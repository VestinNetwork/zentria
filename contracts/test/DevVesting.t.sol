// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DevVesting} from "../src/DevVesting.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Token", "TOK") {
        _mint(msg.sender, 1_000_000 * 1e18);
    }
}

contract DevVestingTest is Test {
    DevVesting internal vesting;
    MockToken internal tok;

    address internal launchpad = makeAddr("launchpad");
    address internal dev = makeAddr("dev");
    address internal alice = makeAddr("alice");

    uint256 internal constant TOTAL = 50_000 * 1e18;

    function setUp() public {
        vesting = new DevVesting();
        tok = new MockToken();
        tok.transfer(launchpad, TOTAL);
    }

    function _createSchedule() internal returns (uint256) {
        vm.startPrank(launchpad);
        tok.approve(address(vesting), TOTAL);
        uint256 id = vesting.createVesting(address(tok), dev, TOTAL);
        vm.stopPrank();
        return id;
    }

    function test_createVesting_pullsTokens() public {
        uint256 id = _createSchedule();
        DevVesting.Schedule memory s = vesting.getSchedule(id);
        assertEq(s.token, address(tok));
        assertEq(s.beneficiary, dev);
        assertEq(s.totalAmount, TOTAL);
        assertEq(s.released, 0);
        assertEq(tok.balanceOf(address(vesting)), TOTAL);
    }

    function test_release_revertsBeforeCliff() public {
        uint256 id = _createSchedule();
        skip(15 days);

        vm.prank(dev);
        vm.expectRevert(DevVesting.NothingToRelease.selector);
        vesting.release(id);
    }

    function test_release_zeroAtCliffBoundary() public {
        uint256 id = _createSchedule();
        // Right at the cliff (block.timestamp == cliffEnd) -> 0 vested.
        skip(30 days);
        assertEq(vesting.releasable(id), 0);
    }

    function test_release_linearAfterCliff() public {
        uint256 id = _createSchedule();
        // 30 days cliff + 90 days into vesting (50% of 180-day linear period).
        skip(30 days + 90 days);

        uint256 expected = TOTAL / 2;
        assertApproxEqAbs(vesting.releasable(id), expected, 1e10);

        uint256 devBalBefore = tok.balanceOf(dev);
        vm.prank(dev);
        vesting.release(id);
        assertApproxEqAbs(tok.balanceOf(dev) - devBalBefore, expected, 1e10);
    }

    function test_release_fullAfterVestingPeriod() public {
        uint256 id = _createSchedule();
        skip(30 days + 180 days + 1);

        assertEq(vesting.releasable(id), TOTAL);
        vm.prank(dev);
        vesting.release(id);
        assertEq(tok.balanceOf(dev), TOTAL);
    }

    function test_release_revertsForNonBeneficiary() public {
        uint256 id = _createSchedule();
        skip(30 days + 180 days + 1);

        vm.prank(alice);
        vm.expectRevert(DevVesting.NotBeneficiary.selector);
        vesting.release(id);
    }

    function test_release_partialThenRest() public {
        uint256 id = _createSchedule();
        skip(30 days + 90 days);
        uint256 first = vesting.releasable(id);

        vm.prank(dev);
        vesting.release(id);

        // After full vesting, the rest should be claimable.
        skip(91 days);
        uint256 second = vesting.releasable(id);
        assertApproxEqAbs(first + second, TOTAL, 1e10);

        vm.prank(dev);
        vesting.release(id);
        assertEq(tok.balanceOf(dev), TOTAL);
    }
}
