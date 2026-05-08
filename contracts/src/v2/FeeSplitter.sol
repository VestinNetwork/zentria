// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title FeeSplitter
/// @notice Central accountant for per-trade fees collected by the bonding curve.
///         Books credits in ETH for (creator) and (protocol) per token, and exposes
///         pull-based claim functions. Fees come ONLY from registered curves.
contract FeeSplitter is Ownable2Step, ReentrancyGuard {
    /// @notice Address authorized to register curves; typically the launchpad.
    address public registrar;

    /// @notice Recipient of the protocol cut.
    address public treasury;

    /// @notice token => curve allowed to call accrue() for that token.
    mapping(address token => address curve) public curveOf;
    /// @notice token => creator wallet that can claim creator share.
    mapping(address token => address creator) public creatorOf;

    /// @notice token => unclaimed ETH credited to the creator.
    mapping(address token => uint256 wei_) public creatorBalance;
    /// @notice token => unclaimed ETH credited to the protocol treasury.
    mapping(address token => uint256 wei_) public protocolBalance;

    /// @notice Lifetime ETH credited to creator/protocol per token (analytics).
    mapping(address token => uint256 wei_) public lifetimeCreator;
    mapping(address token => uint256 wei_) public lifetimeProtocol;

    event RegistrarUpdated(address indexed previous, address indexed current);
    event TreasuryUpdated(address indexed previous, address indexed current);
    event CurveRegistered(address indexed token, address indexed curve, address indexed creator);
    event Accrued(address indexed token, uint256 creatorWei, uint256 protocolWei);
    event CreatorClaimed(address indexed token, address indexed creator, uint256 amount);
    event ProtocolClaimed(address indexed token, address indexed treasury, uint256 amount);

    error NotRegistrar();
    error NotCurve();
    error NotCreator();
    error AlreadyRegistered();
    error InvalidAddress();
    error MismatchedFunds();
    error NothingToClaim();
    error TransferFailed();

    constructor(address owner_, address treasury_) Ownable(owner_) {
        if (owner_ == address(0) || treasury_ == address(0)) revert InvalidAddress();
        treasury = treasury_;
    }

    modifier onlyRegistrar() {
        if (msg.sender != registrar) revert NotRegistrar();
        _;
    }

    function setRegistrar(address newRegistrar) external onlyOwner {
        if (newRegistrar == address(0)) revert InvalidAddress();
        emit RegistrarUpdated(registrar, newRegistrar);
        registrar = newRegistrar;
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert InvalidAddress();
        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    /// @notice Register a (token, curve, creator) triple. Called once per token by the launchpad.
    function registerCurve(address token, address curve, address creator) external onlyRegistrar {
        if (token == address(0) || curve == address(0) || creator == address(0)) revert InvalidAddress();
        if (curveOf[token] != address(0)) revert AlreadyRegistered();
        curveOf[token] = curve;
        creatorOf[token] = creator;
        emit CurveRegistered(token, curve, creator);
    }

    /// @notice Called by the registered curve with msg.value == creatorWei + protocolWei.
    function accrue(address token, uint256 creatorWei, uint256 protocolWei) external payable nonReentrant {
        if (msg.sender != curveOf[token]) revert NotCurve();
        if (msg.value != creatorWei + protocolWei) revert MismatchedFunds();

        if (creatorWei > 0) {
            creatorBalance[token] += creatorWei;
            lifetimeCreator[token] += creatorWei;
        }
        if (protocolWei > 0) {
            protocolBalance[token] += protocolWei;
            lifetimeProtocol[token] += protocolWei;
        }

        emit Accrued(token, creatorWei, protocolWei);
    }

    /// @notice Creator claim. Anyone can call but funds always go to the registered creator.
    function claimCreator(address token) external nonReentrant returns (uint256 amount) {
        amount = creatorBalance[token];
        if (amount == 0) revert NothingToClaim();
        address creator = creatorOf[token];
        if (creator == address(0)) revert NotCreator();
        creatorBalance[token] = 0;
        (bool ok,) = creator.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit CreatorClaimed(token, creator, amount);
    }

    /// @notice Protocol claim. Anyone can call but funds always go to the current treasury.
    function claimProtocol(address token) external nonReentrant returns (uint256 amount) {
        amount = protocolBalance[token];
        if (amount == 0) revert NothingToClaim();
        protocolBalance[token] = 0;
        (bool ok,) = treasury.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit ProtocolClaimed(token, treasury, amount);
    }

    receive() external payable {}
}
