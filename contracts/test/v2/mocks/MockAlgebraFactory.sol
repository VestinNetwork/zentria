// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAlgebraFactory} from "src/v2/interfaces/IAlgebraFactory.sol";

/// @notice Minimal Algebra factory mock; not exercised by the Graduator path but provided
///         to satisfy the constructor wiring in tests/scripts.
contract MockAlgebraFactory is IAlgebraFactory {
    mapping(bytes32 key => address pool) private _pools;

    function createPool(address tokenA, address tokenB) external returns (address pool) {
        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        bytes32 k = keccak256(abi.encodePacked(t0, t1));
        require(_pools[k] == address(0), "MockAlgebraFactory: already created");
        pool = address(uint160(uint256(keccak256(abi.encodePacked(t0, t1, "pool")))));
        _pools[k] = pool;
    }

    function poolByPair(address tokenA, address tokenB) external view returns (address pool) {
        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return _pools[keccak256(abi.encodePacked(t0, t1))];
    }
}
