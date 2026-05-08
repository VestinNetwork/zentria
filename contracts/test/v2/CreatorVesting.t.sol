// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CreatorVesting} from "src/v2/CreatorVesting.sol";

contract DummyToken is ERC20 {
    constructor() ERC20("Dummy", "DUM") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract CreatorVestingTest is Test {
    CreatorVesting internal vesting;
    DummyToken internal token;
    address internal beneficiary = address(0xBABE);

    function setUp() public {
        vesting = new CreatorVesting();
        token = new DummyToken();
        token.approve(address(vesting), type(uint256).max);
    }

    function test_create_and_release_after_full_duration() public {
        uint256 id = vesting.createSchedule(address(token), beneficiary, 1000 ether, 30 days, 270 days);
        assertEq(vesting.releasable(id), 0);

        vm.warp(block.timestamp + 270 days);
        assertEq(vesting.releasable(id), 1000 ether);

        uint256 released = vesting.release(id);
        assertEq(released, 1000 ether);
        assertEq(token.balanceOf(beneficiary), 1000 ether);
    }

    function test_no_release_during_cliff() public {
        uint256 id = vesting.createSchedule(address(token), beneficiary, 1000 ether, 30 days, 270 days);
        vm.warp(block.timestamp + 30 days - 1);
        assertEq(vesting.releasable(id), 0);
        vm.expectRevert(CreatorVesting.NothingToRelease.selector);
        vesting.release(id);
    }

    function test_linear_release_after_cliff() public {
        uint256 id = vesting.createSchedule(address(token), beneficiary, 270 ether, 30 days, 270 days);
        // Halfway through total duration => half vested
        vm.warp(block.timestamp + 135 days);
        assertEq(vesting.releasable(id), 135 ether);
        vesting.release(id);
        assertEq(token.balanceOf(beneficiary), 135 ether);
    }

    function test_topup_increases_total() public {
        uint256 id = vesting.createSchedule(address(token), beneficiary, 100 ether, 0, 100 days);
        vesting.topUp(id, 50 ether);
        CreatorVesting.Schedule memory s = vesting.getSchedule(id);
        assertEq(s.totalAmount, 150 ether);
    }

    function test_revert_on_invalid_params() public {
        vm.expectRevert(CreatorVesting.InvalidParams.selector);
        vesting.createSchedule(address(0), beneficiary, 1, 0, 1);
        vm.expectRevert(CreatorVesting.InvalidParams.selector);
        vesting.createSchedule(address(token), address(0), 1, 0, 1);
        vm.expectRevert(CreatorVesting.InvalidParams.selector);
        vesting.createSchedule(address(token), beneficiary, 0, 0, 1);
        vm.expectRevert(CreatorVesting.InvalidParams.selector);
        vesting.createSchedule(address(token), beneficiary, 1, 100, 50); // duration < cliff
    }

    function test_unknown_schedule_reverts() public {
        vm.expectRevert(CreatorVesting.InvalidSchedule.selector);
        vesting.release(999);
    }
}
