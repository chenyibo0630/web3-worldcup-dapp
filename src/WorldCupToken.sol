// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title  WorldCup Token (WCT)
/// @notice Entertainment-only ERC20. Each address can claim 100 WCT once.
/// @dev    No owner, not pausable, not burnable, not redeemable for ETH.
///         Inherits ERC20Permit (EIP-2612) for gasless approvals.
contract WorldCupToken is ERC20, ERC20Permit {
    uint256 public constant WELCOME_AMOUNT = 100 * 10 ** 18;

    /// @notice Claim window ends 2026-07-20 00:00:00 UTC (day after the final).
    uint64 public constant CLAIM_DEADLINE = 1784505600;

    /// @notice One claim per address.
    mapping(address => bool) public hasClaimed;

    event WelcomeClaimed(address indexed user, uint256 amount);

    error AlreadyClaimed();
    error ClaimWindowClosed();

    /// @dev EIP-712 domain.name must equal "WorldCup Token" on the frontend.
    constructor() ERC20("WorldCup Token", "WCT") ERC20Permit("WorldCup Token") {}

    /// @notice Mint 100 WCT to caller. Once per address, before the deadline.
    function claimWelcome() external {
        if (block.timestamp >= CLAIM_DEADLINE) revert ClaimWindowClosed();
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();

        hasClaimed[msg.sender] = true;
        _mint(msg.sender, WELCOME_AMOUNT);

        emit WelcomeClaimed(msg.sender, WELCOME_AMOUNT);
    }
}
