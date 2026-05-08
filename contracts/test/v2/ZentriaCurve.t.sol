// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Setup} from "./Setup.t.sol";
import {AntiSniper} from "src/v2/AntiSniper.sol";
import {CreatorVesting} from "src/v2/CreatorVesting.sol";
import {FeeSplitter} from "src/v2/FeeSplitter.sol";
import {Graduator} from "src/v2/Graduator.sol";
import {ZentriaCurve} from "src/v2/ZentriaCurve.sol";
import {ZentriaToken} from "src/v2/ZentriaToken.sol";

contract ZentriaCurveTest is Setup {
    address internal tokenAddr;
    address internal curveAddr;

    function setUp() public {
        _deployInfra();
        (tokenAddr, curveAddr) = _createToken(creator, "Pepe Coin", "PEPE", 0); // sniper window 0 -> off
    }

    function _curve() internal view returns (ZentriaCurve) {
        return ZentriaCurve(payable(curveAddr));
    }

    function _token() internal view returns (ZentriaToken) {
        return ZentriaToken(tokenAddr);
    }

    // --------------- initialization ---------------

    function test_initialization_state() public view {
        assertTrue(_curve().initialized());
        assertEq(_curve().launchedAt(), block.timestamp);
        assertFalse(_curve().graduated());
        assertEq(_curve().realEthReserves(), 0);
        assertEq(_curve().realTokenReserves(), 800_000_000 * 1e18);
        // Curve holds the full 1B supply (curve + reserve).
        assertEq(_token().balanceOf(curveAddr), 1_000_000_000 * 1e18);
    }

    function test_double_activate_reverts() public {
        vm.prank(address(launchpad));
        vm.expectRevert(ZentriaCurve.AlreadyInitialized.selector);
        _curve().activate();
    }

    function test_activate_only_by_launchpad() public {
        // Make a fresh curve manually to test activate restriction.
        // We can use the existing curve which was already activated; non-launchpad caller
        // should still hit the launchpad-check first.
        vm.prank(address(0xdead));
        vm.expectRevert(ZentriaCurve.NotLaunchpad.selector);
        _curve().activate();
    }

    // --------------- buy ---------------

    function test_buy_zero_eth_reverts() public {
        vm.prank(alice);
        vm.expectRevert(ZentriaCurve.ZeroAmount.selector);
        _curve().buy{value: 0}(0);
    }

    function test_buy_credits_buyer_with_tokens() public {
        uint256 ethIn = 1 ether;
        uint256 out = _buy(curveAddr, alice, ethIn, 0);
        assertGt(out, 0);
        assertEq(_token().balanceOf(alice), out);
    }

    function test_buy_charges_one_percent_fee() public {
        uint256 ethIn = 1 ether;
        _buy(curveAddr, alice, ethIn, 0);
        // 1% fee = 0.01 ETH; of that 50% creator + 30% protocol go to splitter (0.008 ETH).
        // Splitter accrues these as separate balances per token.
        assertEq(feeSplitter.creatorBalance(tokenAddr), 0.005 ether);
        assertEq(feeSplitter.protocolBalance(tokenAddr), 0.003 ether);
        assertEq(feeSplitter.lifetimeCreator(tokenAddr), 0.005 ether);
        assertEq(feeSplitter.lifetimeProtocol(tokenAddr), 0.003 ether);
    }

    function test_buy_retains_boost_on_curve() public {
        uint256 ethIn = 1 ether;
        _buy(curveAddr, alice, ethIn, 0);
        // 0.992 ETH should stay in the curve (1 - creator 0.005 - protocol 0.003)
        assertEq(curveAddr.balance, 0.992 ether);
        assertEq(_curve().realEthReserves(), 0.992 ether);
    }

    function test_buy_slippage_reverts_when_min_not_met() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(ZentriaCurve.SlippageExceeded.selector);
        _curve().buy{value: 1 ether}(type(uint256).max);
    }

    function test_buy_quote_matches_actual() public {
        uint256 ethIn = 0.5 ether;
        (uint256 quoted,) = _curve().quoteBuy(ethIn);
        uint256 actual = _buy(curveAddr, alice, ethIn, 0);
        assertEq(actual, quoted);
    }

    // --------------- sell ---------------

    function test_sell_basic() public {
        uint256 boughtTokens = _buy(curveAddr, alice, 1 ether, 0);

        uint256 ethBefore = alice.balance;
        uint256 ethOut = _sell(curveAddr, alice, boughtTokens, 0);
        uint256 ethAfter = alice.balance;

        assertEq(ethAfter, ethBefore + ethOut);
        assertGt(ethOut, 0);
        // Round-trip must be < ethIn due to fees.
        assertLt(ethOut, 1 ether);
    }

    function test_sell_quote_matches_actual() public {
        uint256 boughtTokens = _buy(curveAddr, alice, 1 ether, 0);
        uint256 quoted = _curve().quoteSell(boughtTokens);
        uint256 actual = _sell(curveAddr, alice, boughtTokens, 0);
        assertEq(actual, quoted);
    }

    function test_sell_slippage_reverts() public {
        uint256 boughtTokens = _buy(curveAddr, alice, 0.5 ether, 0);
        vm.prank(alice);
        _token().approve(curveAddr, boughtTokens);
        vm.prank(alice);
        vm.expectRevert(ZentriaCurve.SlippageExceeded.selector);
        _curve().sell(boughtTokens, type(uint256).max);
    }

    function test_sell_zero_reverts() public {
        vm.prank(alice);
        vm.expectRevert(ZentriaCurve.ZeroAmount.selector);
        _curve().sell(0, 0);
    }

    function test_sell_too_large_reverts() public {
        // Acquire some tokens through admin trickery; then try to sell more than ever sold.
        uint256 boughtTokens = _buy(curveAddr, alice, 0.1 ether, 0);
        // Now alice tries to sell more tokens than exist on the curve's selling capacity.
        // R_t can never exceed CURVE_SUPPLY, so attempting to sell e.g. CURVE_SUPPLY worth
        // of tokens (which alice doesn't even own) reverts on the math first.
        deal(tokenAddr, alice, 800_000_000 * 1e18);
        vm.prank(alice);
        _token().approve(curveAddr, 800_000_000 * 1e18);
        vm.prank(alice);
        vm.expectRevert(ZentriaCurve.SellTooLarge.selector);
        _curve().sell(800_000_000 * 1e18, 0);
    }

    // --------------- multi-trade flow ---------------

    function test_two_buys_price_increases() public {
        uint256 firstOut = _buy(curveAddr, alice, 1 ether, 0);
        uint256 secondOut = _buy(curveAddr, bob, 1 ether, 0);
        // Second buyer gets fewer tokens for the same ETH (price went up).
        assertLt(secondOut, firstOut);
    }

    function test_buy_then_sell_then_buy_consistency() public {
        uint256 firstOut = _buy(curveAddr, alice, 1 ether, 0);
        _sell(curveAddr, alice, firstOut, 0);
        // After sell the price drops back near (but above due to fees retained as boost) start.
        // Buying same ETH again should produce slightly fewer tokens than the original first buy.
        uint256 secondOut = _buy(curveAddr, bob, 1 ether, 0);
        assertLt(secondOut, firstOut);
    }

    function test_no_trading_after_graduation() public {
        // Push reserves over the graduation threshold via several whales.
        // Each buy adds 0.992 ETH to reserves; ~33 ETH gross required.
        for (uint256 i = 0; i < 33; i++) {
            address whale = address(uint160(0x1000 + i));
            _buy(curveAddr, whale, 1 ether, 0);
            if (_curve().graduated()) break;
        }
        assertTrue(_curve().graduated(), "should graduate within budget");

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(ZentriaCurve.NotTradable.selector);
        _curve().buy{value: 1 ether}(0);
    }
}
