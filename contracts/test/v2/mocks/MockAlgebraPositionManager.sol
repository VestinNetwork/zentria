// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAlgebraPositionManager} from "src/v2/interfaces/IAlgebraPositionManager.sol";

/// @notice Minimal mock of the Camelot V3 / Algebra NonfungiblePositionManager.
///         Pulls token0/token1 from the caller and mints an LP NFT to the recipient.
///         Tracks pool addresses per (token0, token1) deterministically.
/// @dev Does not inherit IAlgebraPositionManager because OpenZeppelin's ERC721 declares
///      `safeTransferFrom(address,address,uint256)` as non-virtual; the function is satisfied
///      structurally by the inherited ERC721 implementation. Graduator only needs the ABI to
///      match at runtime.
contract MockAlgebraPositionManager is ERC721 {
    struct PoolInfo {
        address token0;
        address token1;
        uint160 sqrtPriceX96;
        bool initialized;
    }

    /// @dev poolKey -> PoolInfo
    mapping(bytes32 key => PoolInfo) public pools;
    /// @dev poolKey -> deterministic pool address (mock)
    mapping(bytes32 key => address pool) public poolOf;
    /// @dev tokenId -> (amount0, amount1, token0, token1)
    mapping(uint256 tokenId => uint128 liquidity) public liquidityOf;
    mapping(uint256 tokenId => uint256 amount0) public amount0Of;
    mapping(uint256 tokenId => uint256 amount1) public amount1Of;
    mapping(uint256 tokenId => address token0) public token0Of;
    mapping(uint256 tokenId => address token1) public token1Of;

    uint256 public nextTokenId = 1;
    uint256 public nextPoolNonce = 1;

    constructor() ERC721("Mock Algebra Positions", "MALG-POS") {}

    function _key(address t0, address t1) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(t0, t1));
    }

    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint160 sqrtPriceX96
    )
        external
        payable
        returns (address pool)
    {
        require(token0 < token1, "Mock: tokens unordered");
        bytes32 k = _key(token0, token1);
        pool = poolOf[k];
        if (pool == address(0)) {
            pool = address(uint160(uint256(keccak256(abi.encodePacked(k, nextPoolNonce++)))));
            poolOf[k] = pool;
            pools[k] = PoolInfo({token0: token0, token1: token1, sqrtPriceX96: sqrtPriceX96, initialized: true});
        }
    }

    function mint(IAlgebraPositionManager.MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        require(params.token0 < params.token1, "Mock: tokens unordered");
        require(params.deadline >= block.timestamp, "Mock: expired");

        // Pull both sides.
        if (params.amount0Desired > 0) {
            IERC20(params.token0).transferFrom(msg.sender, address(this), params.amount0Desired);
        }
        if (params.amount1Desired > 0) {
            IERC20(params.token1).transferFrom(msg.sender, address(this), params.amount1Desired);
        }
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;
        // Pretend liquidity is sqrt(amount0 * amount1) for the mock.
        liquidity = uint128(_sqrt(amount0 * amount1));

        tokenId = nextTokenId++;
        _safeMint(params.recipient, tokenId);
        liquidityOf[tokenId] = liquidity;
        amount0Of[tokenId] = amount0;
        amount1Of[tokenId] = amount1;
        token0Of[tokenId] = params.token0;
        token1Of[tokenId] = params.token1;
    }

    /// @dev ERC721 already implements `safeTransferFrom(address,address,uint256)` which
    ///      satisfies the IAlgebraPositionManager signature; no explicit override required.
    function _sqrt(uint256 x) private pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
