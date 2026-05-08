// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MemeToken
/// @notice ERC20 with configurable buy/sell tax, max wallet, max tx, and anti-rug guarantees.
/// @dev Tax parameters are immutable after deployment to prevent honeypot rug pulls.
///      80% of tax goes to the dev wallet, 20% goes to the platform treasury (hardcoded).
contract MemeToken is ERC20, Ownable {
    /// @notice Hard cap on buy or sell tax (5% each).
    uint16 public constant MAX_TAX_BPS = 500;
    /// @notice Hard cap on dev share of supply (5%).
    uint16 public constant MAX_DEV_BPS = 500;
    /// @notice Platform's cut of collected tax (20%).
    uint16 public constant PLATFORM_TAX_SHARE_BPS = 2000;
    /// @notice Basis-points denominator (100%).
    uint16 public constant BPS_DENOMINATOR = 10000;
    /// @notice Latest possible automatic limits expiry (24 hours after launch).
    uint256 public constant MAX_LIMITS_DURATION = 24 hours;

    /// @notice Buy tax in basis points, immutable after deployment.
    uint16 public immutable buyTaxBps;
    /// @notice Sell tax in basis points, immutable after deployment.
    uint16 public immutable sellTaxBps;
    /// @notice Max balance a non-excluded wallet can hold while limits are active.
    uint256 public immutable maxWalletAmount;
    /// @notice Max amount that can be transferred in a single tx while limits are active.
    uint256 public immutable maxTxAmount;
    /// @notice Timestamp at which max wallet/tx limits auto-expire.
    uint256 public immutable limitsExpireAt;
    /// @notice Address that receives the 80% dev share of tax.
    address public immutable devWallet;
    /// @notice Address that receives the 20% platform share of tax.
    address public immutable platformTreasury;

    /// @notice Set of pair addresses where transfers are taxed (typically the Uniswap V2 pair).
    mapping(address pair => bool isPair) public isAmmPair;
    /// @notice Set of addresses excluded from tax (router, treasury, dev, vesting, etc).
    mapping(address account => bool isExcluded) public isExcludedFromTax;
    /// @notice Set of addresses excluded from max wallet/tx limits.
    mapping(address account => bool isExcluded) public isExcludedFromLimits;

    /// @notice True once trading has been opened by the launchpad.
    bool public tradingOpen;
    /// @notice True once limits have been manually disabled (one-way switch).
    bool public limitsDisabled;

    event TradingOpened();
    event LimitsDisabled();
    event AmmPairSet(address indexed pair, bool isPair);
    event ExcludedFromTax(address indexed account, bool excluded);
    event ExcludedFromLimits(address indexed account, bool excluded);
    event TaxCollected(address indexed from, address indexed to, uint256 devAmount, uint256 platformAmount);

    error TradingNotOpen();
    error MaxWalletExceeded();
    error MaxTxExceeded();
    error TaxTooHigh();
    error InvalidAddress();
    error LimitsAlreadyDisabled();

    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    /// @param totalSupply_ Total supply (in whole tokens, will be multiplied by 10**decimals).
    /// @param buyTaxBps_ Buy tax in basis points (max 500 = 5%).
    /// @param sellTaxBps_ Sell tax in basis points (max 500 = 5%).
    /// @param maxWalletBps_ Max wallet as bps of supply (e.g. 200 = 2%).
    /// @param maxTxBps_ Max tx as bps of supply (e.g. 100 = 1%).
    /// @param devWallet_ Receives 80% of taxes.
    /// @param platformTreasury_ Receives 20% of taxes.
    /// @param launchpad_ Address of the launchpad orchestrator (initial owner).
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        uint16 buyTaxBps_,
        uint16 sellTaxBps_,
        uint16 maxWalletBps_,
        uint16 maxTxBps_,
        address devWallet_,
        address platformTreasury_,
        address launchpad_
    )
        ERC20(name_, symbol_)
        Ownable(launchpad_)
    {
        if (buyTaxBps_ > MAX_TAX_BPS || sellTaxBps_ > MAX_TAX_BPS) revert TaxTooHigh();
        if (devWallet_ == address(0) || platformTreasury_ == address(0) || launchpad_ == address(0)) {
            revert InvalidAddress();
        }

        buyTaxBps = buyTaxBps_;
        sellTaxBps = sellTaxBps_;
        devWallet = devWallet_;
        platformTreasury = platformTreasury_;

        uint256 supply = totalSupply_ * 10 ** decimals();
        maxWalletAmount = (supply * maxWalletBps_) / BPS_DENOMINATOR;
        maxTxAmount = (supply * maxTxBps_) / BPS_DENOMINATOR;
        limitsExpireAt = block.timestamp + MAX_LIMITS_DURATION;

        // Mint full supply to launchpad which will distribute it (LP + vesting).
        _mint(launchpad_, supply);

        // Default tax/limit exclusions for system addresses.
        isExcludedFromTax[launchpad_] = true;
        isExcludedFromTax[devWallet_] = true;
        isExcludedFromTax[platformTreasury_] = true;
        isExcludedFromLimits[launchpad_] = true;
        isExcludedFromLimits[devWallet_] = true;
        isExcludedFromLimits[platformTreasury_] = true;
        isExcludedFromLimits[address(this)] = true;
    }

    /// @notice Called once by the launchpad after liquidity is seeded to enable public trading.
    function openTrading() external onlyOwner {
        tradingOpen = true;
        emit TradingOpened();
    }

    /// @notice Marks an address as an AMM pair (transfers to/from this address are taxed).
    function setAmmPair(address pair, bool isPair) external onlyOwner {
        if (pair == address(0)) revert InvalidAddress();
        isAmmPair[pair] = isPair;
        // Pairs are auto-excluded from limits since they hold most of the supply.
        isExcludedFromLimits[pair] = isPair;
        emit AmmPairSet(pair, isPair);
    }

    /// @notice Permanently disables max wallet/tx limits before the auto-expiry.
    function disableLimits() external onlyOwner {
        if (limitsDisabled) revert LimitsAlreadyDisabled();
        limitsDisabled = true;
        emit LimitsDisabled();
    }

    /// @notice Returns true if max wallet/tx are currently enforced.
    function limitsActive() public view returns (bool) {
        return !limitsDisabled && block.timestamp < limitsExpireAt;
    }

    function setExcludedFromTax(address account, bool excluded) external onlyOwner {
        isExcludedFromTax[account] = excluded;
        emit ExcludedFromTax(account, excluded);
    }

    function setExcludedFromLimits(address account, bool excluded) external onlyOwner {
        isExcludedFromLimits[account] = excluded;
        emit ExcludedFromLimits(account, excluded);
    }

    /// @dev Override of ERC20 _update to apply tax + limits on every transfer.
    function _update(address from, address to, uint256 value) internal override {
        // Mint and burn paths: skip all logic.
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        // Trading must be open unless one side is excluded (e.g. launchpad seeding LP).
        if (!tradingOpen && !isExcludedFromTax[from] && !isExcludedFromTax[to]) {
            revert TradingNotOpen();
        }

        // Apply max tx + max wallet limits while active.
        if (limitsActive()) {
            if (!isExcludedFromLimits[from] && !isExcludedFromLimits[to]) {
                if (value > maxTxAmount) revert MaxTxExceeded();
            }
            if (!isExcludedFromLimits[to]) {
                if (balanceOf(to) + value > maxWalletAmount) revert MaxWalletExceeded();
            }
        }

        // Compute tax. Only buys (from pair) and sells (to pair) are taxed.
        uint256 taxAmount;
        if (!isExcludedFromTax[from] && !isExcludedFromTax[to]) {
            if (isAmmPair[from] && buyTaxBps > 0) {
                taxAmount = (value * buyTaxBps) / BPS_DENOMINATOR;
            } else if (isAmmPair[to] && sellTaxBps > 0) {
                taxAmount = (value * sellTaxBps) / BPS_DENOMINATOR;
            }
        }

        if (taxAmount > 0) {
            uint256 platformShare = (taxAmount * PLATFORM_TAX_SHARE_BPS) / BPS_DENOMINATOR;
            uint256 devShare = taxAmount - platformShare;
            super._update(from, platformTreasury, platformShare);
            super._update(from, devWallet, devShare);
            emit TaxCollected(from, to, devShare, platformShare);
            value -= taxAmount;
        }

        super._update(from, to, value);
    }
}
