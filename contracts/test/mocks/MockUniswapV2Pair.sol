// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Minimal mock LP token used by MockUniswapV2Router/Factory for tests.
contract MockUniswapV2Pair is ERC20 {
    address public token0;
    address public token1;
    address public factory;

    constructor(address tokenA, address tokenB) ERC20("Mock LP", "MLP") {
        factory = msg.sender;
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
