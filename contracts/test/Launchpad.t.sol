// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Launchpad} from "../src/Launchpad.sol";
import {LiquidityLocker} from "../src/LiquidityLocker.sol";
import {DevVesting} from "../src/DevVesting.sol";
import {MemeToken} from "../src/MemeToken.sol";

import {MockUniswapV2Factory} from "./mocks/MockUniswapV2Factory.sol";
import {MockUniswapV2Router} from "./mocks/MockUniswapV2Router.sol";
import {MockUniswapV2Pair} from "./mocks/MockUniswapV2Pair.sol";
import {MockWETH} from "./mocks/MockWETH.sol";

contract LaunchpadTest is Test {
    Launchpad internal launchpad;
    LiquidityLocker internal locker;
    DevVesting internal vesting;

    MockUniswapV2Factory internal factory;
    MockUniswapV2Router internal router;
    MockWETH internal weth;

    address internal owner = makeAddr("owner");
    address internal treasury = makeAddr("treasury");
    address internal dev = makeAddr("dev");

    function setUp() public {
        weth = new MockWETH();
        factory = new MockUniswapV2Factory();
        router = new MockUniswapV2Router(address(factory), address(weth));

        locker = new LiquidityLocker();
        vesting = new DevVesting();

        launchpad = new Launchpad({
            router_: address(router),
            liquidityLocker_: address(locker),
            devVesting_: address(vesting),
            treasury_: treasury,
            owner_: owner
        });

        vm.deal(dev, 100 ether);
    }

    function _defaultParams() internal pure returns (Launchpad.LaunchParams memory) {
        return Launchpad.LaunchParams({
            name: "PepeXL",
            symbol: "PXL",
            totalSupply: 1_000_000,
            buyTaxBps: 300,
            sellTaxBps: 500,
            maxWalletBps: 200,
            maxTxBps: 100,
            devAllocationBps: 300, // 3%
            lockDuration: 200 days
        });
    }

    function test_launch_collectsPlatformFee() public {
        Launchpad.LaunchParams memory p = _defaultParams();
        uint256 ethSent = 5 ether;

        uint256 treasuryBefore = treasury.balance;

        vm.prank(dev);
        launchpad.launch{value: ethSent}(p);

        uint256 expectedFee = (ethSent * 100) / 10000; // 1%
        assertEq(treasury.balance - treasuryBefore, expectedFee, "platform fee not collected");
    }

    function test_launch_createsLockedLP() public {
        Launchpad.LaunchParams memory p = _defaultParams();

        vm.prank(dev);
        address token = launchpad.launch{value: 5 ether}(p);

        Launchpad.LaunchInfo memory info = launchpad.getLaunchByToken(token);
        LiquidityLocker.Lock memory lock = locker.getLock(info.lockId);
        assertEq(lock.owner, dev, "dev owns the lock");
        assertEq(lock.token, info.pair, "pair is locked");
        assertGt(lock.amount, 0, "lp amount > 0");
        assertEq(lock.unlockAt, block.timestamp + p.lockDuration);
        assertFalse(lock.withdrawn);
    }

    function test_launch_createsDevVesting() public {
        Launchpad.LaunchParams memory p = _defaultParams();

        vm.prank(dev);
        address token = launchpad.launch{value: 5 ether}(p);

        Launchpad.LaunchInfo memory info = launchpad.getLaunchByToken(token);
        DevVesting.Schedule memory s = vesting.getSchedule(info.vestingId);
        assertEq(s.beneficiary, dev);
        assertEq(s.token, token);

        // 3% of 1_000_000 tokens = 30_000 tokens (with 18 decimals).
        uint256 expectedDevAmount = 30_000 * 1e18;
        assertEq(s.totalAmount, expectedDevAmount);
    }

    function test_launch_opensTradingAndTransfersOwnership() public {
        Launchpad.LaunchParams memory p = _defaultParams();
        vm.prank(dev);
        address tokenAddr = launchpad.launch{value: 5 ether}(p);

        MemeToken token = MemeToken(tokenAddr);
        assertTrue(token.tradingOpen(), "trading must be open");
        assertEq(token.owner(), dev, "ownership transferred to dev");
    }

    function test_launch_revertsBelowMinLiquidity() public {
        Launchpad.LaunchParams memory p = _defaultParams();
        vm.prank(dev);
        vm.expectRevert(Launchpad.InsufficientLiquidity.selector);
        launchpad.launch{value: 0.001 ether}(p);
    }

    function test_launch_revertsAboveMaxTax() public {
        Launchpad.LaunchParams memory p = _defaultParams();
        p.buyTaxBps = 600;
        vm.prank(dev);
        vm.expectRevert(Launchpad.TaxTooHigh.selector);
        launchpad.launch{value: 1 ether}(p);
    }

    function test_launch_revertsAboveMaxDevAllocation() public {
        Launchpad.LaunchParams memory p = _defaultParams();
        p.devAllocationBps = 600;
        vm.prank(dev);
        vm.expectRevert(Launchpad.DevAllocationTooHigh.selector);
        launchpad.launch{value: 1 ether}(p);
    }

    function test_launch_revertsBelowMinLockDuration() public {
        Launchpad.LaunchParams memory p = _defaultParams();
        p.lockDuration = 30 days;
        vm.prank(dev);
        vm.expectRevert(Launchpad.LockTooShort.selector);
        launchpad.launch{value: 1 ether}(p);
    }

    function test_launch_zeroDevAllocation_skipsVesting() public {
        Launchpad.LaunchParams memory p = _defaultParams();
        p.devAllocationBps = 0;

        vm.prank(dev);
        address token = launchpad.launch{value: 1 ether}(p);

        Launchpad.LaunchInfo memory info = launchpad.getLaunchByToken(token);
        assertEq(info.vestingId, type(uint256).max, "no vesting created");
    }

    function test_launch_recordsInRegistry() public {
        Launchpad.LaunchParams memory p = _defaultParams();
        vm.prank(dev);
        address token = launchpad.launch{value: 1 ether}(p);

        assertEq(launchpad.totalLaunches(), 1);
        Launchpad.LaunchInfo memory info = launchpad.getLaunchByToken(token);
        assertEq(info.token, token);
        assertEq(info.dev, dev);
    }

    function test_launch_devCannotWithdrawLockEarly() public {
        Launchpad.LaunchParams memory p = _defaultParams();
        vm.prank(dev);
        address token = launchpad.launch{value: 1 ether}(p);

        Launchpad.LaunchInfo memory info = launchpad.getLaunchByToken(token);

        skip(p.lockDuration - 1);
        vm.prank(dev);
        vm.expectRevert(LiquidityLocker.StillLocked.selector);
        locker.withdraw(info.lockId);
    }

    function test_launch_devCannotClaimVestingBeforeCliff() public {
        Launchpad.LaunchParams memory p = _defaultParams();
        vm.prank(dev);
        address token = launchpad.launch{value: 1 ether}(p);

        Launchpad.LaunchInfo memory info = launchpad.getLaunchByToken(token);

        skip(29 days);
        vm.prank(dev);
        vm.expectRevert(DevVesting.NothingToRelease.selector);
        vesting.release(info.vestingId);
    }

    function test_setTreasury_onlyOwner() public {
        address newTreasury = makeAddr("newT");
        vm.prank(makeAddr("intruder"));
        vm.expectRevert();
        launchpad.setTreasury(newTreasury);

        vm.prank(owner);
        launchpad.setTreasury(newTreasury);
        assertEq(launchpad.treasury(), newTreasury);
    }
}
