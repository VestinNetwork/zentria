// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AntiSniper
/// @notice Stateless library that computes the current sniper-tax basis points
///         based on time elapsed since launch.
/// @dev Linear decay from MAX_SNIPER_BPS (99%) down to MIN_SNIPER_BPS (1%) over `windowSeconds`.
///      After the window expires the function returns 0 (no sniper tax).
library AntiSniper {
    /// @notice Highest sniper tax: 99% of incoming buy.
    uint16 internal constant MAX_SNIPER_BPS = 9900;
    /// @notice Lowest non-zero sniper tax: 1% of incoming buy.
    uint16 internal constant MIN_SNIPER_BPS = 100;
    /// @notice Hard cap on the configurable window: 1 hour.
    uint256 internal constant MAX_WINDOW_SECONDS = 1 hours;

    /// @notice Compute the buy-side sniper tax in bps for a given launch timestamp + window.
    /// @param launchedAt Unix timestamp at which the curve started trading.
    /// @param windowSeconds Configured window for decay; 0 disables sniper tax entirely.
    /// @return bps The sniper tax in basis points (0–9900).
    function currentBuyTaxBps(uint256 launchedAt, uint256 windowSeconds) internal view returns (uint16 bps) {
        if (windowSeconds == 0) return 0;
        if (block.timestamp < launchedAt) return MAX_SNIPER_BPS;
        uint256 elapsed = block.timestamp - launchedAt;
        if (elapsed >= windowSeconds) return 0;
        // Linear decay between MAX_SNIPER_BPS at t=0 and MIN_SNIPER_BPS at t=window.
        // After window ends, returns 0 (free trading).
        uint256 span = uint256(MAX_SNIPER_BPS - MIN_SNIPER_BPS);
        uint256 reduction = (span * elapsed) / windowSeconds;
        return uint16(uint256(MAX_SNIPER_BPS) - reduction);
    }
}
