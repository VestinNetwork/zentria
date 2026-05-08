// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title LiquidityLocker
/// @notice Locks LP tokens for a fixed duration. Once locked, the LP cannot be withdrawn until unlock time.
/// @dev Each lock is an independent record. The locker contract has no admin function that can release early.
contract LiquidityLocker is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Hard-coded minimum lock duration (6 months).
    uint256 public constant MIN_LOCK_DURATION = 180 days;
    /// @notice Hard-coded maximum lock duration (~99 years).
    uint256 public constant MAX_LOCK_DURATION = 99 * 365 days;

    struct Lock {
        address token;
        address owner;
        uint256 amount;
        uint256 unlockAt;
        bool withdrawn;
    }

    /// @notice All locks ever created. ID is the array index.
    Lock[] private _locks;

    /// @notice Lock IDs owned by each address (for off-chain queries).
    mapping(address user => uint256[] lockIds) public userLocks;

    event LiquidityLocked(
        uint256 indexed lockId,
        address indexed token,
        address indexed owner,
        uint256 amount,
        uint256 unlockAt
    );
    event LiquidityWithdrawn(uint256 indexed lockId, address indexed owner, uint256 amount);
    event LockOwnerTransferred(uint256 indexed lockId, address indexed previousOwner, address indexed newOwner);
    event LockExtended(uint256 indexed lockId, uint256 previousUnlockAt, uint256 newUnlockAt);

    error InvalidDuration();
    error InvalidAmount();
    error InvalidAddress();
    error LockNotFound();
    error NotLockOwner();
    error StillLocked();
    error AlreadyWithdrawn();
    error NewUnlockNotLater();

    /// @notice Lock LP tokens until `block.timestamp + duration`.
    /// @param token LP token address.
    /// @param amount Amount to lock.
    /// @param duration Lock duration in seconds.
    /// @param lockOwner Address that will be allowed to withdraw at unlock time.
    /// @return lockId Newly created lock ID.
    function lock(
        address token,
        uint256 amount,
        uint256 duration,
        address lockOwner
    )
        external
        nonReentrant
        returns (uint256 lockId)
    {
        if (token == address(0) || lockOwner == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (duration < MIN_LOCK_DURATION || duration > MAX_LOCK_DURATION) revert InvalidDuration();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 unlockAt = block.timestamp + duration;
        lockId = _locks.length;
        _locks.push(
            Lock({token: token, owner: lockOwner, amount: amount, unlockAt: unlockAt, withdrawn: false})
        );
        userLocks[lockOwner].push(lockId);

        emit LiquidityLocked(lockId, token, lockOwner, amount, unlockAt);
    }

    /// @notice Withdraw a lock after its unlock time. Only callable by the lock owner.
    function withdraw(uint256 lockId) external nonReentrant {
        if (lockId >= _locks.length) revert LockNotFound();
        Lock storage l = _locks[lockId];
        if (l.owner != msg.sender) revert NotLockOwner();
        if (l.withdrawn) revert AlreadyWithdrawn();
        if (block.timestamp < l.unlockAt) revert StillLocked();

        l.withdrawn = true;
        IERC20(l.token).safeTransfer(msg.sender, l.amount);
        emit LiquidityWithdrawn(lockId, msg.sender, l.amount);
    }

    /// @notice Extend the lock duration. Can only push the unlock time later, never earlier.
    function extendLock(uint256 lockId, uint256 newUnlockAt) external {
        if (lockId >= _locks.length) revert LockNotFound();
        Lock storage l = _locks[lockId];
        if (l.owner != msg.sender) revert NotLockOwner();
        if (l.withdrawn) revert AlreadyWithdrawn();
        if (newUnlockAt <= l.unlockAt) revert NewUnlockNotLater();
        if (newUnlockAt > block.timestamp + MAX_LOCK_DURATION) revert InvalidDuration();

        uint256 previousUnlockAt = l.unlockAt;
        l.unlockAt = newUnlockAt;
        emit LockExtended(lockId, previousUnlockAt, newUnlockAt);
    }

    /// @notice Transfer lock ownership to a new address.
    function transferLockOwner(uint256 lockId, address newOwner) external {
        if (lockId >= _locks.length) revert LockNotFound();
        if (newOwner == address(0)) revert InvalidAddress();
        Lock storage l = _locks[lockId];
        if (l.owner != msg.sender) revert NotLockOwner();
        if (l.withdrawn) revert AlreadyWithdrawn();

        address previous = l.owner;
        l.owner = newOwner;
        userLocks[newOwner].push(lockId);
        emit LockOwnerTransferred(lockId, previous, newOwner);
    }

    function getLock(uint256 lockId) external view returns (Lock memory) {
        if (lockId >= _locks.length) revert LockNotFound();
        return _locks[lockId];
    }

    function totalLocks() external view returns (uint256) {
        return _locks.length;
    }

    function getUserLocks(address user) external view returns (uint256[] memory) {
        return userLocks[user];
    }
}
