// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @title ZentriaToken
/// @notice Plain ERC-20 used by the v2 launchpad. 1B fixed supply, no transfer hooks,
///         no owner — fully fair-launch safe. All tax/fee logic lives in the bonding curve.
/// @dev Burnable so anyone can self-burn; no privileged minter exists after construction.
contract ZentriaToken is ERC20, ERC20Burnable {
    /// @notice Fixed total supply: 1,000,000,000 with 18 decimals.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 1e18;

    /// @notice Address that received the entire initial supply (the bonding curve).
    address public immutable initialRecipient;

    error InvalidRecipient();

    constructor(string memory name_, string memory symbol_, address recipient_) ERC20(name_, symbol_) {
        if (recipient_ == address(0)) revert InvalidRecipient();
        initialRecipient = recipient_;
        _mint(recipient_, TOTAL_SUPPLY);
    }
}
