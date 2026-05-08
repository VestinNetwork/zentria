// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MemeToken} from "../src/MemeToken.sol";

contract MemeTokenTest is Test {
    MemeToken internal token;

    address internal launchpad = makeAddr("launchpad");
    address internal dev = makeAddr("dev");
    address internal treasury = makeAddr("treasury");
    address internal pair = makeAddr("pair");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant SUPPLY = 1_000_000;
    uint16 internal constant BUY_TAX = 300; // 3%
    uint16 internal constant SELL_TAX = 500; // 5%
    uint16 internal constant MAX_WALLET_BPS = 200; // 2%
    uint16 internal constant MAX_TX_BPS = 100; // 1%

    function setUp() public {
        vm.prank(launchpad);
        token = new MemeToken({
            name_: "Meme",
            symbol_: "MEME",
            totalSupply_: SUPPLY,
            buyTaxBps_: BUY_TAX,
            sellTaxBps_: SELL_TAX,
            maxWalletBps_: MAX_WALLET_BPS,
            maxTxBps_: MAX_TX_BPS,
            devWallet_: dev,
            platformTreasury_: treasury,
            launchpad_: launchpad
        });

        // Simulate launchpad seeding distribution + opening trading.
        vm.startPrank(launchpad);
        token.setAmmPair(pair, true);
        token.openTrading();
        // Send some tokens to the pair so it can "sell" them later in tests.
        token.transfer(pair, token.balanceOf(launchpad) / 2);
        vm.stopPrank();
    }

    function test_constructor_setsParams() public view {
        assertEq(token.name(), "Meme");
        assertEq(token.symbol(), "MEME");
        assertEq(token.totalSupply(), SUPPLY * 1e18);
        assertEq(token.buyTaxBps(), BUY_TAX);
        assertEq(token.sellTaxBps(), SELL_TAX);
        assertEq(token.devWallet(), dev);
        assertEq(token.platformTreasury(), treasury);
        assertEq(token.maxWalletAmount(), (SUPPLY * 1e18 * MAX_WALLET_BPS) / 10000);
        assertEq(token.maxTxAmount(), (SUPPLY * 1e18 * MAX_TX_BPS) / 10000);
    }

    function test_constructor_revertsOnExcessiveTax() public {
        vm.expectRevert(MemeToken.TaxTooHigh.selector);
        new MemeToken({
            name_: "X",
            symbol_: "X",
            totalSupply_: 1,
            buyTaxBps_: 600,
            sellTaxBps_: 0,
            maxWalletBps_: 100,
            maxTxBps_: 100,
            devWallet_: dev,
            platformTreasury_: treasury,
            launchpad_: launchpad
        });
    }

    function test_buyTax_appliedOnTransferFromPair() public {
        // Pair "sells" 1000 tokens to Alice (simulates a buy).
        uint256 amount = 1000 * 1e18;
        // Whitelist Alice from limits to focus on tax mechanics only.
        vm.prank(launchpad);
        token.setExcludedFromLimits(alice, true);

        uint256 devBefore = token.balanceOf(dev);
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(pair);
        token.transfer(alice, amount);

        uint256 expectedTax = (amount * BUY_TAX) / 10000;
        uint256 expectedPlatform = (expectedTax * 2000) / 10000;
        uint256 expectedDev = expectedTax - expectedPlatform;

        assertEq(token.balanceOf(alice), amount - expectedTax, "alice net");
        assertEq(token.balanceOf(dev) - devBefore, expectedDev, "dev share");
        assertEq(token.balanceOf(treasury) - treasuryBefore, expectedPlatform, "platform share");
    }

    function test_sellTax_appliedOnTransferToPair() public {
        // Send Alice some tokens (excluded from limits), then have her sell to pair.
        vm.startPrank(launchpad);
        token.setExcludedFromLimits(alice, true);
        token.setExcludedFromTax(launchpad, true); // already excluded by default
        token.transfer(alice, 1000 * 1e18);
        vm.stopPrank();

        uint256 amount = 500 * 1e18;
        uint256 devBefore = token.balanceOf(dev);
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(alice);
        token.transfer(pair, amount);

        uint256 expectedTax = (amount * SELL_TAX) / 10000;
        uint256 expectedPlatform = (expectedTax * 2000) / 10000;
        uint256 expectedDev = expectedTax - expectedPlatform;

        assertEq(token.balanceOf(pair) - (SUPPLY * 1e18 / 2), amount - expectedTax, "pair received net");
        assertEq(token.balanceOf(dev) - devBefore, expectedDev, "dev share");
        assertEq(token.balanceOf(treasury) - treasuryBefore, expectedPlatform, "platform share");
    }

    function test_noTax_onPeerToPeerTransfer() public {
        vm.startPrank(launchpad);
        token.setExcludedFromLimits(alice, true);
        token.setExcludedFromLimits(bob, true);
        token.transfer(alice, 1000 * 1e18);
        vm.stopPrank();

        uint256 devBefore = token.balanceOf(dev);
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(alice);
        token.transfer(bob, 500 * 1e18);

        assertEq(token.balanceOf(bob), 500 * 1e18);
        assertEq(token.balanceOf(dev), devBefore, "no dev tax");
        assertEq(token.balanceOf(treasury), treasuryBefore, "no platform tax");
    }

    function test_maxTx_revertsWhenExceeded() public {
        // Fund alice up to maxWallet (20k tokens). Then she tries to send > maxTx (10k) to bob.
        vm.prank(launchpad);
        token.transfer(alice, 20_000 * 1e18);

        vm.prank(alice);
        vm.expectRevert(MemeToken.MaxTxExceeded.selector);
        token.transfer(bob, 11_000 * 1e18);
    }

    function test_maxWallet_revertsWhenExceeded() public {
        // maxWalletAmount = 2% of supply = 20_000 tokens.
        vm.prank(launchpad);
        token.transfer(alice, 19_000 * 1e18);

        // Sending another 5000 (within maxTx) would push Alice over max wallet.
        vm.prank(launchpad);
        vm.expectRevert(MemeToken.MaxWalletExceeded.selector);
        token.transfer(alice, 5_000 * 1e18);
    }

    function test_limits_expireAfter24Hours() public {
        skip(24 hours + 1);
        assertFalse(token.limitsActive());

        vm.prank(launchpad);
        token.transfer(alice, 100_000 * 1e18); // would have failed under maxWallet pre-expiry
        assertEq(token.balanceOf(alice), 100_000 * 1e18);
    }

    function test_disableLimits_oneWaySwitch() public {
        vm.prank(dev); // dev is not yet owner
        vm.expectRevert();
        token.disableLimits();

        vm.prank(launchpad);
        token.disableLimits();
        assertFalse(token.limitsActive());

        vm.prank(launchpad);
        vm.expectRevert(MemeToken.LimitsAlreadyDisabled.selector);
        token.disableLimits();
    }

    function test_tradingNotOpen_revertsForNonExcludedTransfers() public {
        // Deploy fresh token where trading hasn't been opened.
        vm.prank(launchpad);
        MemeToken fresh = new MemeToken({
            name_: "X",
            symbol_: "X",
            totalSupply_: 1000,
            buyTaxBps_: 0,
            sellTaxBps_: 0,
            maxWalletBps_: 10000,
            maxTxBps_: 10000,
            devWallet_: dev,
            platformTreasury_: treasury,
            launchpad_: launchpad
        });

        // Launchpad -> Alice works (launchpad excluded).
        vm.prank(launchpad);
        fresh.transfer(alice, 100 * 1e18);

        // Alice -> Bob should revert (neither excluded, trading not open).
        vm.prank(alice);
        vm.expectRevert(MemeToken.TradingNotOpen.selector);
        fresh.transfer(bob, 1 * 1e18);
    }
}
