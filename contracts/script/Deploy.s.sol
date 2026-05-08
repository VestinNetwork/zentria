// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {Launchpad} from "../src/Launchpad.sol";
import {LiquidityLocker} from "../src/LiquidityLocker.sol";
import {DevVesting} from "../src/DevVesting.sol";

/// @notice Deploys the launchpad stack to a target chain.
/// @dev Configure router/treasury via env vars:
///        ROUTER_ADDRESS  - Uniswap V2 router on the target chain
///        TREASURY_ADDRESS - address that receives platform fees
///        OWNER_ADDRESS   - launchpad admin (defaults to msg.sender)
///
/// Common router addresses:
///   Arbitrum One        : 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24 (Uniswap V2)
///   Arbitrum Sepolia    : deploy your own SushiSwap/Uniswap V2 fork or use a mock for tests
contract Deploy is Script {
    function run()
        external
        returns (LiquidityLocker locker, DevVesting vesting, Launchpad launchpad)
    {
        address router = vm.envAddress("ROUTER_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address owner = vm.envOr("OWNER_ADDRESS", msg.sender);

        vm.startBroadcast();
        locker = new LiquidityLocker();
        vesting = new DevVesting();
        launchpad = new Launchpad({
            router_: router,
            liquidityLocker_: address(locker),
            devVesting_: address(vesting),
            treasury_: treasury,
            owner_: owner
        });
        vm.stopBroadcast();

        console2.log("LiquidityLocker:", address(locker));
        console2.log("DevVesting     :", address(vesting));
        console2.log("Launchpad      :", address(launchpad));
        console2.log("Router         :", router);
        console2.log("Treasury       :", treasury);
        console2.log("Owner          :", owner);
    }
}
