// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AntiSniper} from "src/v2/AntiSniper.sol";

contract AntiSniperHarness {
    function bps(uint256 launchedAt, uint256 windowSeconds) external view returns (uint16) {
        return AntiSniper.currentBuyTaxBps(launchedAt, windowSeconds);
    }
}

/// @dev Tests use a fixed `LAUNCHED_AT` literal rather than capturing `block.timestamp`
///      into a local before `vm.warp`, because the Solidity optimizer fuses
///      `block.timestamp` reads across the (opaque) cheatcode call.
contract AntiSniperTest is Test {
    AntiSniperHarness internal h;

    uint256 internal constant LAUNCHED_AT = 1_000_000;

    function setUp() public {
        h = new AntiSniperHarness();
        vm.warp(LAUNCHED_AT);
    }

    function test_zero_window_disables_tax() public view {
        assertEq(h.bps(LAUNCHED_AT, 0), 0);
    }

    function test_max_at_t0() public view {
        assertEq(h.bps(LAUNCHED_AT, 300), 9900);
    }

    function test_min_at_window_end() public {
        vm.warp(LAUNCHED_AT + 300);
        // At exactly elapsed == windowSeconds, the function returns 0 (post-window).
        assertEq(h.bps(LAUNCHED_AT, 300), 0);
    }

    function test_linear_decay_at_50pct() public {
        vm.warp(LAUNCHED_AT + 150);
        // Expected: 9900 - (9800 * 150 / 300) = 9900 - 4900 = 5000
        assertEq(h.bps(LAUNCHED_AT, 300), 5000);
    }

    function test_post_window_returns_zero() public {
        vm.warp(LAUNCHED_AT + 1000);
        assertEq(h.bps(LAUNCHED_AT, 300), 0);
    }

    function test_pre_launch_returns_max() public view {
        // launchedAt > current → return MAX
        assertEq(h.bps(LAUNCHED_AT + 100, 300), 9900);
    }
}
