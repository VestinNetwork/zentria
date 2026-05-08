// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FeeSplitter} from "src/v2/FeeSplitter.sol";

contract FeeSplitterTest is Test {
    FeeSplitter internal splitter;
    address internal owner = address(0xA11CE);
    address internal treasury = address(0xBEEF);
    address internal registrar = address(0xCAFE);
    address internal curve = address(0xDEAD);
    address internal token = address(0x7890);
    address internal creator = address(0x1234);

    function setUp() public {
        splitter = new FeeSplitter(owner, treasury);
        vm.prank(owner);
        splitter.setRegistrar(registrar);
    }

    function test_register_curve_only_by_registrar() public {
        vm.expectRevert(FeeSplitter.NotRegistrar.selector);
        splitter.registerCurve(token, curve, creator);

        vm.prank(registrar);
        splitter.registerCurve(token, curve, creator);
        assertEq(splitter.curveOf(token), curve);
        assertEq(splitter.creatorOf(token), creator);
    }

    function test_double_register_reverts() public {
        vm.startPrank(registrar);
        splitter.registerCurve(token, curve, creator);
        vm.expectRevert(FeeSplitter.AlreadyRegistered.selector);
        splitter.registerCurve(token, address(0xDEAD2), creator);
        vm.stopPrank();
    }

    function test_accrue_books_balances() public {
        vm.prank(registrar);
        splitter.registerCurve(token, curve, creator);

        vm.deal(curve, 1 ether);
        vm.prank(curve);
        splitter.accrue{value: 0.5 ether + 0.3 ether}(token, 0.5 ether, 0.3 ether);

        assertEq(splitter.creatorBalance(token), 0.5 ether);
        assertEq(splitter.protocolBalance(token), 0.3 ether);
        assertEq(splitter.lifetimeCreator(token), 0.5 ether);
        assertEq(splitter.lifetimeProtocol(token), 0.3 ether);
    }

    function test_accrue_only_from_registered_curve() public {
        vm.prank(registrar);
        splitter.registerCurve(token, curve, creator);

        address impostor = address(0xBADBEEF);
        vm.deal(impostor, 1 ether);
        vm.prank(impostor);
        vm.expectRevert(FeeSplitter.NotCurve.selector);
        splitter.accrue{value: 0.5 ether}(token, 0.5 ether, 0);
    }

    function test_accrue_value_must_match() public {
        vm.prank(registrar);
        splitter.registerCurve(token, curve, creator);

        vm.deal(curve, 1 ether);
        vm.prank(curve);
        vm.expectRevert(FeeSplitter.MismatchedFunds.selector);
        splitter.accrue{value: 1 ether}(token, 0.5 ether, 0.3 ether); // value != sum
    }

    function test_claim_creator_to_creator_only() public {
        vm.prank(registrar);
        splitter.registerCurve(token, curve, creator);
        vm.deal(curve, 1 ether);
        vm.prank(curve);
        splitter.accrue{value: 0.5 ether}(token, 0.5 ether, 0);

        // Anyone can call but funds always go to creator.
        uint256 creatorBefore = creator.balance;
        splitter.claimCreator(token);
        assertEq(creator.balance, creatorBefore + 0.5 ether);
        assertEq(splitter.creatorBalance(token), 0);

        vm.expectRevert(FeeSplitter.NothingToClaim.selector);
        splitter.claimCreator(token);
    }

    function test_claim_protocol_to_treasury() public {
        vm.prank(registrar);
        splitter.registerCurve(token, curve, creator);
        vm.deal(curve, 1 ether);
        vm.prank(curve);
        splitter.accrue{value: 0.3 ether}(token, 0, 0.3 ether);

        uint256 before_ = treasury.balance;
        splitter.claimProtocol(token);
        assertEq(treasury.balance, before_ + 0.3 ether);
    }

    function test_set_treasury_redirects_future_claims() public {
        vm.prank(registrar);
        splitter.registerCurve(token, curve, creator);
        vm.deal(curve, 1 ether);
        vm.prank(curve);
        splitter.accrue{value: 0.3 ether}(token, 0, 0.3 ether);

        address newTreasury = address(0xC0FFEE);
        vm.prank(owner);
        splitter.setTreasury(newTreasury);

        splitter.claimProtocol(token);
        assertEq(newTreasury.balance, 0.3 ether);
    }
}
