// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title CreatorVesting
/// @notice Linear vesting with cliff for creator pre-buy and sniper-tax buybacks.
/// @dev Multiple schedules can be created per (token, beneficiary). Each schedule is independent.
///      Tokens for a schedule must be transferred in atomically before the deposit step.
contract CreatorVesting is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Schedule {
        address token;
        address beneficiary;
        uint256 totalAmount;
        uint256 released;
        uint256 startTime;
        uint64 cliffSeconds;
        uint64 durationSeconds;
        bool exists;
    }

    Schedule[] private _schedules;

    event ScheduleCreated(
        uint256 indexed scheduleId,
        address indexed token,
        address indexed beneficiary,
        uint256 totalAmount,
        uint64 cliffSeconds,
        uint64 durationSeconds
    );
    event Released(uint256 indexed scheduleId, address indexed beneficiary, uint256 amount);
    event ScheduleToppedUp(uint256 indexed scheduleId, uint256 amount, uint256 newTotal);

    error InvalidParams();
    error InvalidSchedule();
    error NothingToRelease();

    /// @notice Create a new vesting schedule. Tokens must already be sitting in this contract
    ///         OR be approved by the caller (transferFrom is invoked).
    /// @param token ERC-20 being vested.
    /// @param beneficiary Recipient.
    /// @param amount Amount to vest.
    /// @param cliffSeconds Time before any tokens unlock.
    /// @param durationSeconds Total time over which tokens vest linearly (>= cliffSeconds).
    function createSchedule(
        address token,
        address beneficiary,
        uint256 amount,
        uint64 cliffSeconds,
        uint64 durationSeconds
    )
        external
        nonReentrant
        returns (uint256 scheduleId)
    {
        if (token == address(0) || beneficiary == address(0) || amount == 0) revert InvalidParams();
        if (durationSeconds < cliffSeconds || durationSeconds == 0) revert InvalidParams();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        scheduleId = _schedules.length;
        _schedules.push(
            Schedule({
                token: token,
                beneficiary: beneficiary,
                totalAmount: amount,
                released: 0,
                startTime: block.timestamp,
                cliffSeconds: cliffSeconds,
                durationSeconds: durationSeconds,
                exists: true
            })
        );

        emit ScheduleCreated(scheduleId, token, beneficiary, amount, cliffSeconds, durationSeconds);
    }

    /// @notice Add more tokens to an existing schedule (used by sniper-tax buybacks accumulating
    ///         into the creator's existing vesting bucket).
    /// @dev Does not change schedule timing — extra tokens vest on the same schedule.
    function topUp(uint256 scheduleId, uint256 amount) external nonReentrant {
        Schedule storage s = _scheduleAt(scheduleId);
        if (amount == 0) revert InvalidParams();
        IERC20(s.token).safeTransferFrom(msg.sender, address(this), amount);
        s.totalAmount += amount;
        emit ScheduleToppedUp(scheduleId, amount, s.totalAmount);
    }

    /// @notice Release any vested-but-unreleased tokens to the beneficiary.
    function release(uint256 scheduleId) external nonReentrant returns (uint256 released) {
        Schedule storage s = _scheduleAt(scheduleId);
        uint256 vested = _vestedAmount(s);
        released = vested - s.released;
        if (released == 0) revert NothingToRelease();
        s.released = vested;
        IERC20(s.token).safeTransfer(s.beneficiary, released);
        emit Released(scheduleId, s.beneficiary, released);
    }

    function vestedAmount(uint256 scheduleId) external view returns (uint256) {
        return _vestedAmount(_scheduleAt(scheduleId));
    }

    function releasable(uint256 scheduleId) external view returns (uint256) {
        Schedule storage s = _scheduleAt(scheduleId);
        return _vestedAmount(s) - s.released;
    }

    function getSchedule(uint256 scheduleId) external view returns (Schedule memory) {
        return _scheduleAt(scheduleId);
    }

    function totalSchedules() external view returns (uint256) {
        return _schedules.length;
    }

    function _scheduleAt(uint256 id) private view returns (Schedule storage s) {
        if (id >= _schedules.length) revert InvalidSchedule();
        s = _schedules[id];
        if (!s.exists) revert InvalidSchedule();
    }

    function _vestedAmount(Schedule storage s) private view returns (uint256) {
        uint256 elapsed = block.timestamp - s.startTime;
        if (elapsed < s.cliffSeconds) return 0;
        if (elapsed >= s.durationSeconds) return s.totalAmount;
        return (s.totalAmount * elapsed) / s.durationSeconds;
    }
}
