// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {AntiSniper} from "./AntiSniper.sol";
import {CreatorVesting} from "./CreatorVesting.sol";
import {FeeSplitter} from "./FeeSplitter.sol";
import {Graduator} from "./Graduator.sol";
import {ZentriaToken} from "./ZentriaToken.sol";

/// @title ZentriaCurve
/// @notice The bonding curve. Per-token instance deployed by the launchpad. Implements:
///         - constant-product virtual-reserves curve (pump.fun-style)
///         - 1% per-trade fee in ETH split 50/30/20 (creator/protocol/boost-retained-on-curve)
///         - linear-decay sniper buy tax (99% → 1% over configurable window) → creator vesting
///         - atomic graduation to Camelot V3 + LP NFT burn at threshold
contract ZentriaCurve is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -------------------- Curve constants --------------------

    /// @notice Curve-side allocation: tokens available on the bonding curve.
    uint256 public constant CURVE_SUPPLY = 800_000_000 * 1e18;
    /// @notice Reserve allocation: tokens kept aside for graduation LP seed.
    uint256 public constant RESERVE_SUPPLY = 200_000_000 * 1e18;
    /// @notice Virtual token reserves (constant). Curve math uses V_T - tokens_sold.
    uint256 public constant V_T = 900_000_000 * 1e18;
    /// @notice Virtual ETH reserves at deploy. Stays constant over the lifetime of the curve.
    ///         Boost portion of fees adds to realEthReserves, not to this.
    uint256 public constant V_E = 4 ether;
    /// @notice Real-ETH threshold that triggers atomic graduation.
    uint256 public constant GRADUATION_THRESHOLD_ETH = 32 ether;

    /// @notice Total per-trade fee in basis points (1%).
    uint16 public constant TRADE_FEE_BPS = 100;
    /// @notice Of the trade volume, this many bps go to the creator (0.5%).
    uint16 public constant CREATOR_BPS = 50;
    /// @notice Of the trade volume, this many bps go to the protocol (0.3%).
    uint16 public constant PROTOCOL_BPS = 30;
    /// @notice Of the trade volume, this many bps stay on the curve as boost (0.2%).
    uint16 public constant BOOST_BPS = 20;
    uint16 public constant BPS_DEN = 10_000;

    /// @notice Cliff before any sniper-tax-buyback tokens unlock for the creator.
    uint64 public constant CREATOR_VESTING_CLIFF = 30 days;
    /// @notice Total duration (incl. cliff) of the creator vesting schedule.
    uint64 public constant CREATOR_VESTING_DURATION = 270 days;

    /// @notice Camelot V3 / Algebra full-range tick bounds (tickSpacing-aligned).
    int24 public constant TICK_LOWER = -887_220;
    int24 public constant TICK_UPPER = 887_220;

    // -------------------- Wiring --------------------

    ZentriaToken public immutable token;
    address public immutable weth;
    Graduator public immutable graduator;
    FeeSplitter public immutable feeSplitter;
    CreatorVesting public immutable creatorVesting;
    address public immutable launchpad;
    address public immutable creator;
    /// @notice Sniper-tax decay window in seconds. 0 disables the tax entirely.
    uint256 public immutable sniperWindow;

    // -------------------- Mutable state --------------------

    uint256 public realEthReserves;
    uint256 public realTokenReserves;
    uint256 public launchedAt;
    bool public initialized;
    bool public graduated;

    uint256 public creatorVestingScheduleId;
    bool public vestingScheduleInitialized;

    // -------------------- Events --------------------

    event Activated(uint256 launchedAt);
    event Bought(
        address indexed buyer, uint256 ethIn, uint256 tokensOutToBuyer, uint256 sniperTokensVested, uint256 totalFee
    );
    event Sold(address indexed seller, uint256 tokensIn, uint256 ethOutToSeller, uint256 totalFee);
    event Graduated(address indexed token, uint256 ethSeeded, uint256 tokensSeeded, uint160 sqrtPriceX96);

    // -------------------- Errors --------------------

    error NotLaunchpad();
    error AlreadyInitialized();
    error InsufficientTokenBalance();
    error NotTradable();
    error ZeroAmount();
    error SlippageExceeded();
    error SellTooLarge();
    error TransferFailed();
    error InvalidAddress();
    error InvalidWindow();

    constructor(
        ZentriaToken token_,
        address weth_,
        Graduator graduator_,
        FeeSplitter feeSplitter_,
        CreatorVesting creatorVesting_,
        address launchpad_,
        address creator_,
        uint256 sniperWindow_
    ) {
        if (
            address(token_) == address(0) || weth_ == address(0) || address(graduator_) == address(0)
                || address(feeSplitter_) == address(0) || address(creatorVesting_) == address(0)
                || launchpad_ == address(0) || creator_ == address(0)
        ) revert InvalidAddress();
        if (sniperWindow_ > AntiSniper.MAX_WINDOW_SECONDS) revert InvalidWindow();

        token = token_;
        weth = weth_;
        graduator = graduator_;
        feeSplitter = feeSplitter_;
        creatorVesting = creatorVesting_;
        launchpad = launchpad_;
        creator = creator_;
        sniperWindow = sniperWindow_;
        realTokenReserves = CURVE_SUPPLY;
    }

    /// @notice Called once by the launchpad after the full token supply has been transferred in.
    function activate() external {
        if (msg.sender != launchpad) revert NotLaunchpad();
        if (initialized) revert AlreadyInitialized();
        if (token.balanceOf(address(this)) < token.TOTAL_SUPPLY()) revert InsufficientTokenBalance();
        initialized = true;
        launchedAt = block.timestamp;
        emit Activated(launchedAt);
    }

    // -------------------- Trading --------------------

    /// @notice Buy tokens from the curve. msg.value is the ETH amount to spend.
    /// @param minTokensOut Minimum tokens (after sniper tax) the caller will accept.
    /// @return tokensToBuyer Tokens transferred to msg.sender.
    function buy(uint256 minTokensOut) external payable nonReentrant returns (uint256 tokensToBuyer) {
        if (!initialized || graduated) revert NotTradable();
        if (msg.value == 0) revert ZeroAmount();

        uint256 creatorFee = (msg.value * CREATOR_BPS) / BPS_DEN;
        uint256 protocolFee = (msg.value * PROTOCOL_BPS) / BPS_DEN;
        uint256 totalFee = (msg.value * TRADE_FEE_BPS) / BPS_DEN;
        uint256 ePurchase = msg.value - totalFee;

        // Curve math (pre-state).
        uint256 effEth = V_E + realEthReserves;
        uint256 effTokens = V_T - (CURVE_SUPPLY - realTokenReserves);
        uint256 newEffEth = effEth + ePurchase;
        uint256 newEffTokens = Math.mulDiv(effEth, effTokens, newEffEth);
        uint256 tokensOutGross = effTokens - newEffTokens;
        if (tokensOutGross > realTokenReserves) {
            tokensOutGross = realTokenReserves; // cap; can occur near graduation
        }

        // realEthReserves grows by everything except creator+protocol fees (i.e. ePurchase + boost).
        uint256 eKept = msg.value - creatorFee - protocolFee;

        // Apply sniper tax to determine user-vs-vesting share.
        uint16 sniperBps = AntiSniper.currentBuyTaxBps(launchedAt, sniperWindow);
        uint256 sniperTokens = (tokensOutGross * sniperBps) / BPS_DEN;
        tokensToBuyer = tokensOutGross - sniperTokens;
        if (tokensToBuyer < minTokensOut) revert SlippageExceeded();

        // Update reserves.
        realEthReserves += eKept;
        realTokenReserves -= tokensOutGross;

        // Forward fees to splitter (creator + protocol).
        if (creatorFee + protocolFee > 0) {
            feeSplitter.accrue{value: creatorFee + protocolFee}(address(token), creatorFee, protocolFee);
        }

        // Vest sniper tokens for the creator.
        if (sniperTokens > 0) {
            IERC20(address(token)).forceApprove(address(creatorVesting), sniperTokens);
            if (!vestingScheduleInitialized) {
                creatorVestingScheduleId = creatorVesting.createSchedule(
                    address(token), creator, sniperTokens, CREATOR_VESTING_CLIFF, CREATOR_VESTING_DURATION
                );
                vestingScheduleInitialized = true;
            } else {
                creatorVesting.topUp(creatorVestingScheduleId, sniperTokens);
            }
        }

        // Pay buyer.
        if (tokensToBuyer > 0) {
            IERC20(address(token)).safeTransfer(msg.sender, tokensToBuyer);
        }

        emit Bought(msg.sender, msg.value, tokensToBuyer, sniperTokens, totalFee);

        if (realEthReserves >= GRADUATION_THRESHOLD_ETH) {
            _graduate();
        }
    }

    /// @notice Sell tokens back to the curve.
    /// @param tokensIn Amount of token (in wei units) the caller wants to sell.
    /// @param minEthOut Minimum ETH out the caller will accept (after fee).
    function sell(uint256 tokensIn, uint256 minEthOut) external nonReentrant returns (uint256 ethOut) {
        if (!initialized || graduated) revert NotTradable();
        if (tokensIn == 0) revert ZeroAmount();

        uint256 effEth = V_E + realEthReserves;
        uint256 effTokens = V_T - (CURVE_SUPPLY - realTokenReserves);
        uint256 newEffTokens = effTokens + tokensIn;
        if (newEffTokens > V_T) revert SellTooLarge(); // R_t cannot exceed CURVE_SUPPLY

        uint256 newEffEth = Math.mulDiv(effEth, effTokens, newEffTokens);
        uint256 ethOutGross = effEth - newEffEth;

        uint256 creatorFee = (ethOutGross * CREATOR_BPS) / BPS_DEN;
        uint256 protocolFee = (ethOutGross * PROTOCOL_BPS) / BPS_DEN;
        uint256 boostFee = (ethOutGross * BOOST_BPS) / BPS_DEN;
        ethOut = ethOutGross - creatorFee - protocolFee - boostFee;
        if (ethOut < minEthOut) revert SlippageExceeded();

        // Pull tokens.
        IERC20(address(token)).safeTransferFrom(msg.sender, address(this), tokensIn);

        // Update reserves: boost stays on curve, only creator + protocol + ethOut leave.
        realEthReserves -= (ethOutGross - boostFee);
        realTokenReserves += tokensIn;

        // Forward fees.
        if (creatorFee + protocolFee > 0) {
            feeSplitter.accrue{value: creatorFee + protocolFee}(address(token), creatorFee, protocolFee);
        }

        // Pay seller.
        (bool ok,) = msg.sender.call{value: ethOut}("");
        if (!ok) revert TransferFailed();

        emit Sold(msg.sender, tokensIn, ethOut, creatorFee + protocolFee + boostFee);
    }

    // -------------------- Quotes (off-chain helpers) --------------------

    /// @notice Quote how many tokens a buyer would receive (after sniper tax) for ethIn ETH.
    function quoteBuy(uint256 ethIn) external view returns (uint256 tokensToBuyer, uint16 sniperBps) {
        if (!initialized || graduated || ethIn == 0) return (0, 0);
        uint256 totalFee = (ethIn * TRADE_FEE_BPS) / BPS_DEN;
        uint256 ePurchase = ethIn - totalFee;
        uint256 effEth = V_E + realEthReserves;
        uint256 effTokens = V_T - (CURVE_SUPPLY - realTokenReserves);
        uint256 newEffTokens = Math.mulDiv(effEth, effTokens, effEth + ePurchase);
        uint256 tokensOutGross = effTokens - newEffTokens;
        if (tokensOutGross > realTokenReserves) tokensOutGross = realTokenReserves;
        sniperBps = AntiSniper.currentBuyTaxBps(launchedAt, sniperWindow);
        tokensToBuyer = tokensOutGross - (tokensOutGross * sniperBps) / BPS_DEN;
    }

    /// @notice Quote how much ETH a seller would receive (net of fee) for tokensIn tokens.
    /// @dev Fee computation mirrors `sell()` exactly: three independent floors (creator,
    ///      protocol, boost) summed, rather than a single combined floor on the total fee.
    ///      This keeps `quoteSell` and the actual `sell()` payout bit-identical.
    function quoteSell(uint256 tokensIn) external view returns (uint256 ethOut) {
        if (!initialized || graduated || tokensIn == 0) return 0;
        uint256 effEth = V_E + realEthReserves;
        uint256 effTokens = V_T - (CURVE_SUPPLY - realTokenReserves);
        uint256 newEffTokens = effTokens + tokensIn;
        if (newEffTokens > V_T) return 0;
        uint256 newEffEth = Math.mulDiv(effEth, effTokens, newEffTokens);
        uint256 ethOutGross = effEth - newEffEth;
        uint256 creatorFee = (ethOutGross * CREATOR_BPS) / BPS_DEN;
        uint256 protocolFee = (ethOutGross * PROTOCOL_BPS) / BPS_DEN;
        uint256 boostFee = (ethOutGross * BOOST_BPS) / BPS_DEN;
        ethOut = ethOutGross - creatorFee - protocolFee - boostFee;
    }

    /// @notice Current bonding-curve mid price in (wei ETH) per (1e18 token wei). Useful for UI.
    function midPrice() external view returns (uint256) {
        uint256 effEth = V_E + realEthReserves;
        uint256 effTokens = V_T - (CURVE_SUPPLY - realTokenReserves);
        return Math.mulDiv(effEth, 1e18, effTokens);
    }

    // -------------------- Graduation --------------------

    function _graduate() private {
        graduated = true;

        uint256 ethBalance = address(this).balance;
        uint256 tokenBalance = IERC20(address(token)).balanceOf(address(this));

        // Compute initial sqrtPriceX96 for the V3 pool from the actual deposit ratio.
        bool tokenIsToken0 = address(token) < weth;
        uint256 amount0 = tokenIsToken0 ? tokenBalance : ethBalance;
        uint256 amount1 = tokenIsToken0 ? ethBalance : tokenBalance;
        uint160 sqrtPriceX96 = _computeSqrtPriceX96(amount0, amount1);

        IERC20(address(token)).forceApprove(address(graduator), tokenBalance);
        graduator.graduate{value: ethBalance}(address(token), tokenBalance, TICK_LOWER, TICK_UPPER, sqrtPriceX96);

        emit Graduated(address(token), ethBalance, tokenBalance, sqrtPriceX96);
    }

    /// @dev sqrtPriceX96 = floor(sqrt(amount1/amount0) * 2^96). Uses 1e36 fixed-point scaling
    ///      to avoid overflow in the intermediate multiplication.
    function _computeSqrtPriceX96(uint256 amount0, uint256 amount1) private pure returns (uint160) {
        uint256 ratio = Math.mulDiv(amount1, 1e36, amount0); // (amount1/amount0) * 1e36
        uint256 sqrtRatio = Math.sqrt(ratio); // (sqrt(amount1/amount0)) * 1e18
        return uint160(Math.mulDiv(sqrtRatio, 1 << 96, 1e18));
    }
}
