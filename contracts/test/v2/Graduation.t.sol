// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Setup} from "./Setup.t.sol";
import {Graduator} from "src/v2/Graduator.sol";
import {ZentriaCurve} from "src/v2/ZentriaCurve.sol";
import {ZentriaToken} from "src/v2/ZentriaToken.sol";

contract GraduationTest is Setup {
    address internal tokenAddr;
    address internal curveAddr;

    function setUp() public {
        _deployInfra();
        (tokenAddr, curveAddr) = _createToken(creator, "Moonshot", "MOON", 0);
    }

    function _curve() internal view returns (ZentriaCurve) {
        return ZentriaCurve(payable(curveAddr));
    }

    function _drainCurveAndGraduate() internal {
        // 33 buys × 1 ETH adds 33 × 0.992 = ~32.7 ETH to realEthReserves; threshold is 32 ETH.
        for (uint256 i = 0; i < 40; i++) {
            address whale = address(uint160(0x2000 + i));
            _buy(curveAddr, whale, 1 ether, 0);
            if (_curve().graduated()) break;
        }
    }

    function test_graduate_triggered_at_threshold() public {
        _drainCurveAndGraduate();
        assertTrue(_curve().graduated());
    }

    function test_curve_holds_no_eth_after_graduation() public {
        _drainCurveAndGraduate();
        assertEq(curveAddr.balance, 0);
    }

    function test_curve_holds_no_tokens_after_graduation() public {
        _drainCurveAndGraduate();
        assertEq(ZentriaToken(tokenAddr).balanceOf(curveAddr), 0);
    }

    function test_lp_nft_burned_to_dead_address() public {
        _drainCurveAndGraduate();
        uint256 lpId = graduator.lpTokenIdOf(tokenAddr);
        assertGt(lpId, 0, "lp id should be set");
        assertEq(positionManager.ownerOf(lpId), 0x000000000000000000000000000000000000dEaD);
    }

    function test_pool_address_recorded() public {
        _drainCurveAndGraduate();
        address pool = graduator.poolOf(tokenAddr);
        assertTrue(pool != address(0));
    }

    function test_pool_seeded_with_eth_and_tokens() public {
        // Snapshot WETH and token balances at the mock NFPM after graduation.
        _drainCurveAndGraduate();
        // Mock NFPM accumulated both sides during the mint() call.
        uint256 wethAtNFPM = weth.balanceOf(address(positionManager));
        uint256 tokenAtNFPM = ZentriaToken(tokenAddr).balanceOf(address(positionManager));
        assertGt(wethAtNFPM, 0);
        assertGt(tokenAtNFPM, 0);
    }

    function test_double_graduation_reverts() public {
        _drainCurveAndGraduate();
        // Direct call to Graduator.graduate by an unauthorized caller should fail (NotCurve)
        vm.expectRevert(Graduator.NotCurve.selector);
        graduator.graduate(tokenAddr, 1, -100, 100, 1);

        // Even from the curve address itself, isGraduated[true] blocks via AlreadyGraduated.
        // The curve was drained during graduation, so re-fund it for the value-bearing call.
        vm.deal(curveAddr, 1);
        vm.prank(curveAddr);
        vm.expectRevert(Graduator.AlreadyGraduated.selector);
        graduator.graduate{value: 1}(tokenAddr, 1, -100, 100, 1);
    }

    function test_register_curve_only_by_registrar() public {
        address rogue = address(0xBAD);
        vm.prank(rogue);
        vm.expectRevert(Graduator.NotRegistrar.selector);
        graduator.registerCurve(tokenAddr, curveAddr);
    }

    function test_no_double_register() public {
        // Already registered during _createToken.
        vm.prank(address(launchpad));
        vm.expectRevert(Graduator.AlreadyRegistered.selector);
        graduator.registerCurve(tokenAddr, curveAddr);
    }
}
