// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Setup} from "./Setup.t.sol";
import {ZentriaCurve} from "src/v2/ZentriaCurve.sol";
import {ZentriaLaunchpad} from "src/v2/ZentriaLaunchpad.sol";
import {ZentriaToken} from "src/v2/ZentriaToken.sol";

/// @notice Full E2E happy path: launch → snipe-window trade → buy → sell → claim → graduate.
contract IntegrationTest is Setup {
    function setUp() public {
        _deployInfra();
    }

    function test_full_lifecycle() public {
        // 1. Creator launches with 5-minute sniper window.
        (address tokenAddr, address curveAddr) = _createToken(creator, "Pepe v2", "PEPE2", 5 minutes);
        ZentriaCurve curve = ZentriaCurve(payable(curveAddr));
        ZentriaToken token = ZentriaToken(tokenAddr);

        // 2. Sniper hits at t=0 — gets very few tokens (99% redirected to vesting).
        uint256 sniperOut = _buy(curveAddr, alice, 0.5 ether, 0);
        uint256 sniperTokensInVesting = token.balanceOf(address(creatorVesting));
        assertGt(sniperTokensInVesting, sniperOut * 50);

        // 3. Wait past sniper window. Honest buyer gets normal tokens.
        vm.warp(block.timestamp + 6 minutes);
        uint256 normalOut = _buy(curveAddr, bob, 0.5 ether, 0);
        // Honest buyer gets >> sniper.
        assertGt(normalOut, sniperOut * 50);

        // 4. Bob sells half his bag back; should get ETH minus fee.
        uint256 ethBefore = bob.balance;
        uint256 ethOut = _sell(curveAddr, bob, normalOut / 2, 0);
        assertEq(bob.balance, ethBefore + ethOut);
        assertGt(ethOut, 0);

        // 5. Creator claims accumulated fees (creator share of trade fees).
        uint256 creatorBefore = creator.balance;
        uint256 creatorClaim = feeSplitter.claimCreator(tokenAddr);
        assertEq(creator.balance, creatorBefore + creatorClaim);

        // 6. Treasury claims protocol share.
        uint256 treasuryBefore = treasury.balance;
        uint256 protocolClaim = feeSplitter.claimProtocol(tokenAddr);
        assertEq(treasury.balance, treasuryBefore + protocolClaim);

        // 7. Drive curve to graduation.
        for (uint256 i = 0; i < 40; i++) {
            address whale = address(uint160(0x3000 + i));
            _buy(curveAddr, whale, 1 ether, 0);
            if (curve.graduated()) break;
        }
        assertTrue(curve.graduated());

        // 8. Sniper-tax vesting eventually pays out to creator after cliff + duration.
        uint256 scheduleId = curve.creatorVestingScheduleId();
        vm.warp(block.timestamp + 270 days);
        uint256 released = creatorVesting.release(scheduleId);
        assertEq(released, sniperTokensInVesting);
        assertEq(token.balanceOf(creator), sniperTokensInVesting);

        // 9. LP NFT is burned forever.
        uint256 lpId = graduator.lpTokenIdOf(tokenAddr);
        assertEq(positionManager.ownerOf(lpId), 0x000000000000000000000000000000000000dEaD);
    }

    function test_two_independent_launches_have_separate_state() public {
        (address tokenA, address curveA) = _createToken(creator, "AAA", "A", 0);
        (address tokenB, address curveB) = _createToken(alice, "BBB", "B", 0);

        // Trades on A do not affect B's reserves or fees.
        _buy(curveA, bob, 1 ether, 0);
        assertEq(ZentriaCurve(payable(curveB)).realEthReserves(), 0);
        assertGt(feeSplitter.creatorBalance(tokenA), 0);
        assertEq(feeSplitter.creatorBalance(tokenB), 0);
    }
}
