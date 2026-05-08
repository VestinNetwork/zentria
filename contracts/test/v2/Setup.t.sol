// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AntiSniper} from "src/v2/AntiSniper.sol";
import {CreatorVesting} from "src/v2/CreatorVesting.sol";
import {FeeSplitter} from "src/v2/FeeSplitter.sol";
import {Graduator} from "src/v2/Graduator.sol";
import {ZentriaCurve} from "src/v2/ZentriaCurve.sol";
import {ZentriaLaunchpad} from "src/v2/ZentriaLaunchpad.sol";
import {ZentriaToken} from "src/v2/ZentriaToken.sol";

import {MockAlgebraFactory} from "./mocks/MockAlgebraFactory.sol";
import {MockAlgebraPositionManager} from "./mocks/MockAlgebraPositionManager.sol";
import {MockWETH} from "./mocks/MockWETH.sol";

/// @notice Shared deployment fixture for v2 tests. Deploys all infra contracts and one
///         launchpad ready to create tokens.
abstract contract Setup is Test {
    MockWETH internal weth;
    MockAlgebraFactory internal factory;
    MockAlgebraPositionManager internal positionManager;

    CreatorVesting internal creatorVesting;
    FeeSplitter internal feeSplitter;
    Graduator internal graduator;
    ZentriaLaunchpad internal launchpad;

    address internal owner = address(0xA11CE);
    address internal treasury = address(0xBEEF);
    address internal creator = address(0xCAFE);
    address internal alice = address(0xA11CE1);
    address internal bob = address(0xB0B);

    function _deployInfra() internal {
        weth = new MockWETH();
        factory = new MockAlgebraFactory();
        positionManager = new MockAlgebraPositionManager();

        creatorVesting = new CreatorVesting();

        feeSplitter = new FeeSplitter(owner, treasury);

        // Compute the launchpad address ahead of time so Graduator can be wired with it.
        // We deploy launchpad LAST and pass placeholders -> reconfigure by ownership step.
        // Simpler: deploy launchpad first with infra wired; graduator and feeSplitter
        // accept registrar via owner-controlled setter (FeeSplitter) or constructor arg (Graduator).
        // Therefore we must deploy launchpad after we know graduator's deploy needs registrar.
        // Workaround: precompute launchpad address using nonce.

        uint256 testNonce = vm.getNonce(address(this));
        // We will deploy in order: graduator, then launchpad. So:
        // graduator nonce = testNonce
        // launchpad nonce = testNonce + 1
        address predictedLaunchpad = vm.computeCreateAddress(address(this), testNonce + 1);

        graduator = new Graduator({
            positionManager_: address(positionManager),
            factory_: address(factory),
            weth_: address(weth),
            registrar_: predictedLaunchpad
        });

        launchpad = new ZentriaLaunchpad({
            feeSplitter_: feeSplitter,
            graduator_: graduator,
            creatorVesting_: creatorVesting,
            weth_: address(weth),
            owner_: owner
        });
        require(address(launchpad) == predictedLaunchpad, "Setup: predicted launchpad mismatch");

        vm.prank(owner);
        feeSplitter.setRegistrar(address(launchpad));
    }

    function _createToken(
        address creator_,
        string memory name,
        string memory symbol,
        uint256 sniperWindow
    )
        internal
        returns (address token, address curve)
    {
        ZentriaLaunchpad.CreateParams memory p =
            ZentriaLaunchpad.CreateParams({name: name, symbol: symbol, sniperWindow: sniperWindow});
        vm.prank(creator_);
        (token, curve) = launchpad.createToken(p);
    }

    function _buy(address curve, address buyer, uint256 ethIn, uint256 minOut) internal returns (uint256 out) {
        vm.deal(buyer, buyer.balance + ethIn);
        vm.prank(buyer);
        out = ZentriaCurve(payable(curve)).buy{value: ethIn}(minOut);
    }

    function _sell(
        address curve,
        address seller,
        uint256 tokensIn,
        uint256 minEthOut
    )
        internal
        returns (uint256 ethOut)
    {
        ZentriaCurve c = ZentriaCurve(payable(curve));
        ZentriaToken t = c.token();
        vm.prank(seller);
        t.approve(curve, tokensIn);
        vm.prank(seller);
        ethOut = c.sell(tokensIn, minEthOut);
    }

    receive() external payable {}
}
