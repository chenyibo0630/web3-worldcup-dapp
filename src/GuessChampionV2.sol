// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/// @title  GuessChampion v2 — WCT edition
/// @notice Pari-mutuel betting game using WorldCup Token (WCT) instead of ETH.
/// @dev    Does not accept ETH (no payable / receive / fallback).
contract GuessChampionV2 {
    // 2026 FIFA World Cup has 48 teams; valid ids are 1..48.
    uint8 public constant TEAM_COUNT = 48;

    /// @notice keccak256 of data/teams.json — on-chain commitment to the teamId↔country map.
    /// @dev    Recompute via: forge script script/HashTeams.s.sol
    bytes32 public constant TEAMS_HASH =
        0x8ccca76bebb51a66704e72959299c5db802e3a20fc186333c52fee50788fbca9;

    // Per-bet bounds in WCT (18 decimals).
    uint256 public constant MIN_BET = 1 * 10 ** 18;
    uint256 public constant MAX_BET = 100 * 10 ** 18;

    // Betting closes at 2026-06-11 00:00:00 UTC (tournament kickoff).
    uint64 public constant BET_DEADLINE = 1781136000;

    address public immutable owner;

    /// @notice WCT contract reference (bound at deploy, immutable).
    IERC20 public immutable wct;

    // teamId => bettors on that team (appended on first bet, no duplicates).
    mapping(uint8 => address[]) public teamBettors;
    // user => total stake on their chosen team (top-ups accumulate).
    mapping(address => uint256) public betAmounts;
    // user => the single team they bet on; 0 means no bet (sentinel).
    mapping(address => uint8) public teamOf;
    // Total pot (frozen as a snapshot after declareChampion, used as numerator in claim).
    uint256 public totalPool;

    bool public cancelled;

    // Winning teamId; 0 before draw (sentinel for "not drawn").
    uint8 public champion;
    // Sum of stakes on the winning team; the denominator for claim payouts.
    uint256 public winnersTotal;

    event BetPlaced(address indexed user, uint8 indexed teamId, uint256 amount);
    event Cancelled();
    event Refunded(address indexed user, uint256 amount);
    event Drawn(uint8 indexed champion, uint256 winnersTotal, uint256 pool);
    event Claimed(address indexed user, uint256 amount);

    error NotOwner();
    error BettingClosed();
    error InvalidTeam(uint8 teamId);
    error BetOutOfRange(uint256 amount);
    error AlreadyBetOnDifferentTeam(uint8 existingTeam);
    error AlreadyCancelled();
    error NotCancelled();
    error AlreadyDrawn();
    error NotDrawable();
    error NotDrawn();
    error NotWinner();
    error NothingToRefund();
    error NothingToClaim();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(IERC20 _wct) {
        owner = msg.sender;
        wct = _wct;
    }

    // ══════════════════════════════════════════════════════════
    // Betting
    // ══════════════════════════════════════════════════════════

    /// @notice Bet `amount` WCT on `teamId` before kickoff.
    /// @dev    Caller must wct.approve(this, amount) first. One team per user; top-ups allowed.
    function bet(uint8 teamId, uint256 amount) external {
        _bet(msg.sender, teamId, amount);
    }

    /// @notice Combined permit + bet in one tx, saving the separate approve.
    /// @dev    permit() is wrapped in try/catch to defeat front-run-permit DoS:
    ///         if an attacker submits the same signature first, our permit() reverts on nonce
    ///         but the allowance is already set, so transferFrom in _bet still succeeds.
    function betWithPermit(
        uint8 teamId,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        try
            IERC20Permit(address(wct)).permit(
                msg.sender, address(this), amount, deadline, v, r, s
            )
        {} catch {}

        _bet(msg.sender, teamId, amount);
    }

    function _bet(address user, uint8 teamId, uint256 amount) internal {
        if (cancelled) revert AlreadyCancelled();
        if (block.timestamp >= BET_DEADLINE) revert BettingClosed();
        if (teamId == 0 || teamId > TEAM_COUNT) revert InvalidTeam(teamId);
        if (amount < MIN_BET || amount > MAX_BET) revert BetOutOfRange(amount);

        uint8 existing = teamOf[user];
        if (existing == 0) {
            teamOf[user] = teamId;
            teamBettors[teamId].push(user);
        } else if (existing != teamId) {
            revert AlreadyBetOnDifferentTeam(existing);
        }

        // Pull funds first; OZ ERC20 reverts on insufficient allowance/balance,
        // so the whole bet rolls back atomically.
        wct.transferFrom(user, address(this), amount);

        betAmounts[user] += amount;
        totalPool += amount;

        emit BetPlaced(user, teamId, amount);
    }

    // ══════════════════════════════════════════════════════════
    // Emergency cancel / refund (pull)
    // ══════════════════════════════════════════════════════════

    function emergencyCancel() external onlyOwner {
        if (champion != 0) revert AlreadyDrawn();
        if (cancelled) revert AlreadyCancelled();
        cancelled = true;
        emit Cancelled();
    }

    function refund() external {
        _refund(msg.sender);
    }

    function refundFor(address user) external {
        _refund(user);
    }

    function refundForBatch(address[] calldata users) external {
        uint256 len = users.length;
        for (uint256 i; i < len; ) {
            _refund(users[i]);
            unchecked {
                i++;
            }
        }
    }

    function _refund(address user) internal {
        if (!cancelled) revert NotCancelled();

        uint256 amount = betAmounts[user];
        if (amount == 0) revert NothingToRefund();

        // CEI: clear state before external call.
        delete betAmounts[user];
        delete teamOf[user];
        unchecked {
            totalPool -= amount;
        }

        wct.transfer(user, amount);

        emit Refunded(user, amount);
    }

    // ══════════════════════════════════════════════════════════
    // Draw
    // ══════════════════════════════════════════════════════════

    function declareChampion(uint8 winningTeam) external onlyOwner {
        if (champion != 0) revert AlreadyDrawn();
        if (cancelled) revert AlreadyCancelled();
        if (block.timestamp < BET_DEADLINE) revert NotDrawable();
        if (winningTeam == 0 || winningTeam > TEAM_COUNT) {
            revert InvalidTeam(winningTeam);
        }

        address[] storage winners = teamBettors[winningTeam];
        uint256 n = winners.length;

        // No bettors on the winner: auto-cancel so everyone can refund their stake.
        if (n == 0) {
            cancelled = true;
            emit Cancelled();
            return;
        }

        uint256 wt;
        for (uint256 i = 0; i < n; ) {
            wt += betAmounts[winners[i]];
            unchecked {
                i++;
            }
        }

        champion = winningTeam;
        winnersTotal = wt;

        emit Drawn(winningTeam, wt, totalPool);
    }

    // ══════════════════════════════════════════════════════════
    // Claim (pull only)
    // ══════════════════════════════════════════════════════════

    function claim() external {
        _claimFor(msg.sender);
    }

    function claimFor(address user) external {
        _claimFor(user);
    }

    function claimForBatch(address[] calldata users) external {
        uint256 len = users.length;
        for (uint256 i; i < len; ) {
            _claimFor(users[i]);
            unchecked {
                i++;
            }
        }
    }

    function _claimFor(address user) internal {
        if (cancelled) revert AlreadyCancelled();
        if (champion == 0) revert NotDrawn();
        if (teamOf[user] != champion) revert NotWinner();

        uint256 stake = betAmounts[user];
        if (stake == 0) revert NothingToClaim();

        // payout = totalPool * stake / winnersTotal — multiply before divide to avoid truncation.
        uint256 payout = (totalPool * stake) / winnersTotal;

        // CEI: clear state before external call.
        delete betAmounts[user];
        delete teamOf[user];

        wct.transfer(user, payout);

        emit Claimed(user, payout);
    }
}
