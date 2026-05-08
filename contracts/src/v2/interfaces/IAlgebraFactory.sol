// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal Camelot V3 / Algebra factory interface.
interface IAlgebraFactory {
    function createPool(address tokenA, address tokenB) external returns (address pool);
    function poolByPair(address tokenA, address tokenB) external view returns (address pool);
}
