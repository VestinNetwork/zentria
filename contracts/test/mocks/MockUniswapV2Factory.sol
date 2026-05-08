// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockUniswapV2Pair} from "./MockUniswapV2Pair.sol";

contract MockUniswapV2Factory {
    mapping(address => mapping(address => address)) public pairs;
    address[] public allPairs;

    function getPair(address tokenA, address tokenB) external view returns (address) {
        return pairs[tokenA][tokenB];
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "same tokens");
        require(pairs[tokenA][tokenB] == address(0), "exists");
        MockUniswapV2Pair p = new MockUniswapV2Pair(tokenA, tokenB);
        pair = address(p);
        pairs[tokenA][tokenB] = pair;
        pairs[tokenB][tokenA] = pair;
        allPairs.push(pair);
    }
}
