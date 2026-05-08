// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAlgebraFactory} from "./interfaces/IAlgebraFactory.sol";
import {IAlgebraPositionManager} from "./interfaces/IAlgebraPositionManager.sol";
import {IWETH} from "./interfaces/IWETH.sol";

/// @title Graduator
/// @notice Migrates a bonding-curve token into a Camelot V3 (Algebra) full-range LP and
///         immediately burns the LP NFT. After graduation the LP is unrecoverable — no
///         creator, dev, or platform can pull liquidity. This is the v2 anti-rug guarantee.
/// @dev `graduate` is callable only by registered curves. Each curve gets registered by the
///      launchpad at deploy time so randoms can't trigger early graduations.
contract Graduator is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Burn address for the LP NFT. EOA-style sentinel.
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    /// @notice Algebra/Camelot V3 NonfungiblePositionManager.
    IAlgebraPositionManager public immutable positionManager;
    /// @notice Algebra/Camelot V3 factory (used to read pool address; pool init happens via NFPM).
    IAlgebraFactory public immutable factory;
    /// @notice WETH9.
    IWETH public immutable weth;

    /// @notice Registrar (typically the launchpad) authorized to register curves.
    address public immutable registrar;

    /// @notice token => curve allowed to call graduate() for that token.
    mapping(address token => address curve) public curveOf;
    /// @notice token => true once graduated. One-shot; cannot be re-graduated.
    mapping(address token => bool graduated) public isGraduated;
    /// @notice token => Camelot V3 pool address that was created.
    mapping(address token => address pool) public poolOf;
    /// @notice token => LP NFT tokenId.
    mapping(address token => uint256 lpId) public lpTokenIdOf;

    event CurveRegistered(address indexed token, address indexed curve);
    event Graduated(
        address indexed token, address indexed pool, uint256 ethSeeded, uint256 tokensSeeded, uint256 lpTokenId
    );

    error NotRegistrar();
    error NotCurve();
    error AlreadyRegistered();
    error AlreadyGraduated();
    error InvalidAddress();
    error InvalidAmounts();

    constructor(address positionManager_, address factory_, address weth_, address registrar_) {
        if (positionManager_ == address(0) || factory_ == address(0) || weth_ == address(0) || registrar_ == address(0))
        revert InvalidAddress();
        positionManager = IAlgebraPositionManager(positionManager_);
        factory = IAlgebraFactory(factory_);
        weth = IWETH(weth_);
        registrar = registrar_;
    }

    /// @notice Register a curve as the only address allowed to graduate `token`.
    function registerCurve(address token, address curve) external {
        if (msg.sender != registrar) revert NotRegistrar();
        if (token == address(0) || curve == address(0)) revert InvalidAddress();
        if (curveOf[token] != address(0)) revert AlreadyRegistered();
        curveOf[token] = curve;
        emit CurveRegistered(token, curve);
    }

    /// @notice Migrate the bonding curve's reserves to Camelot V3 and burn the LP NFT.
    /// @param token The token graduating.
    /// @param tokenAmount Tokens being seeded (sitting in the curve, transferable to here).
    /// @param tickLower Lower tick of the LP range. Use a wide range (full-range emulation).
    /// @param tickUpper Upper tick.
    /// @param sqrtPriceX96 Initial price encoding for the pool. Must match the curve's last price.
    function graduate(
        address token,
        uint256 tokenAmount,
        int24 tickLower,
        int24 tickUpper,
        uint160 sqrtPriceX96
    )
        external
        payable
        nonReentrant
        returns (address pool, uint256 lpTokenId)
    {
        if (msg.sender != curveOf[token]) revert NotCurve();
        if (isGraduated[token]) revert AlreadyGraduated();
        if (msg.value == 0 || tokenAmount == 0) revert InvalidAmounts();

        // Pull tokens from the curve.
        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);

        // Wrap incoming ETH to WETH so we can deposit a token/token pair.
        weth.deposit{value: msg.value}();

        // Sort tokens — Algebra expects token0 < token1.
        (address token0, address token1, uint256 amount0, uint256 amount1) = address(token) < address(weth)
            ? (token, address(weth), tokenAmount, msg.value)
            : (address(weth), token, msg.value, tokenAmount);

        // Initialize pool if not exists. If `token` < `weth` then sqrtPrice describes weth/token,
        // else token/weth — caller is responsible for matching sqrtPriceX96 to the sorted order.
        pool = positionManager.createAndInitializePoolIfNecessary(token0, token1, sqrtPriceX96);

        // Approve NFPM to pull both sides.
        IERC20(token0).forceApprove(address(positionManager), amount0);
        IERC20(token1).forceApprove(address(positionManager), amount1);

        // Mint full-range LP. Recipient = address(this) so we can immediately burn the NFT.
        IAlgebraPositionManager.MintParams memory params = IAlgebraPositionManager.MintParams({
            token0: token0,
            token1: token1,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 60
        });
        (lpTokenId,,,) = positionManager.mint(params);

        // Burn the LP NFT to make the position permanently inaccessible.
        positionManager.safeTransferFrom(address(this), DEAD, lpTokenId);

        isGraduated[token] = true;
        poolOf[token] = pool;
        lpTokenIdOf[token] = lpTokenId;

        emit Graduated(token, pool, msg.value, tokenAmount, lpTokenId);
    }

    /// @dev Required so the NFPM can transfer the freshly minted NFT into this contract before
    ///      we forward it to DEAD.
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
