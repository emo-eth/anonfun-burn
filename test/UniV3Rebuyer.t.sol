// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {UniV3Rebuyer} from "src/UniV3Rebuyer.sol";
import {DeterministicUpgradeableFactory, SimpleUpgradeableProxy} from "src/proxy/DeterministicUpgradeableFactory.sol";
import {ILpLocker} from "src/lib/ILpLocker.sol";
import {IUniswapV3Pool} from "uniswap-v3-core/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IV3SwapRouter} from "src/lib/IV3SwapRouter.sol";
import {TickMath} from "uniswap-v3-core/libraries/TickMath.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {console2} from "forge-std/console2.sol";
import {TickMath} from "uniswap-v3-core/libraries/TickMath.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC1967} from "openzeppelin-contracts/interfaces/IERC1967.sol";

contract UniV3RebuyerTest is Test {
    uint256 baseFork;
    uint256 constant FORK_BLOCK_NUMBER = 23460629; // Choose an appropriate Base block number

    using stdStorage for StdStorage;

    DeterministicUpgradeableFactory factory;
    UniV3Rebuyer implementation;
    UniV3Rebuyer rebuyer;

    // Constants from UniV3Rebuyer
    ILpLocker constant LP_LOCKER = ILpLocker(payable(0x6521962E1f587B5fF3F8B5F2Ca52960013E2Ccd3));
    uint256 constant LP_TOKEN_ID = 1150923;
    IUniswapV3Pool constant POOL = IUniswapV3Pool(0xc4eCaf115CBcE3985748c58dccfC4722fEf8247c);
    IERC20 constant WETH = IERC20(0x4200000000000000000000000000000000000006);
    IV3SwapRouter constant V3_ROUTER = IV3SwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481);
    IERC20 constant TARGET = IERC20(0x0Db510e79909666d6dEc7f5e49370838c16D950f);

    // Test parameters
    uint96 constant MAX_AMOUNT_PER_TX = 1e18; // 1 WETH
    uint40 constant MIN_SWAP_DELAY = 1 hours;
    uint16 constant MAX_DEVIATION_BPS = 10; // .1%

    // Add swapper address
    address swapper;

    function setUp() public {
        vm.label(address(WETH), "WETH");
        vm.label(address(TARGET), "TARGET");
        // Setup Base fork
        baseFork = vm.createSelectFork(getChain("base").rpcUrl, FORK_BLOCK_NUMBER);

        // Deploy factory and implementation
        factory = new DeterministicUpgradeableFactory();
        implementation = new UniV3Rebuyer();

        // Deploy proxy
        SimpleUpgradeableProxy proxy = SimpleUpgradeableProxy(factory.deployDeterministicUUPS(0, address(this)));

        // Initialize implementation through proxy
        proxy.upgradeToAndCall(
            address(implementation),
            abi.encodeCall(UniV3Rebuyer.reinitialize, (2, MAX_AMOUNT_PER_TX, MIN_SWAP_DELAY, MAX_DEVIATION_BPS))
        );
        rebuyer = UniV3Rebuyer(address(proxy));

        // Transfer LP_LOCKER ownership to rebuyer
        address lpLockerOwner = LP_LOCKER.owner();
        vm.prank(lpLockerOwner);
        LP_LOCKER.transferOwnership(address(rebuyer));

        // Deal some WETH to test with
        deal(address(WETH), address(rebuyer), 10e18);

        // Create swapper address
        swapper = makeAddr("swapper");

        // Approve router to spend tokens
        vm.startPrank(swapper);
        WETH.approve(address(V3_ROUTER), type(uint256).max);
        TARGET.approve(address(V3_ROUTER), type(uint256).max);
        vm.stopPrank();
    }

    function testClaimAndBurnCustomLocker() public {
        // Test using the same locker and tokenId as the default ones
        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn(address(LP_LOCKER), LP_TOKEN_ID);

        // Verify WETH was spent
        assertLt(WETH.balanceOf(address(rebuyer)), 10e18);
    }

    function testClaimAndBurn_WhenPriceDeviates() public {
        // Manipulate pool price to deviate significantly
        int24 currentTick = getCurrentTick();
        int24 newTick = currentTick + int24(uint24(MAX_DEVIATION_BPS + 100)); // Exceed max deviation

        // Set new price in pool (implementation depends on pool internals)
        newTick = manipulatePoolPrice(newTick);

        // Expect revert due to price deviation
        vm.expectRevert(
            abi.encodeWithSelector(
                UniV3Rebuyer.PriceDeviationTooHigh.selector,
                uint256(uint24(newTick)),
                uint256(uint24(currentTick)),
                MAX_DEVIATION_BPS
            )
        );
        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn(address(LP_LOCKER), LP_TOKEN_ID);
    }

    function testClaimAndBurn_TooSoon() public {
        // First swap
        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn(address(LP_LOCKER), LP_TOKEN_ID);

        // Try again immediately
        vm.expectRevert(UniV3Rebuyer.SwapTooSoon.selector);
        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn(address(LP_LOCKER), LP_TOKEN_ID);

        // Wait and try again
        skip(MIN_SWAP_DELAY);
        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn(address(LP_LOCKER), LP_TOKEN_ID);
    }

    function testClaimAndBurn_WhenPaused() public {
        rebuyer.setPaused(true);
        vm.expectRevert(UniV3Rebuyer.Paused.selector);
        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn(address(LP_LOCKER), LP_TOKEN_ID);
    }

    function testClaimAndBurn_SwapsUpToLimit() public {
        // change to next block and warp 2 seconds
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 2 seconds);

        // deal 100weth to rebuyer
        deal(address(WETH), address(rebuyer), 100e18);
        rebuyer.setMaxAmountOutPerTx(100e18);

        // Find and modify liquidity slot using stdstore
        uint128 currentLiquidity = POOL.liquidity();
        stdstore.target(address(POOL)).sig("liquidity()").checked_write(currentLiquidity / 1000000);

        // get initial tick
        (, int24 initialTick,,,,,) = POOL.slot0();

        // Execute swap
        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn(address(LP_LOCKER), LP_TOKEN_ID);

        // get final tick
        (, int24 finalTick,,,,,) = POOL.slot0();

        // Verify price moved exactly MAX_DEVIATION_BPS ticks
        assertEq(finalTick - initialTick, int24(uint24(MAX_DEVIATION_BPS)));
    }

    function testClaimAndBurn_NoWethBalance() public {
        // Drain WETH balance
        rebuyer.claimFromLpLocker(address(LP_LOCKER), LP_TOKEN_ID);
        uint256 rebuyerBalance = WETH.balanceOf(address(rebuyer));
        vm.prank(address(rebuyer));
        WETH.transfer(address(0xdead), rebuyerBalance);

        // Try to swap with 0 balance
        vm.prank(address(this), address(this));
        vm.expectRevert(UniV3Rebuyer.NoWethBalance.selector);
        rebuyer.claimAndBurn(address(LP_LOCKER), LP_TOKEN_ID);
    }

    function testUpgrade() public {
        // Deploy new implementation
        UniV3Rebuyer newImplementation = new UniV3Rebuyer();

        // Upgrade to new implementation
        vm.prank(address(this));
        // expect emitted events
        vm.expectEmit(true, true, true, true);
        emit IERC1967.Upgraded(address(newImplementation));
        rebuyer.upgradeToAndCall(
            address(newImplementation),
            abi.encodeCall(UniV3Rebuyer.reinitialize, (3, MAX_AMOUNT_PER_TX, MIN_SWAP_DELAY, MAX_DEVIATION_BPS))
        );
    }

    function testReinitialize() public {
        vm.prank(address(this));
        rebuyer.reinitialize(3, 2e18, 2 hours, 20); // Test reinitialization separately

        assertEq(rebuyer.getMaxAmountOutPerTx(), 2e18);
        assertEq(rebuyer.getMinSwapDelay(), 2 hours);
        assertEq(rebuyer.getMaxDeviationBps(), 20);
    }

    function testUpgrade_OnlyOwner() public {
        UniV3Rebuyer newImplementation = new UniV3Rebuyer();

        // Try to upgrade from non-owner
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        rebuyer.upgradeToAndCall(
            address(newImplementation),
            abi.encodeCall(UniV3Rebuyer.reinitialize, (2, MAX_AMOUNT_PER_TX, MIN_SWAP_DELAY, MAX_DEVIATION_BPS))
        );
    }

    function testSetters() public {
        // Test maxAmountOutPerTx
        uint96 newMaxAmount = 2e18;
        rebuyer.setMaxAmountOutPerTx(newMaxAmount);
        assertEq(rebuyer.getMaxAmountOutPerTx(), newMaxAmount);

        // Test minSwapDelay
        uint40 newDelay = 2 hours;
        rebuyer.setMinSwapDelay(newDelay);
        assertEq(rebuyer.getMinSwapDelay(), newDelay);

        // Test maxDeviationBps
        uint16 newDeviation = 20;
        rebuyer.setMaxDeviationBps(newDeviation);
        assertEq(rebuyer.getMaxDeviationBps(), newDeviation);

        // Test bulk setter
        rebuyer.setParameters(3e18, 3 hours, 30, true);
        assertEq(rebuyer.getMaxAmountOutPerTx(), 3e18);
        assertEq(rebuyer.getMinSwapDelay(), 3 hours);
        assertEq(rebuyer.getMaxDeviationBps(), 30);
        assertTrue(rebuyer.isPaused());
    }

    function testSetters_OnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.startPrank(nonOwner);

        // Test each setter reverts for non-owner
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        rebuyer.setMaxAmountOutPerTx(2e18);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        rebuyer.setMinSwapDelay(2 hours);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        rebuyer.setMaxDeviationBps(20);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        rebuyer.setPaused(true);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        rebuyer.setParameters(3e18, 3 hours, 30, true);

        vm.stopPrank();
    }

    function testValidatePrice_ObservationWindow() public {
        // Roll forward many blocks to test observation window
        vm.roll(block.number + 100);

        // Try to swap - should still work since we use current and previous block
        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn(address(LP_LOCKER), LP_TOKEN_ID);

        // Verify the swap succeeded by checking WETH was spent
        assertLt(WETH.balanceOf(address(rebuyer)), 10e18);
    }

    function testValidatePrice_NegativeDeviation() public {
        // Manipulate price downward and verify it also allows negative deviations
        int24 currentTick = getCurrentTick();
        int24 newTick = currentTick - int24(uint24(MAX_DEVIATION_BPS + 100)); // Exceed max deviation

        // Set new price in pool (implementation depends on pool internals)
        newTick = manipulatePoolPrice(newTick);

        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn(address(LP_LOCKER), LP_TOKEN_ID);
    }

    function testInitialization() public {
        assertEq(rebuyer.getMaxAmountOutPerTx(), MAX_AMOUNT_PER_TX);
        assertEq(rebuyer.getMinSwapDelay(), MIN_SWAP_DELAY);
        assertEq(rebuyer.getMaxDeviationBps(), MAX_DEVIATION_BPS);
        assertEq(WETH.allowance(address(rebuyer), address(V3_ROUTER)), type(uint256).max);
    }

    // Helper functions
    function getCurrentTick() internal view returns (int24) {
        (, int24 currentTick,,,,,) = POOL.slot0();
        return currentTick;
    }

    function manipulatePoolPrice(int24 targetTick) internal returns (int24 actualNewTick) {
        int24 currentTick = getCurrentTick();

        // Determine direction of price movement
        bool moveUp = targetTick > currentTick;

        // Calculate amounts for swapping
        uint256 swapAmount = 1000e18; // Large amount to move price significantly

        while (getCurrentTick() != targetTick) {
            // Deal tokens to swapper based on direction
            if (moveUp) {
                deal(address(WETH), swapper, swapAmount);
            } else {
                deal(address(TARGET), swapper, swapAmount);
            }

            vm.prank(swapper);
            if (moveUp) {
                // Swap WETH for TARGET to increase price
                V3_ROUTER.exactInputSingle(
                    IV3SwapRouter.ExactInputSingleParams({
                        tokenIn: address(WETH),
                        tokenOut: address(TARGET),
                        fee: 10000,
                        recipient: swapper,
                        amountIn: swapAmount,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    })
                );
            } else {
                // Swap TARGET for WETH to decrease price
                V3_ROUTER.exactInputSingle(
                    IV3SwapRouter.ExactInputSingleParams({
                        tokenIn: address(TARGET),
                        tokenOut: address(WETH),
                        fee: 10000,
                        recipient: swapper,
                        amountIn: swapAmount,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    })
                );
            }

            // Break if we've moved past the target to avoid infinite loop
            actualNewTick = getCurrentTick();
            if ((moveUp && actualNewTick > targetTick) || (!moveUp && actualNewTick < targetTick)) {
                break;
            }

            // Increase swap amount if price isn't moving enough
            swapAmount = swapAmount * 2;
        }
    }
}
