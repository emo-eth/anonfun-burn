// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ILpLocker} from "./lib/ILpLocker.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {IUniswapV3Pool} from "uniswap-v3-core/interfaces/IUniswapV3Pool.sol";
import {IV3SwapRouter} from "./lib/IV3SwapRouter.sol";
import {TickMath} from "uniswap-v3-core/libraries/TickMath.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title UniV3Rebuyer
 * @notice Handles automated rebuying of tokens using Uniswap V3
 * @dev Implements price validation and automated swapping with configurable parameters
 */
contract UniV3Rebuyer is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error NoWethBalance();
    error OnlyExternal(address sender, address origin);
    error PriceDeviationTooHigh(uint256 currentPrice, uint256 recentPrice, uint16 maxDeviationBps);
    error SwapTooSoon();
    error Paused();

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    ILpLocker public constant LP_LOCKER = ILpLocker(payable(0x6521962E1f587B5fF3F8B5F2Ca52960013E2Ccd3));
    uint256 public constant LP_TOKEN_ID = 1150923;
    uint24 public constant POOL_FEE = 10000; // 1% in 100th of basis points
    IUniswapV3Pool public constant POOL = IUniswapV3Pool(0xc4eCaf115CBcE3985748c58dccfC4722fEf8247c);
    IERC20 public constant TARGET = IERC20(0x0Db510e79909666d6dEc7f5e49370838c16D950f);
    IV3SwapRouter public constant V3_ROUTER = IV3SwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481);
    IERC20 public constant WETH = IERC20(0x4200000000000000000000000000000000000006);

    /*//////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/
    struct UniV3RebuyerStorage {
        uint96 maxAmountOutPerTx; // Maximum amount of tokens to swap per transaction
        uint40 minSwapDelay; // Minimum time between swaps
        uint40 lastSwapTimestamp; // Timestamp of last swap
        uint16 maxDeviationBps; // Maximum allowed price deviation in basis points
        bool paused; // Pause flag
    }

    // Getters
    function getMaxAmountOutPerTx() public view returns (uint96) {
        return getStorage().maxAmountOutPerTx;
    }

    function getMinSwapDelay() public view returns (uint40) {
        return getStorage().minSwapDelay;
    }

    function getLastSwapTimestamp() public view returns (uint40) {
        return getStorage().lastSwapTimestamp;
    }

    function getMaxDeviationBps() public view returns (uint16) {
        return getStorage().maxDeviationBps;
    }

    function isPaused() public view returns (bool) {
        return getStorage().paused;
    }

    // Individual setters
    function setMaxAmountOutPerTx(uint96 _maxAmountOutPerTx) external onlyOwner {
        UniV3RebuyerStorage storage store = getStorage();
        store.maxAmountOutPerTx = _maxAmountOutPerTx;
    }

    function setMinSwapDelay(uint40 _minSwapDelay) external onlyOwner {
        UniV3RebuyerStorage storage store = getStorage();
        store.minSwapDelay = _minSwapDelay;
    }

    function setMaxDeviationBps(uint16 _maxDeviationBps) external onlyOwner {
        UniV3RebuyerStorage storage store = getStorage();
        store.maxDeviationBps = _maxDeviationBps;
    }

    function setPaused(bool _paused) external onlyOwner {
        UniV3RebuyerStorage storage store = getStorage();
        store.paused = _paused;
    }

    // Bulk setter
    function setParameters(uint96 _maxAmountOutPerTx, uint40 _minSwapDelay, uint16 _maxDeviationBps, bool _paused)
        external
        onlyOwner
    {
        UniV3RebuyerStorage storage store = getStorage();
        store.maxAmountOutPerTx = _maxAmountOutPerTx;
        store.minSwapDelay = _minSwapDelay;
        store.maxDeviationBps = _maxDeviationBps;
        store.paused = _paused;
    }

    // Storage slot for contract state
    // Calculated as: keccak256(abi.encode(uint256(keccak256("anonfun.storage.UniV3Rebuyer")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION = 0x95ae5b4e88679a4503d661690feb05ae9b31f5f327a7dbf5dabf5a692f687b00;

    /*//////////////////////////////////////////////////////////////
                            CORE LOGIC
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Main function to execute token swaps using default LP locker
     * @dev Collects fees, validates price, and executes swap
     */
    function claimAndBurn() external {
        UniV3RebuyerStorage memory store = getStorage();
        _validateCallerAndTimestamp(store);
        claimFromLpLocker(address(LP_LOCKER), LP_TOKEN_ID);
        swapAndBurn(store);
    }

    /**
     * @notice Main function to execute token swaps using custom LP locker
     * @param locker Address of LP locker contract
     * @param tokenId ID of LP token
     */
    function claimAndBurn(address locker, uint256 tokenId) public {
        UniV3RebuyerStorage memory store = getStorage();
        _validateCallerAndTimestamp(store);
        claimFromLpLocker(locker, tokenId);
        swapAndBurn(store);
    }

    /**
     * @notice Claims fees from LP locker
     * @param locker Address of LP locker contract
     * @param tokenId ID of LP token
     */
    function claimFromLpLocker(address locker, uint256 tokenId) public {
        ILpLocker(payable(locker)).collectFees(address(this), tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Validates caller is EOA and enough time has passed since last swap
     * @param store Storage struct containing timing parameters
     */
    function _validateCallerAndTimestamp(UniV3RebuyerStorage memory store) internal view {
        // Prevent same-tx sandwich attacks pre-Pectra hardfork
        if (msg.sender != tx.origin) revert OnlyExternal(msg.sender, tx.origin);
        if (block.timestamp - store.lastSwapTimestamp < store.minSwapDelay) {
            revert SwapTooSoon();
        }
        if (store.paused) revert Paused();
    }

    /**
     * @notice Executes swap and burns received tokens
     * @param store Storage struct containing swap parameters
     */
    function swapAndBurn(UniV3RebuyerStorage memory store) internal {
        uint256 amountToSwap = _getAmountToSwap(store);
        if (amountToSwap == 0) {
            revert NoWethBalance();
        }

        // Validate price and get max sqrt price limit
        uint256 maxSqrtPriceX96 = _validatePrice(store.maxDeviationBps);

        // Execute swap on Uniswap V3
        uint256 amountOut = V3_ROUTER.exactInputSingle(
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: address(WETH),
                tokenOut: address(TARGET),
                fee: POOL_FEE,
                recipient: address(this),
                amountIn: amountToSwap,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: uint160(maxSqrtPriceX96)
            })
        );

        getStorage().lastSwapTimestamp = uint40(block.timestamp);

        // Burn received tokens
        TARGET.transfer(address(0xdead), amountOut);
    }

    /**
     * @notice Calculates the amount of tokens to swap
     * @param store Storage struct containing max amount settings
     * @return Amount of tokens to swap, capped by maxAmountOutPerTx
     */
    function _getAmountToSwap(UniV3RebuyerStorage memory store) private view returns (uint256) {
        uint256 wethBalance = WETH.balanceOf(address(this));
        return wethBalance < store.maxAmountOutPerTx ? wethBalance : store.maxAmountOutPerTx;
    }

    /**
     * @notice Validates that the current price is not too far from the recent price
     * @param maxDeviationBps The maximum allowed deviation in basis points (1 bp = 0.01%)
     * @return maxSqrtPriceX96 The maximum sqrt price ratio allowed
     */
    function _validatePrice(uint16 maxDeviationBps) internal view returns (uint256) {
        // Get current pool state
        (, int24 currentTick,,,,,) = POOL.slot0();

        // Set up observation window (current and previous block)
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 2; // previous block
        secondsAgos[1] = 0; // current block

        // Get pool observations for price validation
        (int56[] memory tickCumulatives,) = POOL.observe(secondsAgos);

        // Calculate time between observations

        // Calculate time-weighted average tick
        int24 arithmeticMeanTick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(2));

        // Calculate tick difference and compare to max deviation
        int24 tickDifference = currentTick - arithmeticMeanTick;

        // Each tick represents ~0.01% price change (~1 basis point)
        // Convert maxDeviationBps to equivalent tick range
        int24 maxTickDeviation = int24(uint24(maxDeviationBps));

        // Revert if price difference between this block and last is too high
        if (tickDifference > maxTickDeviation) {
            revert PriceDeviationTooHigh(
                uint256(uint24(currentTick)), uint256(uint24(arithmeticMeanTick)), maxDeviationBps
            );
        }

        // Add safety margin for max swap price to mitigate out-of-range swaps
        int24 maxTick = currentTick + int24(uint24(maxDeviationBps));
        return TickMath.getSqrtRatioAtTick(maxTick);
    }

    /**
     * @notice Gets the storage pointer for the contract
     * @return store Storage struct pointer
     */
    function getStorage() private pure returns (UniV3RebuyerStorage storage store) {
        assembly {
            store.slot := STORAGE_LOCATION
        }
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Initializes the contract
     * @param maxAmountOutPerTx Maximum amount allowed per transaction
     * @param minSwapDelay Minimum delay between swaps
     * @param maxDeviationBps Maximum price deviation allowed in basis points
     */
    function __UniV3Rebuyer_init(uint96 maxAmountOutPerTx, uint40 minSwapDelay, uint16 maxDeviationBps) internal {
        __UniV3Rebuyer_init_unchained(maxAmountOutPerTx, minSwapDelay, maxDeviationBps);
    }

    /**
     * @notice Unchained initialization logic
     * @param maxAmountOutPerTx Maximum amount allowed per transaction
     * @param minSwapDelay Minimum delay between swaps
     * @param maxDeviationBps Maximum price deviation allowed in basis points
     */
    function __UniV3Rebuyer_init_unchained(uint96 maxAmountOutPerTx, uint40 minSwapDelay, uint16 maxDeviationBps)
        internal
        onlyInitializing
    {
        UniV3RebuyerStorage storage store = getStorage();
        store.maxAmountOutPerTx = maxAmountOutPerTx;
        store.minSwapDelay = minSwapDelay;
        store.maxDeviationBps = maxDeviationBps;
        WETH.approve(address(V3_ROUTER), type(uint256).max);
    }

    function reinitialize(uint64 version, uint96 maxAmountOutPerTx, uint40 minSwapDelay, uint16 maxDeviationBps)
        public
        reinitializer(version)
    {
        __UniV3Rebuyer_init_unchained(maxAmountOutPerTx, minSwapDelay, maxDeviationBps);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
