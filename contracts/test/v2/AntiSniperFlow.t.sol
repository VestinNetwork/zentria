// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Setup} from "./Setup.t.sol";
import {AntiSniper} from "src/v2/AntiSniper.sol";
import {CreatorVesting} from "src/v2/CreatorVesting.sol";
import {ZentriaCurve} from "src/v2/ZentriaCurve.sol";
import {ZentriaToken} from "src/v2/ZentriaToken.sol";

/// @notice Tests the anti-sniper buy-tax decay and the resulting buyback-vest pipeline.
contract AntiSniperFlowTest is Setup {
    address internal tokenAddr;
    address internal curveAddr;

    function setUp() public {
        _deployInfra();
        // 5 minute (300s) sniper window
        (tokenAddr, curveAddr) = _createToken(creator, "Sniped Inu", "SNIPE", 300);
    }

    function _curve() internal view returns (ZentriaCurve) {
        return ZentriaCurve(payable(curveAddr));
    }

    function _token() internal view returns (ZentriaToken) {
        return ZentriaToken(tokenAddr);
    }

    function test_buy_at_t0_taxes_99pct_into_vesting() public {
        uint256 out = _buy(curveAddr, alice, 1 ether, 0);

        // 99% of curve tokens went to vesting, 1% to alice.
        assertGt(_token().balanceOf(address(creatorVesting)), 0);
        // Alice keeps ~1% of the gross tokens.
        // Compute gross via quote — but the curve mutated; instead, just bound:
        uint256 vested = _token().balanceOf(address(creatorVesting));
        assertGt(vested, out * 50); // at least 50× the user's share
    }

    function test_buy_after_window_no_tax() public {
        vm.warp(block.timestamp + 301);
        uint256 out = _buy(curveAddr, alice, 1 ether, 0);
        // No tax → vesting should not have been topped up.
        assertEq(_token().balanceOf(address(creatorVesting)), 0);
        assertGt(out, 0);
    }

    function test_buy_at_window_midpoint_about_half_tax() public {
        vm.warp(block.timestamp + 150);
        uint256 outMid = _buy(curveAddr, alice, 1 ether, 0);
        uint256 vestedMid = _token().balanceOf(address(creatorVesting));
        // At midpoint: tax ≈ 50% (between 99% and 1%).
        // outMid : vestedMid should be roughly 1:1 (within 5%).
        if (outMid > vestedMid) {
            assertLt((outMid - vestedMid) * 100 / outMid, 5);
        } else {
            assertLt((vestedMid - outMid) * 100 / vestedMid, 5);
        }
    }

    function test_sniper_tokens_vest_with_30d_cliff() public {
        _buy(curveAddr, alice, 1 ether, 0);
        uint256 scheduleId = _curve().creatorVestingScheduleId();

        // Pre-cliff: nothing releasable.
        assertEq(creatorVesting.releasable(scheduleId), 0);

        // Mid-cliff: still nothing.
        vm.warp(block.timestamp + 29 days);
        assertEq(creatorVesting.releasable(scheduleId), 0);

        // Post-cliff: linear release begins.
        vm.warp(block.timestamp + 2 days); // total 31 days elapsed
        assertGt(creatorVesting.releasable(scheduleId), 0);
    }

    function test_release_after_full_duration() public {
        _buy(curveAddr, alice, 1 ether, 0);
        uint256 scheduleId = _curve().creatorVestingScheduleId();
        vm.warp(block.timestamp + 270 days);

        uint256 totalVested = _token().balanceOf(address(creatorVesting));
        uint256 released = creatorVesting.release(scheduleId);
        assertEq(released, totalVested);
        assertEq(_token().balanceOf(creator), totalVested);
    }

    function test_topup_accumulates_into_same_schedule() public {
        _buy(curveAddr, alice, 1 ether, 0); // creates schedule
        uint256 scheduleId = _curve().creatorVestingScheduleId();

        uint256 firstVested = creatorVesting.getSchedule(scheduleId).totalAmount;

        // Second buy in same window should top up, not create a new schedule.
        _buy(curveAddr, bob, 0.5 ether, 0);
        uint256 nextSchedules = creatorVesting.totalSchedules();
        assertEq(nextSchedules, 1, "should still be exactly one schedule");

        uint256 secondVested = creatorVesting.getSchedule(scheduleId).totalAmount;
        assertGt(secondVested, firstVested);
    }
}
