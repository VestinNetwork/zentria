// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {MemeToken} from "./MemeToken.sol";
import {LiquidityLocker} from "./LiquidityLocker.sol";
import {DevVesting} from "./DevVesting.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";

/// @title Launchpad
/// @notice One-transaction memecoin launch with hardcoded anti-rug guarantees:
///         - 1% platform fee on the ETH sent for liquidity
///         - 99% of ETH + (totalSupply - devAllocation) tokens added to Uniswap V2
///         - LP tokens automatically locked for >= 6 months in the LiquidityLocker
///         - Dev allocation (max 5% of supply) sent to DevVesting (30d cliff + 6m linear)
///         - Trading is opened atomically at the end so no rug-pull window exists
contract Launchpad is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Hard cap on platform fee (1%).
    uint16 public constant PLATFORM_FEE_BPS = 100;
    uint16 public constant BPS_DENOMINATOR = 10000;
    /// @notice Max dev allocation as bps of supply (5%).
    uint16 public constant MAX_DEV_BPS = 500;
    /// @notice Min lock duration enforced by the launchpad (6 months).
    uint256 public constant MIN_LOCK_DURATION = 180 days;
    /// @notice Min initial liquidity to discourage spam launches (in wei).
    uint256 public constant MIN_INITIAL_LIQUIDITY = 0.01 ether;

    IUniswapV2Router02 public immutable router;
    IUniswapV2Factory public immutable factory;
    LiquidityLocker public immutable liquidityLocker;
    DevVesting public immutable devVesting;
    address public immutable WETH;

    /// @notice Treasury that receives the 1% launch fee + 20% of ongoing tax.
    address public treasury;

    struct LaunchParams {
        string name;
        string symbol;
        uint256 totalSupply;       // whole tokens (will be * 10**18)
        uint16 buyTaxBps;          // <= 500
        uint16 sellTaxBps;         // <= 500
        uint16 maxWalletBps;       // <= 1000 (10%)
        uint16 maxTxBps;           // <= 1000 (10%)
        uint16 devAllocationBps;   // <= 500 (5%)
        uint256 lockDuration;      // >= 180 days
    }

    struct LaunchInfo {
        address token;
        address pair;
        address dev;
        uint256 lockId;
        uint256 vestingId;        // type(uint256).max if no dev allocation
        uint256 createdAt;
    }

    /// @notice All launches ever performed.
    LaunchInfo[] private _launches;
    /// @notice Map token address -> launch index + 1 (0 means not found).
    mapping(address token => uint256 launchIdPlusOne) private _launchByToken;

    event TokenLaunched(
        uint256 indexed launchId,
        address indexed token,
        address indexed dev,
        address pair,
        uint256 lockId,
        uint256 vestingId,
        uint256 ethLiquidity,
        uint256 platformFee
    );
    event TreasuryUpdated(address indexed previousTreasury, address indexed newTreasury);

    error InvalidParams();
    error InsufficientLiquidity();
    error TaxTooHigh();
    error DevAllocationTooHigh();
    error MaxWalletTooLow();
    error LockTooShort();
    error TransferFailed();
    error InvalidAddress();

    constructor(
        address router_,
        address liquidityLocker_,
        address devVesting_,
        address treasury_,
        address owner_
    ) Ownable(owner_) {
        if (
            router_ == address(0) || liquidityLocker_ == address(0) || devVesting_ == address(0)
                || treasury_ == address(0) || owner_ == address(0)
        ) {
            revert InvalidAddress();
        }
        router = IUniswapV2Router02(router_);
        factory = IUniswapV2Factory(router.factory());
        WETH = router.WETH();
        liquidityLocker = LiquidityLocker(liquidityLocker_);
        devVesting = DevVesting(devVesting_);
        treasury = treasury_;
    }

    /// @notice Launch a new memecoin in a single atomic transaction.
    /// @dev Sender (msg.sender) becomes the dev: receives 80% of tax + the vested allocation.
    /// @param p Launch parameters.
    /// @return token Newly deployed MemeToken address.
    function launch(LaunchParams calldata p)
        external
        payable
        nonReentrant
        returns (address token)
    {
        // 1. Param validation
        if (bytes(p.name).length == 0 || bytes(p.symbol).length == 0) revert InvalidParams();
        if (p.totalSupply == 0) revert InvalidParams();
        if (p.buyTaxBps > 500 || p.sellTaxBps > 500) revert TaxTooHigh();
        if (p.devAllocationBps > MAX_DEV_BPS) revert DevAllocationTooHigh();
        // Max wallet must be at least max tx; both must be > 0 to avoid bricking the token.
        if (p.maxWalletBps == 0 || p.maxTxBps == 0 || p.maxWalletBps < p.maxTxBps) revert MaxWalletTooLow();
        if (p.lockDuration < MIN_LOCK_DURATION) revert LockTooShort();
        if (msg.value < MIN_INITIAL_LIQUIDITY) revert InsufficientLiquidity();

        address dev = msg.sender;

        // 2. Deduct 1% platform fee from sent ETH; rest goes into LP.
        uint256 platformFee = (msg.value * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        uint256 lpEth = msg.value - platformFee;
        if (platformFee > 0) {
            (bool sent,) = treasury.call{value: platformFee}("");
            if (!sent) revert TransferFailed();
        }

        // 3. Deploy the MemeToken (mints full supply to this contract).
        MemeToken meme = new MemeToken({
            name_: p.name,
            symbol_: p.symbol,
            totalSupply_: p.totalSupply,
            buyTaxBps_: p.buyTaxBps,
            sellTaxBps_: p.sellTaxBps,
            maxWalletBps_: p.maxWalletBps,
            maxTxBps_: p.maxTxBps,
            devWallet_: dev,
            platformTreasury_: treasury,
            launchpad_: address(this)
        });
        token = address(meme);
        uint256 totalSupplyWei = meme.totalSupply();

        // 4. Configure tax + limit exclusions for system addresses involved in the launch.
        meme.setExcludedFromTax(address(devVesting), true);
        meme.setExcludedFromTax(address(router), true);
        meme.setExcludedFromLimits(address(devVesting), true);
        meme.setExcludedFromLimits(address(router), true);

        // 5. Pre-create the AMM pair and mark it as such so the upcoming addLiquidityETH transfer
        //    to the pair bypasses max-wallet limits. Tax does not fire because the launchpad is
        //    excluded from tax on the from-side.
        address pair = factory.getPair(token, WETH);
        if (pair == address(0)) {
            pair = factory.createPair(token, WETH);
        }
        meme.setAmmPair(pair, true);

        // 6. Compute dev allocation; rest goes to LP.
        uint256 devAmount = (totalSupplyWei * p.devAllocationBps) / BPS_DENOMINATOR;
        uint256 lpTokenAmount = totalSupplyWei - devAmount;

        // 7. Send dev allocation into vesting.
        uint256 vestingId = type(uint256).max;
        if (devAmount > 0) {
            IERC20(token).forceApprove(address(devVesting), devAmount);
            vestingId = devVesting.createVesting(token, dev, devAmount);
        }

        // 8. Add liquidity to Uniswap V2.
        IERC20(token).forceApprove(address(router), lpTokenAmount);
        router.addLiquidityETH{value: lpEth}({
            token: token,
            amountTokenDesired: lpTokenAmount,
            amountTokenMin: 0,
            amountETHMin: 0,
            to: address(this),
            deadline: block.timestamp + 1
        });

        // 7. Lock LP tokens.
        uint256 lpBalance = IERC20(pair).balanceOf(address(this));
        IERC20(pair).forceApprove(address(liquidityLocker), lpBalance);
        uint256 lockId = liquidityLocker.lock({
            token: pair,
            amount: lpBalance,
            duration: p.lockDuration,
            lockOwner: dev
        });

        // 8. Open trading + transfer ownership to dev.
        meme.openTrading();
        meme.transferOwnership(dev);

        // 9. Record launch.
        uint256 launchId = _launches.length;
        _launches.push(
            LaunchInfo({
                token: token,
                pair: pair,
                dev: dev,
                lockId: lockId,
                vestingId: vestingId,
                createdAt: block.timestamp
            })
        );
        _launchByToken[token] = launchId + 1;

        emit TokenLaunched(launchId, token, dev, pair, lockId, vestingId, lpEth, platformFee);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert InvalidAddress();
        address previous = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(previous, newTreasury);
    }

    function getLaunch(uint256 launchId) external view returns (LaunchInfo memory) {
        return _launches[launchId];
    }

    function getLaunchByToken(address token) external view returns (LaunchInfo memory) {
        uint256 idPlusOne = _launchByToken[token];
        require(idPlusOne != 0, "Launchpad: token not launched here");
        return _launches[idPlusOne - 1];
    }

    function totalLaunches() external view returns (uint256) {
        return _launches.length;
    }

    receive() external payable {}
}
