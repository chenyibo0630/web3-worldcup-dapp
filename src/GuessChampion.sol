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

    // teamId => 押该队的用户列表（首次下注时追加，无重复）
    mapping(uint8 => address[]) public teamBettors;
    // user => 该用户对其押注队伍的累计下注（同队加注会累加）
    mapping(address => uint256) public betAmounts;
    // user => 该用户唯一押注的队伍编号；0 = 尚未下注（哨兵值）
    mapping(address => uint8) public teamOf;
    // 整个奖池（declareChampion 后保持为快照，供 claim 用作分子）
    uint256 public totalPool;

    // 紧急取消标志（保留给后续 emergencyCancel/refund 用）
    bool public cancelled;

    // 冠军 teamId（开奖前为 0，作为"已开奖"哨兵值）
    uint8 public champion;
    // 冠军队累计下注总额，由 declareChampion 一次算好作为 claim 的分母
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
    error TransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    // ══════════════════════════════════════════════════════════
    // 下注阶段
    // ══════════════════════════════════════════════════════════

    /// @notice 在开赛前对某支队伍下注，金额由 msg.value 决定
    /// @dev    强制约束：每个用户只能押注一支队伍，可对同队加注
    function bet(uint8 teamId) external payable {
        if (cancelled) revert AlreadyCancelled();
        if (block.timestamp >= BET_DEADLINE) revert BettingClosed();
        if (teamId == 0 || teamId > TEAM_COUNT) revert InvalidTeam(teamId);
        if (msg.value < MIN_BET || msg.value > MAX_BET) {
            revert BetOutOfRange(msg.value);
        }

        uint8 existing = teamOf[msg.sender];
        if (existing == 0) {
            // 首次下注：登记 + 加入 bettors 列表（只此一次）
            teamOf[msg.sender] = teamId;
            teamBettors[teamId].push(msg.sender);
        } else if (existing != teamId) {
            // 想押别的队 → 拒绝
            revert AlreadyBetOnDifferentTeam(existing);
        }
        // existing == teamId：同队加注，不动 teamBettors

        betAmounts[msg.sender] += msg.value;
        totalPool += msg.value;

        emit BetPlaced(msg.sender, teamId, msg.value);
    }

    // ══════════════════════════════════════════════════════════
    // 紧急停摆 / 退款（pull 模式）
    // ══════════════════════════════════════════════════════════

    /// @notice owner 紧急停摆合约：之后 bet/declareChampion 关闭，refund 开放
    /// @dev    一旦取消不可逆；只能在 declareChampion 之前触发
    function emergencyCancel() external onlyOwner {
        if (champion != 0) revert AlreadyDrawn();
        if (cancelled) revert AlreadyCancelled();
        cancelled = true;
        emit Cancelled();
    }

    /// @notice 自取本金（紧急取消后开放）
    function refund() external {
        _refund(msg.sender);
    }

    /// @notice 任何人代某 user 触发退款，钱仍转给 user 本人
    /// @dev    Keeper 可批量代退；代退者承担 gas，但拿不到别人的钱
    function refundFor(address user) external {
        _refund(user);
    }

    /// @notice 批量代退，摊销 21K tx 基础 gas
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

        // CEI: 先清状态再外部调用
        delete betAmounts[user];
        delete teamOf[user];
        // 不变量：amount ≤ totalPool（每笔下注都同时累加两者）
        unchecked {
            totalPool -= amount;
        }

        (bool ok, ) = user.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Refunded(user, amount);
    }

    // ══════════════════════════════════════════════════════════
    // 开奖阶段
    // ══════════════════════════════════════════════════════════

    /// @notice owner 公布冠军并锁定结算参数
    /// @dev    纯 pull 模式：仅遍历一次冠军队 bettors 计算分母 winnersTotal
    ///         不主动派钱，winners 后续各自调 claim() 或由 Keeper 调 claimFor()
    /// @param  winningTeam 冠军队伍编号 1..TEAM_COUNT
    function declareChampion(uint8 winningTeam) external onlyOwner {
        if (champion != 0) revert AlreadyDrawn();
        if (cancelled) revert AlreadyCancelled();
        if (block.timestamp < BET_DEADLINE) revert NotDrawable();
        if (winningTeam == 0 || winningTeam > TEAM_COUNT) {
            revert InvalidTeam(winningTeam);
        }

        address[] storage winners = teamBettors[winningTeam];
        uint256 n = winners.length;

        // 没人押中：自动转入"已取消"状态，所有下注人走 refund 通道按本金退款
        if (n == 0) {
            cancelled = true;
            emit Cancelled();
            return;
        }

        // 唯一一次 O(n) 累加：算冠军队总押注作为后续 claim 的分母
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
    // 领奖阶段（纯 pull）
    // ══════════════════════════════════════════════════════════

    /// @notice 自取奖金
    function claim() external {
        _claimFor(msg.sender);
    }

    /// @notice 任何人代某 user 触发领奖，钱仍转给 user 本人
    /// @dev    Keeper / 运营机器人扫描事件后批量代领，用户体感"自动到账"
    ///         代领者承担 gas，但拿不到别人的钱（call value 目标固定是 user）
    function claimFor(address user) external {
        _claimFor(user);
    }

    /// @notice 批量代领，摊销 21K tx 基础 gas
    /// @dev    一笔 tx 处理 N 个用户；任一用户失败会整笔 revert，建议 N < 50
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
        if (cancelled) revert AlreadyCancelled(); // 应走 refund 通道
        if (champion == 0) revert NotDrawn();
        if (teamOf[user] != champion) revert NotWinner();

        uint256 stake = betAmounts[user];
        if (stake == 0) revert NothingToClaim(); // 已领过或从未下注

        // 比例派奖：payout = totalPool * stake / winnersTotal
        // ⚠ 必须先乘后除，先除会因整数截断丢失精度
        uint256 payout = (totalPool * stake) / winnersTotal;

        // CEI: 先清状态再外部调用，防重入和重复领取
        delete betAmounts[user];
        delete teamOf[user];

        (bool ok, ) = user.call{value: payout}("");
        if (!ok) revert TransferFailed();

        emit Claimed(user, payout);
    }
}
