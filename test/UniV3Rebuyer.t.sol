// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {
    DeterministicUpgradeableFactory,
    SimpleUpgradeableProxy
} from "src/proxy/DeterministicUpgradeableFactory.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC1967} from "openzeppelin-contracts/interfaces/IERC1967.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ILpLocker} from "src/lib/ILpLocker.sol";
import {IUniswapV3Pool} from "uniswap-v3-core/interfaces/IUniswapV3Pool.sol";
import {IV3SwapRouter} from "src/lib/IV3SwapRouter.sol";
import {MockLpLockerV2} from "./helpers/MockLpLockerV2.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {Test} from "forge-std/Test.sol";
import {TickMath} from "uniswap-v3-core/libraries/TickMath.sol";
import {UniV3Rebuyer} from "src/UniV3Rebuyer.sol";
// Helper contract for testing non-EOA calls

contract ContractCaller {
    function call(UniV3Rebuyer _rebuyer) external {
        _rebuyer.claimAndBurn();
    }
}

contract MockOwnable is Ownable {
    constructor(address owner) Ownable(owner) {}
}

/**
 * @title UniV3RebuyerTest
 * @notice Test contract for UniV3Rebuyer functionality
 */
contract UniV3RebuyerTest is Test {
    using stdStorage for StdStorage;

    // Constants
    uint256 private constant FORK_BLOCK_NUMBER = 23460629;
    uint96 private constant MAX_AMOUNT_PER_TX = 1e18; // 1 WETH
    uint40 private constant MIN_SWAP_DELAY = 1 hours;
    uint16 private constant MAX_DEVIATION_BPS = 10; // 0.1%

    // Core protocol contracts
    ILpLocker private constant LP_LOCKER =
        ILpLocker(payable(0x6521962E1f587B5fF3F8B5F2Ca52960013E2Ccd3));
    IUniswapV3Pool private constant POOL =
        IUniswapV3Pool(0xc4eCaf115CBcE3985748c58dccfC4722fEf8247c);
    IV3SwapRouter private constant V3_ROUTER =
        IV3SwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481);
    IERC20 private constant WETH = IERC20(0x4200000000000000000000000000000000000006);
    IERC20 private constant TARGET = IERC20(0x0Db510e79909666d6dEc7f5e49370838c16D950f);

    // Test state variables
    uint256 private baseFork;
    uint256 private constant LP_TOKEN_ID = 1150923;
    address private swapper;
    DeterministicUpgradeableFactory private factory;
    UniV3Rebuyer private implementation;
    UniV3Rebuyer private rebuyer;
    MockLpLockerV2 private mockLpLockerV2;

    function setUp() public {
        // Setup labels and fork
        vm.label(address(WETH), "WETH");
        vm.label(address(TARGET), "TARGET");
        baseFork = vm.createSelectFork(getChain("base").rpcUrl, FORK_BLOCK_NUMBER);

        // Deploy core contracts
        factory = new DeterministicUpgradeableFactory();
        implementation = new UniV3Rebuyer();
        mockLpLockerV2 = new MockLpLockerV2();

        // Deploy and initialize proxy
        SimpleUpgradeableProxy proxy =
            SimpleUpgradeableProxy(factory.deployDeterministicUUPS(0, address(this)));
        proxy.upgradeToAndCall(
            address(implementation),
            abi.encodeCall(
                UniV3Rebuyer.reinitialize,
                (2, MAX_AMOUNT_PER_TX, MIN_SWAP_DELAY, MAX_DEVIATION_BPS, address(mockLpLockerV2))
            )
        );
        rebuyer = UniV3Rebuyer(payable(address(proxy)));

        // Transfer LP_LOCKER ownership
        address lpLockerOwner = LP_LOCKER.owner();
        vm.prank(lpLockerOwner);
        LP_LOCKER.transferOwnership(address(rebuyer));

        // Setup test accounts and balances
        deal(address(WETH), address(rebuyer), 10e18);
        swapper = makeAddr("swapper");

        // Approve router spending
        vm.startPrank(swapper);
        WETH.approve(address(V3_ROUTER), type(uint256).max);
        TARGET.approve(address(V3_ROUTER), type(uint256).max);
        vm.stopPrank();
    }

    function testClaimAndBurn_WhenPriceDeviates() public {
        int24 currentTick = getCurrentTick();
        int24 newTick = currentTick + int24(uint24(MAX_DEVIATION_BPS + 100));
        newTick = manipulatePoolPrice(newTick);

        vm.expectRevert(
            abi.encodeWithSelector(
                UniV3Rebuyer.PriceDeviationTooHigh.selector,
                uint256(uint24(newTick)),
                uint256(uint24(currentTick)),
                MAX_DEVIATION_BPS
            )
        );
        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn();
    }

    function testClaimAndBurn_TooSoon() public {
        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn();

        vm.expectRevert(UniV3Rebuyer.SwapTooSoon.selector);
        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn();

        skip(MIN_SWAP_DELAY);
        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn();
    }

    function testClaimAndBurn_WhenPaused() public {
        rebuyer.setPaused(true);
        vm.expectRevert(UniV3Rebuyer.Paused.selector);
        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn();
    }

    function testClaimAndBurn_SwapsUpToLimit() public {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 2 seconds);

        deal(address(WETH), address(rebuyer), 100e18);
        rebuyer.setMaxAmountOutPerTx(100e18);

        uint128 currentLiquidity = POOL.liquidity();
        stdstore.target(address(POOL)).sig("liquidity()").checked_write(currentLiquidity / 1000000);

        (, int24 initialTick,,,,,) = POOL.slot0();

        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn();

        (, int24 finalTick,,,,,) = POOL.slot0();

        assertEq(finalTick - initialTick, int24(uint24(MAX_DEVIATION_BPS)));
    }

    function testClaimAndBurn_NoWethBalance() public {
        rebuyer.claimFromLpLocker(address(LP_LOCKER), LP_TOKEN_ID);
        uint256 rebuyerBalance = WETH.balanceOf(address(rebuyer));
        vm.prank(address(rebuyer));
        WETH.transfer(address(0xdead), rebuyerBalance);

        vm.prank(address(this), address(this));
        vm.expectRevert(UniV3Rebuyer.NoWethBalance.selector);
        rebuyer.claimAndBurn();
    }

    // Admin functionality tests
    function testUpgrade() public {
        UniV3Rebuyer newImplementation = new UniV3Rebuyer();

        vm.prank(address(this));
        vm.expectEmit(true, true, true, true);
        emit IERC1967.Upgraded(address(newImplementation));
        rebuyer.upgradeToAndCall(
            address(newImplementation),
            abi.encodeCall(
                UniV3Rebuyer.reinitialize,
                (3, MAX_AMOUNT_PER_TX, MIN_SWAP_DELAY, MAX_DEVIATION_BPS, makeAddr("newLpLockerV2"))
            )
        );
    }

    function testReinitialize() public {
        vm.prank(address(this));
        rebuyer.reinitialize(3, 2e18, 2 hours, 20, makeAddr("newLpLockerV2"));

        assertEq(rebuyer.getMaxAmountOutPerTx(), 2e18);
        assertEq(rebuyer.getMinSwapDelay(), 2 hours);
        assertEq(rebuyer.getMaxIncreaseBps(), 20);
        assertEq(rebuyer.getLpLockerV2(), makeAddr("newLpLockerV2"));
    }

    function testUpgrade_OnlyOwner() public {
        UniV3Rebuyer newImplementation = new UniV3Rebuyer();
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        rebuyer.upgradeToAndCall(
            address(newImplementation),
            abi.encodeCall(
                UniV3Rebuyer.reinitialize,
                (2, MAX_AMOUNT_PER_TX, MIN_SWAP_DELAY, MAX_DEVIATION_BPS, makeAddr("newLpLockerV2"))
            )
        );
    }

    // Parameter setter tests
    function testSetters() public {
        uint96 newMaxAmount = 2e18;
        rebuyer.setMaxAmountOutPerTx(newMaxAmount);
        assertEq(rebuyer.getMaxAmountOutPerTx(), newMaxAmount);

        uint40 newDelay = 2 hours;
        rebuyer.setMinSwapDelay(newDelay);
        assertEq(rebuyer.getMinSwapDelay(), newDelay);

        uint16 newDeviation = 20;
        rebuyer.setMaxIncreaseBps(newDeviation);
        assertEq(rebuyer.getMaxIncreaseBps(), newDeviation);

        rebuyer.setParameters(3e18, 3 hours, 30, true, address(mockLpLockerV2));
        assertEq(rebuyer.getMaxAmountOutPerTx(), 3e18);
        assertEq(rebuyer.getMinSwapDelay(), 3 hours);
        assertEq(rebuyer.getMaxIncreaseBps(), 30);
        assertTrue(rebuyer.isPaused());
        assertEq(rebuyer.getLpLockerV2(), address(mockLpLockerV2));
    }

    function testSetters_OnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.startPrank(nonOwner);

        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        rebuyer.setMaxAmountOutPerTx(2e18);

        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        rebuyer.setMinSwapDelay(2 hours);

        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        rebuyer.setMaxIncreaseBps(20);

        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        rebuyer.setPaused(true);

        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        rebuyer.setParameters(3e18, 3 hours, 30, true, address(mockLpLockerV2));

        vm.stopPrank();
    }

    // Price validation tests
    function testValidatePrice_ObservationWindow() public {
        vm.roll(block.number + 100);

        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn();

        assertLt(WETH.balanceOf(address(rebuyer)), 10e18);
    }

    function testValidatePrice_NegativeDeviation() public {
        int24 currentTick = getCurrentTick();
        int24 newTick = currentTick - int24(uint24(MAX_DEVIATION_BPS + 100));

        newTick = manipulatePoolPrice(newTick);

        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn();
    }

    // Initialization tests
    function testInitialization() public {
        assertEq(rebuyer.getMaxAmountOutPerTx(), MAX_AMOUNT_PER_TX);
        assertEq(rebuyer.getMinSwapDelay(), MIN_SWAP_DELAY);
        assertEq(rebuyer.getMaxIncreaseBps(), MAX_DEVIATION_BPS);
        assertEq(WETH.allowance(address(rebuyer), address(V3_ROUTER)), type(uint256).max);
    }

    // LP Locker V2 tests
    function testClaimFromLpLockerV2Single() public {
        vm.expectEmit(true, false, false, false);
        emit MockLpLockerV2.RewardsCollected(LP_TOKEN_ID);

        rebuyer.claimFromLpLockerV2(LP_TOKEN_ID);
    }

    function testClaimFromLpLockerV2Array() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        vm.expectEmit(true, false, false, false);
        emit MockLpLockerV2.RewardsCollected(1);
        vm.expectEmit(true, false, false, false);
        emit MockLpLockerV2.RewardsCollected(2);

        rebuyer.claimFromLpLockerV2(tokenIds);
    }

    function testClaimFromLpLockerArray() public {
        uint256 initialBalance = WETH.balanceOf(address(rebuyer));
        UniV3Rebuyer.LpLocker[] memory lockers = new UniV3Rebuyer.LpLocker[](2);
        lockers[0] = UniV3Rebuyer.LpLocker({locker: address(LP_LOCKER), tokenId: LP_TOKEN_ID});
        lockers[1] = UniV3Rebuyer.LpLocker({locker: address(LP_LOCKER), tokenId: LP_TOKEN_ID});

        rebuyer.claimFromLpLocker(lockers);

        assertLt(initialBalance, WETH.balanceOf(address(rebuyer)));
    }

    // Helper functions
    function getCurrentTick() internal view returns (int24) {
        (, int24 currentTick,,,,,) = POOL.slot0();
        return currentTick;
    }

    /**
     * @notice Manipulates pool price by performing swaps
     * @param targetTick The target tick to manipulate price to
     * @return actualNewTick The actual new tick after manipulation
     */
    function manipulatePoolPrice(int24 targetTick) internal returns (int24 actualNewTick) {
        int24 currentTick = getCurrentTick();
        bool moveUp = targetTick > currentTick;
        uint256 swapAmount = 1000e18;

        while (getCurrentTick() != targetTick) {
            if (moveUp) {
                deal(address(WETH), swapper, swapAmount);
            } else {
                deal(address(TARGET), swapper, swapAmount);
            }

            vm.prank(swapper);
            if (moveUp) {
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

            actualNewTick = getCurrentTick();
            if ((moveUp && actualNewTick > targetTick) || (!moveUp && actualNewTick < targetTick)) {
                break;
            }

            swapAmount = swapAmount * 2;
        }
    }

    // Add these tests after the initialization tests

    function testGetLastSwapTimestamp() public {
        // Initial timestamp should be 0
        assertEq(rebuyer.getLastSwapTimestamp(), 0);

        // Perform a swap to update timestamp
        vm.prank(address(this), address(this));
        rebuyer.claimAndBurn();

        // Verify timestamp was updated
        assertEq(rebuyer.getLastSwapTimestamp(), block.timestamp);
    }

    function testInitFunction() public {
        // Deploy proxy pointing to new implementation
        bytes memory initData = abi.encodeCall(
            UniV3Rebuyer.initialize,
            (
                address(this),
                MAX_AMOUNT_PER_TX,
                MIN_SWAP_DELAY,
                MAX_DEVIATION_BPS,
                makeAddr("newLpLockerV2")
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        UniV3Rebuyer newRebuyer = UniV3Rebuyer(payable(proxy));

        // Verify initialization
        assertEq(newRebuyer.getMaxAmountOutPerTx(), MAX_AMOUNT_PER_TX);
        assertEq(newRebuyer.getMinSwapDelay(), MIN_SWAP_DELAY);
        assertEq(newRebuyer.getMaxIncreaseBps(), MAX_DEVIATION_BPS);
        assertEq(newRebuyer.getLpLockerV2(), makeAddr("newLpLockerV2"));
    }

    function testValidateCallerAndTimestamp_NonEOA() public {
        // Create a contract caller
        ContractCaller caller = new ContractCaller();
        address contractCaller = address(caller);

        vm.prank(contractCaller, address(this));
        vm.expectRevert(
            abi.encodeWithSelector(
                UniV3Rebuyer.OnlyExternal.selector, contractCaller, address(this)
            )
        );
        caller.call(rebuyer);
    }

    function testReceive() public {
        // test that sending ether to the rebuyer converts it to weth
        uint256 initialWethBalance = WETH.balanceOf(address(rebuyer));

        (bool success,) = address(rebuyer).call{value: 1 ether}("");
        assertTrue(success);

        assertEq(WETH.balanceOf(address(rebuyer)), initialWethBalance + 1 ether);
    }

    // Add these tests after the other test functions

    function testSwapAndBurn() public {
        // Setup initial state
        deal(address(WETH), address(rebuyer), 10e18);
        uint256 initialWethBalance = WETH.balanceOf(address(rebuyer));
        uint256 initialTargetBalance = TARGET.balanceOf(address(0xdead));

        // Execute swap
        vm.prank(address(this), address(this));
        rebuyer.swapAndBurn();

        // Verify WETH was spent
        assertLt(WETH.balanceOf(address(rebuyer)), initialWethBalance);
        // Verify TARGET was burned (sent to 0xdead)
        assertGt(TARGET.balanceOf(address(0xdead)), initialTargetBalance);
    }

    function testSwapAndBurn_WhenPaused() public {
        rebuyer.setPaused(true);
        vm.expectRevert(UniV3Rebuyer.Paused.selector);
        vm.prank(address(this), address(this));
        rebuyer.swapAndBurn();
    }

    function testSwapAndBurn_NonEOA() public {
        ContractCaller caller = new ContractCaller();
        vm.prank(address(caller), address(this));
        vm.expectRevert(
            abi.encodeWithSelector(
                UniV3Rebuyer.OnlyExternal.selector, address(caller), address(this)
            )
        );
        rebuyer.swapAndBurn();
    }

    function testSwapAndBurn_TooSoon() public {
        // First swap
        vm.prank(address(this), address(this));
        rebuyer.swapAndBurn();

        // Try to swap again immediately
        vm.expectRevert(UniV3Rebuyer.SwapTooSoon.selector);
        vm.prank(address(this), address(this));
        rebuyer.swapAndBurn();

        // Wait for delay and verify swap works
        skip(MIN_SWAP_DELAY);
        vm.prank(address(this), address(this));
        rebuyer.swapAndBurn();
    }

    function testSwapAndBurn_NoWethBalance() public {
        // Transfer away all WETH
        uint256 rebuyerBalance = WETH.balanceOf(address(rebuyer));
        vm.prank(address(rebuyer));
        WETH.transfer(address(0xdead), rebuyerBalance);

        vm.prank(address(this), address(this));
        vm.expectRevert(UniV3Rebuyer.NoWethBalance.selector);
        rebuyer.swapAndBurn();
    }

    function testSwapAndBurn_PriceDeviation() public {
        int24 currentTick = getCurrentTick();
        int24 newTick = currentTick + int24(uint24(MAX_DEVIATION_BPS + 100));
        newTick = manipulatePoolPrice(newTick);

        vm.expectRevert(
            abi.encodeWithSelector(
                UniV3Rebuyer.PriceDeviationTooHigh.selector,
                uint256(uint24(newTick)),
                uint256(uint24(currentTick)),
                MAX_DEVIATION_BPS
            )
        );
        vm.prank(address(this), address(this));
        rebuyer.swapAndBurn();
    }

    function testTransferUnderlyingOwnership() public {
        // Deploy a mock ownable contract to transfer
        MockOwnable mockOwnable = new MockOwnable(address(rebuyer));
        address newOwner = makeAddr("newOwner");

        // Transfer ownership through rebuyer
        vm.prank(address(this));
        rebuyer.transferUnderlyingOwnership(address(mockOwnable), newOwner);

        // Verify ownership was transferred
        assertEq(mockOwnable.owner(), newOwner);
    }

    function testTransferUnderlyingOwnership_OnlyOwner() public {
        MockOwnable mockOwnable = new MockOwnable(address(rebuyer));
        address nonOwner = makeAddr("nonOwner");
        address newOwner = makeAddr("newOwner");

        // Attempt transfer from non-owner should fail
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        rebuyer.transferUnderlyingOwnership(address(mockOwnable), newOwner);
    }

    function testSetLpLockerV2() public {
        address newLocker = makeAddr("newLocker");

        vm.prank(address(this));
        rebuyer.setLpLockerV2(newLocker);

        assertEq(rebuyer.getLpLockerV2(), newLocker);
    }

    function testSetLpLockerV2_OnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");
        address newLocker = makeAddr("newLocker");

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        rebuyer.setLpLockerV2(newLocker);
    }

    function testSetParameters_WithLpLockerV2() public {
        uint96 newMaxAmount = 2e18;
        uint40 newDelay = 2 hours;
        uint16 newDeviation = 20;
        bool newPaused = true;
        address newLocker = makeAddr("newLocker");

        rebuyer.setParameters(newMaxAmount, newDelay, newDeviation, newPaused, newLocker);

        assertEq(rebuyer.getMaxAmountOutPerTx(), newMaxAmount);
        assertEq(rebuyer.getMinSwapDelay(), newDelay);
        assertEq(rebuyer.getMaxIncreaseBps(), newDeviation);
        assertTrue(rebuyer.isPaused());
        assertEq(rebuyer.getLpLockerV2(), newLocker);
    }

    function testClaimFromLpLockerV2_Single() public {
        address newLocker = address(mockLpLockerV2);
        uint256 tokenId = 123;

        vm.prank(address(this));
        rebuyer.setLpLockerV2(newLocker);

        vm.expectEmit(true, false, false, false);
        emit MockLpLockerV2.RewardsCollected(tokenId);

        rebuyer.claimFromLpLockerV2(tokenId);
    }

    function testClaimFromLpLockerV2_Array() public {
        address newLocker = address(mockLpLockerV2);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 123;
        tokenIds[1] = 456;

        vm.prank(address(this));
        rebuyer.setLpLockerV2(newLocker);

        vm.expectEmit(true, false, false, false);
        emit MockLpLockerV2.RewardsCollected(tokenIds[0]);
        vm.expectEmit(true, false, false, false);
        emit MockLpLockerV2.RewardsCollected(tokenIds[1]);

        rebuyer.claimFromLpLockerV2(tokenIds);
    }

    function testClaimFromLpLockerV2_NoLockerSet() public {
        uint256 tokenId = 123;
        rebuyer.setLpLockerV2(address(0));

        vm.expectRevert(UniV3Rebuyer.NoLpLockerV2Set.selector);
        rebuyer.claimFromLpLockerV2(tokenId);
    }

    function testClaimFromLpLockerV2Array_EmptyArray() public {
        address newLocker = address(mockLpLockerV2);
        uint256[] memory tokenIds = new uint256[](0);

        vm.prank(address(this));
        rebuyer.setLpLockerV2(newLocker);

        rebuyer.claimFromLpLockerV2(tokenIds);
    }

    function testSetParameters_OnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        rebuyer.setParameters(2e18, 2 hours, 20, true, address(0));
    }

    function testClaimFromLpLockerV2Array_NoLockerSet() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 123;
        tokenIds[1] = 456;

        rebuyer.setLpLockerV2(address(0));

        vm.expectRevert(UniV3Rebuyer.NoLpLockerV2Set.selector);
        rebuyer.claimFromLpLockerV2(tokenIds);
    }

    function testUpgrade2() public {
        vm.createSelectFork(getChain("base").rpcUrl);
        address verifyingContract = vm.envAddress("VERIFYING_CONTRACT");
        address impl = address(new UniV3Rebuyer());
        UniV3Rebuyer buyer = UniV3Rebuyer(payable(verifyingContract));
        address owner = buyer.owner();
        vm.prank(owner);
        buyer.upgradeToAndCall(impl, "");
    }
}
