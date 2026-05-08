// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LiquidityLocker} from "../src/LiquidityLocker.sol";

contract MockLP is ERC20 {
    constructor() ERC20("LP", "LP") {
        _mint(msg.sender, 1_000_000 * 1e18);
    }
}

contract LiquidityLockerTest is Test {
    LiquidityLocker internal locker;
    MockLP internal lp;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        locker = new LiquidityLocker();
        lp = new MockLP();
        lp.transfer(alice, 100_000 * 1e18);
    }

    function test_lock_storesData() public {
        uint256 amount = 1_000 * 1e18;
        uint256 duration = 200 days;

        vm.startPrank(alice);
        lp.approve(address(locker), amount);
        uint256 lockId = locker.lock(address(lp), amount, duration, alice);
        vm.stopPrank();

        LiquidityLocker.Lock memory l = locker.getLock(lockId);
        assertEq(l.token, address(lp));
        assertEq(l.owner, alice);
        assertEq(l.amount, amount);
        assertEq(l.unlockAt, block.timestamp + duration);
        assertFalse(l.withdrawn);
        assertEq(lp.balanceOf(address(locker)), amount);
    }

    function test_lock_revertsBelowMinimumDuration() public {
        vm.startPrank(alice);
        lp.approve(address(locker), 1);
        vm.expectRevert(LiquidityLocker.InvalidDuration.selector);
        locker.lock(address(lp), 1, 30 days, alice);
        vm.stopPrank();
    }

    function test_withdraw_revertsBeforeUnlock() public {
        vm.startPrank(alice);
        lp.approve(address(locker), 100);
        uint256 lockId = locker.lock(address(lp), 100, 200 days, alice);

        vm.expectRevert(LiquidityLocker.StillLocked.selector);
        locker.withdraw(lockId);
        vm.stopPrank();
    }

    function test_withdraw_succeedsAfterUnlock() public {
        vm.startPrank(alice);
        lp.approve(address(locker), 100);
        uint256 lockId = locker.lock(address(lp), 100, 200 days, alice);
        vm.stopPrank();

        skip(201 days);
        uint256 balBefore = lp.balanceOf(alice);

        vm.prank(alice);
        locker.withdraw(lockId);

        assertEq(lp.balanceOf(alice), balBefore + 100);
        assertTrue(locker.getLock(lockId).withdrawn);
    }

    function test_withdraw_revertsForNonOwner() public {
        vm.startPrank(alice);
        lp.approve(address(locker), 100);
        uint256 lockId = locker.lock(address(lp), 100, 200 days, alice);
        vm.stopPrank();

        skip(201 days);
        vm.prank(bob);
        vm.expectRevert(LiquidityLocker.NotLockOwner.selector);
        locker.withdraw(lockId);
    }

    function test_withdraw_revertsTwice() public {
        vm.startPrank(alice);
        lp.approve(address(locker), 100);
        uint256 lockId = locker.lock(address(lp), 100, 200 days, alice);
        vm.stopPrank();

        skip(201 days);
        vm.startPrank(alice);
        locker.withdraw(lockId);
        vm.expectRevert(LiquidityLocker.AlreadyWithdrawn.selector);
        locker.withdraw(lockId);
        vm.stopPrank();
    }

    function test_extendLock_canOnlyPushLater() public {
        vm.startPrank(alice);
        lp.approve(address(locker), 100);
        uint256 lockId = locker.lock(address(lp), 100, 200 days, alice);

        vm.expectRevert(LiquidityLocker.NewUnlockNotLater.selector);
        locker.extendLock(lockId, block.timestamp + 100 days);

        locker.extendLock(lockId, block.timestamp + 365 days);
        assertEq(locker.getLock(lockId).unlockAt, block.timestamp + 365 days);
        vm.stopPrank();
    }

    function test_transferLockOwner() public {
        vm.startPrank(alice);
        lp.approve(address(locker), 100);
        uint256 lockId = locker.lock(address(lp), 100, 200 days, alice);
        locker.transferLockOwner(lockId, bob);
        vm.stopPrank();

        skip(201 days);
        // Alice can no longer withdraw.
        vm.prank(alice);
        vm.expectRevert(LiquidityLocker.NotLockOwner.selector);
        locker.withdraw(lockId);

        // Bob can.
        vm.prank(bob);
        locker.withdraw(lockId);
        assertEq(lp.balanceOf(bob), 100);
    }
}
