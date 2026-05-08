// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract GuessChampion {
    // 2026 FIFA World Cup 共 48 支参赛队，有效编号 1..48
    uint8 public constant TEAM_COUNT = 48;

    // 每笔下注金额必须落在 [MIN_BET, MAX_BET] 区间内
    uint256 public constant MIN_BET = 0.01 ether;
    uint256 public constant MAX_BET = 1 ether;

    // 下注截止：2026-06-11 00:00:00 UTC（世界杯开赛时间）
    uint64 public constant BET_DEADLINE = 1781136000;

    address public immutable owner;

    // each team has a list of bettors
    mapping(uint8 => address[]) public teamBettors;
    // each user can only bet one team
    mapping(address => uint256) public betAmounts;
    // user => teamId
    mapping(address => uint8) public teamOf;
    // total pool amount
    uint256 public totalPool;

    // emergency cancel flag
    bool public cancelled;

    // 开奖状态
    bool public drawn;
    // 冠军 teamId（draw 之前为 0）
    uint8 public champion;
    // push 转账失败时的兜底余额：用户后续可调 claim() 自取
    mapping(address => uint256) public unclaimedPayout;

    event BetPlaced(address indexed user, uint8 indexed teamId, uint256 amount);
    event Cancelled();
    event Refunded(address indexed user, uint256 amount);
    event Drawn(uint8 indexed champion, uint256 winnersTotal, uint256 pool);
    event Paid(address indexed winner, uint256 amount);
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
    error NothingToRefund();
    error NothingToClaim();
    error TransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice 在开赛前对某支队伍下注，金额由 msg.value 决定
    function bet(uint8 teamId) external payable {
        if (cancelled) revert AlreadyCancelled();
        if (block.timestamp >= BET_DEADLINE) revert BettingClosed();
        if (teamId == 0 || teamId > TEAM_COUNT) revert InvalidTeam(teamId);
        if (msg.value < MIN_BET || msg.value > MAX_BET) {
            revert BetOutOfRange(msg.value);
        }

        uint8 existing = teamOf[msg.sender];
        if (existing == 0) {
            // first bet
            teamOf[msg.sender] = teamId;
            teamBettors[teamId].push(msg.sender);
        } else if (existing != teamId) {
            // bet other team
            revert AlreadyBetOnDifferentTeam(existing);
        }

        betAmounts[msg.sender] += msg.value;
        totalPool += msg.value;

        emit BetPlaced(msg.sender, teamId, msg.value);
    }

    /// @notice owner 公布冠军并按比例 push 派发整个奖池
    /// @dev    遍历 teamBettors[winningTeam] 一次累加押注总额，再遍历一次发钱
    ///         push 失败的金额转入 unclaimedPayout，用户事后调 claim() 自取
    /// @param  winning team id
    function draw(uint8 winningTeam) external onlyOwner {
        if (drawn) revert AlreadyDrawn();
        if (cancelled) revert AlreadyCancelled();
        if (block.timestamp < BET_DEADLINE) revert NotDrawable();
        if (winningTeam == 0 || winningTeam > TEAM_COUNT) {
            revert InvalidTeam(winningTeam);
        }

        // lock the draw status
        drawn = true;
        champion = winningTeam;

        address[] storage winners = teamBettors[winningTeam];
        uint256 n = winners.length;

        uint256 pool = totalPool;
        totalPool = 0; // 清空，防止任何隐含状态被滥用

        // 没人押中：奖池兜底转给 owner
        if (n == 0) {
            (bool ok, ) = owner.call{value: pool}("");
            if (!ok) revert TransferFailed();
            emit Drawn(winningTeam, 0, pool);
            return;
        }

        // calculate winner total bet amount
        uint256 winnersTotal;
        for (uint256 i = 0; i < n; ) {
            winnersTotal += betAmounts[winners[i]];
            unchecked {
                i++;
            }
        }

        emit Drawn(winningTeam, winnersTotal, pool);

        // distribute the prize by ratio
        // ⚠ 必须先乘后除：先除会因整数截断丢失精度，导致部分 ETH 锁死合约
        for (uint256 i = 0; i < n; ) {
            address winner = winners[i];
            uint256 stake = betAmounts[winner];
            uint256 payout = (pool * stake) / winnersTotal;
            delete betAmounts[winner];
            delete teamOf[winner];

            // gas 限制 30000：防 gas grief；EOA 充足，复杂合约可走兜底 claim()
            (bool ok, ) = winner.call{value: payout, gas: 30_000}("");
            if (ok) {
                emit Paid(winner, payout);
            } else {
                unclaimedPayout[winner] = payout;
            }
            unchecked {
                i++;
            }
        }

        delete teamBettors[winningTeam];
    }

    /// @notice push 失败的赢家自取奖金
    function claim() external {
        uint256 amount = unclaimedPayout[msg.sender];
        if (amount == 0) revert NothingToClaim();
        delete unclaimedPayout[msg.sender];

        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Claimed(msg.sender, amount);
    }
}
