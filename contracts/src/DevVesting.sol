// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title DevVesting
/// @notice Linear vesting with cliff for the dev's allocation. Anti-dump primitive.
/// @dev Each vesting schedule is bound to a (token, beneficiary) pair. Once created it
///      cannot be revoked or accelerated — guarantees the dev cannot dump early.
contract DevVesting is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Hard-coded cliff (30 days).
    uint256 public constant CLIFF_DURATION = 30 days;
    /// @notice Hard-coded linear release duration (6 months after cliff).
    uint256 public constant VESTING_DURATION = 180 days;

    struct Schedule {
        address token;
        address beneficiary;
        uint256 totalAmount;
        uint256 released;
        uint64 startAt;
    }

    Schedule[] private _schedules;

    /// @notice Schedule IDs per beneficiary (for off-chain queries).
    mapping(address user => uint256[] scheduleIds) public userSchedules;

    event VestingCreated(
        uint256 indexed scheduleId,
        address indexed token,
        address indexed beneficiary,
        uint256 totalAmount,
        uint64 startAt
    );
    event VestingReleased(uint256 indexed scheduleId, address indexed beneficiary, uint256 amount);

    error InvalidAmount();
    error InvalidAddress();
    error ScheduleNotFound();
    error NotBeneficiary();
    error NothingToRelease();

    /// @notice Create a new vesting schedule. Tokens must be approved/transferred by the caller (typically the launchpad).
    /// @param token Token to vest.
    /// @param beneficiary Address that can release tokens after the cliff.
    /// @param totalAmount Total tokens vested.
    /// @return scheduleId Newly created schedule ID.
    function createVesting(
        address token,
        address beneficiary,
        uint256 totalAmount
    )
        external
        nonReentrant
        returns (uint256 scheduleId)
    {
        if (token == address(0) || beneficiary == address(0)) revert InvalidAddress();
        if (totalAmount == 0) revert InvalidAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);

        scheduleId = _schedules.length;
        _schedules.push(
            Schedule({
                token: token,
                beneficiary: beneficiary,
                totalAmount: totalAmount,
                released: 0,
                startAt: uint64(block.timestamp)
            })
        );
        userSchedules[beneficiary].push(scheduleId);

        emit VestingCreated(scheduleId, token, beneficiary, totalAmount, uint64(block.timestamp));
    }

    /// @notice Release vested tokens for a schedule. Only callable by the beneficiary.
    function release(uint256 scheduleId) external nonReentrant {
        if (scheduleId >= _schedules.length) revert ScheduleNotFound();
        Schedule storage s = _schedules[scheduleId];
        if (s.beneficiary != msg.sender) revert NotBeneficiary();

        uint256 releasable = _releasable(s);
        if (releasable == 0) revert NothingToRelease();

        s.released += releasable;
        IERC20(s.token).safeTransfer(msg.sender, releasable);
        emit VestingReleased(scheduleId, msg.sender, releasable);
    }

    /// @notice View the currently releasable amount for a schedule.
    function releasable(uint256 scheduleId) external view returns (uint256) {
        if (scheduleId >= _schedules.length) revert ScheduleNotFound();
        return _releasable(_schedules[scheduleId]);
    }

    /// @notice View the total vested-so-far amount for a schedule (released + claimable).
    function vestedAmount(uint256 scheduleId) external view returns (uint256) {
        if (scheduleId >= _schedules.length) revert ScheduleNotFound();
        return _vestedAmount(_schedules[scheduleId]);
    }

    function getSchedule(uint256 scheduleId) external view returns (Schedule memory) {
        if (scheduleId >= _schedules.length) revert ScheduleNotFound();
        return _schedules[scheduleId];
    }

    function totalSchedules() external view returns (uint256) {
        return _schedules.length;
    }

    function getUserSchedules(address user) external view returns (uint256[] memory) {
        return userSchedules[user];
    }

    function _releasable(Schedule storage s) private view returns (uint256) {
        return _vestedAmount(s) - s.released;
    }

    function _vestedAmount(Schedule storage s) private view returns (uint256) {
        uint256 cliffEnd = s.startAt + CLIFF_DURATION;
        if (block.timestamp < cliffEnd) {
            return 0;
        }
        uint256 vestingEnd = cliffEnd + VESTING_DURATION;
        if (block.timestamp >= vestingEnd) {
            return s.totalAmount;
        }
        uint256 elapsed = block.timestamp - cliffEnd;
        return (s.totalAmount * elapsed) / VESTING_DURATION;
    }
}
