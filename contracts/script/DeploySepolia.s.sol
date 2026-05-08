// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Launchpad} from "../src/Launchpad.sol";
import {LiquidityLocker} from "../src/LiquidityLocker.sol";
import {DevVesting} from "../src/DevVesting.sol";

import {MockWETH} from "../test/mocks/MockWETH.sol";
import {MockUniswapV2Factory} from "../test/mocks/MockUniswapV2Factory.sol";
import {MockUniswapV2Router} from "../test/mocks/MockUniswapV2Router.sol";

/// @notice Deploys a full Uniswap-V2-compatible stack and the launchpad on
///         Arbitrum Sepolia (where Uniswap V2 is not officially deployed).
///
/// Sepolia stack:
///   1. MockWETH       (replacement for canonical WETH)
///   2. MockV2Factory  (creates pair contracts)
///   3. MockV2Router   (addLiquidityETH that mimics real V2 behavior)
///   4. LiquidityLocker, DevVesting
///   5. Launchpad      (wired to the mock router + locker + vesting + treasury)
///
/// For mainnet, use Deploy.s.sol with the real Uniswap V2 router instead.
contract DeploySepolia is Script {
    function run()
        external
        returns (
            MockWETH weth,
            MockUniswapV2Factory factory,
            MockUniswapV2Router router,
            LiquidityLocker locker,
            DevVesting vesting,
            Launchpad launchpad
        )
    {
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address owner = vm.envOr("OWNER_ADDRESS", msg.sender);

        vm.startBroadcast();

        weth = new MockWETH();
        factory = new MockUniswapV2Factory();
        router = new MockUniswapV2Router(address(factory), address(weth));

        locker = new LiquidityLocker();
        vesting = new DevVesting();

        launchpad = new Launchpad({
            router_: address(router),
            liquidityLocker_: address(locker),
            devVesting_: address(vesting),
            treasury_: treasury,
            owner_: owner
        });

        vm.stopBroadcast();

        console2.log("=== Sepolia deployment complete ===");
        console2.log("WETH       :", address(weth));
        console2.log("Factory    :", address(factory));
        console2.log("Router     :", address(router));
        console2.log("Locker     :", address(locker));
        console2.log("Vesting    :", address(vesting));
        console2.log("Launchpad  :", address(launchpad));
        console2.log("Treasury   :", treasury);
        console2.log("Owner      :", owner);
    }
}
