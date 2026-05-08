# WorldCup Token (WCT) + GuessChampion v2 设计文档

**版本**: v2.0
**日期**: 2026-05-08
**状态**: 已确认设计，待实施

---

## 1. 设计目标

把 GuessChampion 从"用 ETH 真金白银下注"重构为"用游戏代币 WCT 娱乐式下注"，核心目标：

| 目标 | 说明 |
|------|------|
| **零真实金钱风险** | WCT 无内在价值，不可兑换 ETH，纯娱乐积分 |
| **零监管风险** | 不构成博彩——玩家不投入有价物 |
| **零入场门槛** | 任何钱包地址都能参与，不需要持有 ETH（除 gas 外）|
| **学习收益最大化** | ERC20 标准 + 合约间调用 + faucet 模式 + approve/transferFrom 闭环 |
| **保留原结算逻辑** | 比例分配奖池的 pull 模式不变（沉淀的设计成果） |

---

## 2. 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│  WorldCupToken (WCT.sol)                                     │
│  ─────────────────────────────────────────                   │
│  ERC20 标准 + 一次性领取的 faucet                              │
│                                                              │
│  · name = "WorldCup Token", symbol = "WCT", decimals = 18    │
│  · claimWelcome(): 一地址限领一次 100 WCT                      │
│  · 领取窗口：部署 ~ 2026-07-20 00:00 UTC（世界杯结束次日）       │
│  · 总供应量无上限（按需 mint）                                  │
│  · 无 owner、无管理员、不可暂停（治理简洁）                      │
└──────────────────────────────────────────────────────────────┘
                           │
                           │  approve(GuessChampion, amount)
                           │  transferFrom(user → GC) on bet()
                           │  transfer(GC → winner) on claim()
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  GuessChampion.sol (v2)                                      │
│  ─────────────────────────────────────────                   │
│  比例分配下注游戏（旧版逻辑，币种切换为 WCT）                    │
│                                                              │
│  · 构造函数注入 WCT 地址（immutable）                          │
│  · bet(teamId, amount) — 不再 payable，amount 通过参数传入      │
│  · 内部用 wct.transferFrom / wct.transfer 替换 ETH 转账          │
│  · pull 模式 claim/claimFor/claimForBatch 全部保留              │
│  · refund 通道（紧急取消）保留，币种切换为 WCT                   │
│  · TEAMS_HASH 链上承诺机制保留                                 │
└──────────────────────────────────────────────────────────────┘
```

**关键不变量**：

- 单方向资金流：用户 → 合约 → 用户（不存在反向、跨用户走账）
- WCT 是唯一货币：合约不接收 ETH（无 payable 函数、无 receive/fallback）
- 一笔 bet = 一次 transferFrom；一次 claim = 一次 transfer
- 合约里 `wct.balanceOf(address(this))` 应始终 ≥ `totalPool`（不变量）

---

## 3. WorldCupToken 详细设计

### 3.1 时间线

```
[部署]                           [BET_DEADLINE]                     [WC_END]
  │                                  │                                │
  │       ← claimWelcome 开放 →     │       ← claimWelcome 开放 →    │ claimWelcome 关闭
  │       ← bet 开放 →              │       ← bet 关闭 →             │
  │                                  │  ← declareChampion 开放 →    │ ← declareChampion 仍开放 →
  │                                  │  ← claim 在 declareChampion 后开放 →
                                                                       (claim 永久开放)
```

| 事件 | 时间戳 (Unix) | 日期 (UTC) | 含义 |
|------|--------------|-----------|------|
| `BET_DEADLINE` | 1781136000 | 2026-06-11 00:00 | 世界杯开赛，下注窗口关闭 |
| `WC_END` (= `CLAIM_DEADLINE`) | 1784505600 | 2026-07-20 00:00 | 决赛后一日，新用户领币关闭 |

### 3.2 状态变量

```solidity
contract WorldCupToken is ERC20 {
    /// 每个地址首次领取的额度（100 WCT，18 位小数）
    uint256 public constant WELCOME_AMOUNT = 100 * 10**18;

    /// 领取窗口截止：2026-07-20 00:00:00 UTC，世界杯决赛次日
    /// 之后链上谁也没法再领新币（包括所有人，包括从未领过的人）
    uint64 public constant CLAIM_DEADLINE = 1784505600;

    /// 一地址一票：true = 已领过
    /// ⚠ 注意：这个 mapping 不防止用户切换钱包重复领，
    ///        但因 WCT 无真实价值，女巫攻击是设计上接受的代价
    mapping(address => bool) public hasClaimed;
}
```

### 3.3 函数接口

```solidity
/// 任何人调用，向自己 mint 100 WCT；每个地址限领一次
/// @dev 失败 case：
///     - 已领过 → revert AlreadyClaimed
///     - 超过窗口 → revert ClaimWindowClosed
function claimWelcome() external;

/// 标准 ERC20 接口（继承自 OZ）
function transfer(address to, uint256 amount) external returns (bool);
function approve(address spender, uint256 amount) external returns (bool);
function transferFrom(address from, address to, uint256 amount) external returns (bool);
function balanceOf(address account) external view returns (uint256);
function totalSupply() external view returns (uint256);
function allowance(address owner, address spender) external view returns (uint256);
```

### 3.4 自定义错误

```solidity
error AlreadyClaimed();        // hasClaimed[msg.sender] == true
error ClaimWindowClosed();     // block.timestamp >= CLAIM_DEADLINE
```

### 3.5 事件

```solidity
event WelcomeClaimed(address indexed user, uint256 amount);
// 标准 ERC20 事件继承：Transfer / Approval
```

### 3.6 显式拒绝的功能

| 不要的功能 | 理由 |
|-----------|------|
| Owner / Admin | 极简治理，没人能随意 mint/burn 别人的币 |
| Pausable | 没意义——纯游戏，停下来反而扫兴 |
| Burnable | 玩家可以自由 transfer，不需要主动销毁 |
| Mint cap | 总量随玩家数线性增长，无需上限 |
| ETH faucet | 只送 WCT，gas 费仍由玩家自付（保留与真实链交互的体感）|

---

## 4. GuessChampion v2 改造点

### 4.1 状态变量改动

```solidity
contract GuessChampion {
    // 新增：注入的 WCT 合约引用
    IERC20 public immutable wct;

    // 改：金额单位从 wei 改为 WCT (18 decimals)
    uint256 public constant MIN_BET = 1 * 10**18;     // 1 WCT
    uint256 public constant MAX_BET = 100 * 10**18;   // 100 WCT（= 一次领取额度）

    // 不变：BET_DEADLINE / TEAM_COUNT / TEAMS_HASH / 状态映射 / champion / cancelled / ...
}
```

### 4.2 构造函数改动

```solidity
constructor(IERC20 _wct) {
    owner = msg.sender;
    wct = _wct;            // 部署时绑定 WCT 地址，永久不变
}
```

### 4.3 `bet` 函数改动

```solidity
// 旧
function bet(uint8 teamId) external payable {
    if (msg.value < MIN_BET || msg.value > MAX_BET) revert BetOutOfRange(msg.value);
    // ...
    betAmounts[msg.sender] += msg.value;
    totalPool += msg.value;
}

// 新
function bet(uint8 teamId, uint256 amount) external {
    if (amount < MIN_BET || amount > MAX_BET) revert BetOutOfRange(amount);
    // ... 校验和登记 bettors 列表（与旧版完全一致）

    // 关键：拉币入池（用户必须先 approve(this, amount)）
    wct.transferFrom(msg.sender, address(this), amount);

    betAmounts[msg.sender] += amount;
    totalPool += amount;
    emit BetPlaced(msg.sender, teamId, amount);
}
```

### 4.4 `_claimFor` / `_refund` 内部函数改动

```solidity
// 旧（ETH 转账）
(bool ok, ) = user.call{value: payout}("");
if (!ok) revert TransferFailed();

// 新（WCT 转账）
wct.transfer(user, payout);
// 注：OZ 的 ERC20.transfer 失败时会 revert，不返回 false，
//    所以无需检查返回值（或可用 SafeERC20.safeTransfer 兜底兼容非标 token）
```

### 4.5 移除的内容

```solidity
// ❌ 删除整个 receive() / fallback() 函数（如果存在）
// ❌ 删除 declareChampion 中"无人押中转 owner"那段 ETH 兜底逻辑
//    → 已改为"自动 cancelled，所有人走 refund"，保持设计一致
```

### 4.6 安全考虑

#### 重入风险
- ERC20 标准 `transfer` 不应该回调（OZ 的实现保证了这一点）
- 但若 WCT 升级为 ERC777 / 钩子 token，回调可能发生
- **缓解**：保持 CEI 顺序（先清状态，后外部调用），不需要 ReentrancyGuard
- **本项目**：WCT 是我们自己实现的纯 ERC20，无回调，无风险

#### approve 攻击向量
- 用户必须先 `approve(GC, amount)` 才能 bet
- 经典风险：approve 后被前置交易抢先（front-running）
- **缓解**：本场景无前置攻击意义（不存在套利空间）
- **建议**：前端用 `approve(GC, MAX_UINT256)` 一次授权 + UI 上显式提示用户

#### 余额一致性
- 不变量：`wct.balanceOf(address(this)) >= totalPool`
- 在 declareChampion 后：`wct.balanceOf(this) >= 累计未 claim 的 winner 应得`
- 测试中应验证此不变量

---

## 5. 完整生命周期状态机

```
                          ┌────────────────────────┐
                          │   Initial (Deploy)     │
                          │   cancelled = false    │
                          │   champion = 0         │
                          └────────┬───────────────┘
                                   │
                    bet(teamId, amount) [block.timestamp < BET_DEADLINE]
                                   │
                                   ▼
                          ┌────────────────────────┐
                          │   Open Betting         │
                          │   accepts bet()        │
                          └────────┬───────────────┘
                                   │
                ┌──────────────────┼──────────────────┐
                │                  │                  │
       emergencyCancel()    block.timestamp >=        │
       [owner]              BET_DEADLINE              │
                │           AND owner triggers        │
                │           declareChampion()         │
                ▼                  │                  │
       ┌────────────────┐          ▼                  │
       │   Cancelled    │ ┌────────────────────────┐  │
       │ (refund only)  │ │  Settled               │  │
       └────────────────┘ │  champion ∈ [1, 48]    │  │
                          │  winnersTotal locked   │  │
                          │  accepts claim()       │  │
                          │                         │  │
                          │  注：若冠军队无人押注，   │  │
                          │      auto-transition   │  │
                          │      → Cancelled       │  │
                          └────────────────────────┘  │
                                                      │
                                  (no end state — claim 永久开放)
```

**说明**:
- `Cancelled` 状态：任何人能调 `refund()` / `refundFor()` / `refundForBatch()` 取回原 WCT
- `Settled` 状态：冠军队下注者能调 `claim()` / `claimFor()` / `claimForBatch()` 按比例取奖
- 两个状态互斥；进入任一终态后都不可逆

---

## 6. 端到端用户流程

### 6.1 新用户首次玩

```
1. 用户连接钱包到本地 anvil / sepolia
2. 用户调 WCT.claimWelcome()
   → 收到 100 WCT
3. 用户调 WCT.approve(GuessChampion, 50 WCT)  // 授权 50 个的额度
   → Approval 事件
4. 用户调 GuessChampion.bet(3, 50e18)  // 押 3 号队（Côte d'Ivoire）50 WCT
   → 50 WCT 从用户转到合约
   → BetPlaced 事件
5. ... 等待 BET_DEADLINE
6. owner 调 GuessChampion.declareChampion(3)
   → 假设 3 号队真的赢了
7. 用户调 GuessChampion.claim()
   → 按比例收到 WCT 奖金
```

### 6.2 失败用户（押错队）

```
1-4. 同上，但用户押的是 5 号队
5-6. owner 公布冠军是 3 号队
7. 用户调 claim() → revert NotWinner（在 _claimFor 里）
   或用户调 refund() → revert NotCancelled（合约未取消）
8. 用户的 50 WCT 留在奖池里，作为支付给赢家的奖金
   （WCT 无价值，用户体感是"游戏失败，重新领币再来"）
9. 用户切换钱包（或本钱包 hasClaimed=true 不能再领）
```

### 6.3 紧急取消场景

```
1-4. 多用户已下注
5. 比赛被取消 / FIFA 出现重大事件 / 智能合约发现 bug
6. owner 调 emergencyCancel()
7. 所有下注用户走 refund() 取回原 WCT 本金
   （不分赢家输家，按 betAmounts 1:1 退还）
```

---

## 7. 部署顺序

```
1. forge build                           # 验证 OZ remapping 工作
2. forge test                            # 全部既有测试 + 新测试通过
3. anvil                                 # 启动本地链
4. forge script DeployWorldCupToken.s.sol --broadcast
   → 拿到 WCT 地址
5. forge script DeployGuessChampion.s.sol --sig "run(address)" <WCT_addr> --broadcast
   → GuessChampion 在构造时绑定 WCT 地址
6. cast 验证（见 §10）
```

或一次性部署脚本 `DeployAll.s.sol`：

```solidity
function run() external {
    vm.startBroadcast();
    WorldCupToken wct = new WorldCupToken();
    GuessChampion gc  = new GuessChampion(IERC20(address(wct)));
    vm.stopBroadcast();

    console.log("WCT:", address(wct));
    console.log("GC:",  address(gc));
}
```

---

## 8. 测试场景清单

### 8.1 WorldCupToken

| 测试用例 | 期望 |
|---------|------|
| `test_WCT_constants` | name/symbol/decimals/WELCOME_AMOUNT/CLAIM_DEADLINE 正确 |
| `test_WCT_firstClaimMints100` | claimWelcome → balanceOf == 100e18, hasClaimed == true |
| `test_WCT_secondClaimReverts` | 同地址再调 claimWelcome → revert AlreadyClaimed |
| `test_WCT_claimAfterDeadlineReverts` | warp 到 CLAIM_DEADLINE 后调 → revert ClaimWindowClosed |
| `test_WCT_claimRightBeforeDeadline` | warp 到 CLAIM_DEADLINE - 1 仍能领 |
| `test_WCT_transferStandard` | 标准 ERC20 transfer 正常 |
| `test_WCT_approveAndTransferFrom` | approve + transferFrom 闭环 |
| `test_WCT_event_WelcomeClaimed` | 事件参数正确 |

### 8.2 GuessChampion v2

继承 v1 的所有测试，金额单位改为 WCT。新增/修改：

| 测试用例 | 期望 |
|---------|------|
| `test_bet_requiresApproval` | 没 approve 直接 bet → revert（OZ ERC20 的 ERC20InsufficientAllowance） |
| `test_bet_requiresBalance` | 没 100 WCT 押 50 WCT → revert（ERC20InsufficientBalance） |
| `test_bet_pullsTokensIntoContract` | bet 后 wct.balanceOf(GC) 增加正确数量 |
| `test_bet_doesNotAcceptETH` | 直接 send ETH 到合约 → revert（无 receive/fallback）|
| `test_claim_transfersTokens` | claim 后用户 WCT 余额增加正确比例的 payout |
| `test_refund_transfersTokens` | refund 后用户 WCT 余额回到下注前 |
| `test_balanceInvariant` | 任何状态：wct.balanceOf(GC) == sum(betAmounts) for active users |
| `test_TeamsHash_matchesJsonFile` | 保留（不变） |

---

## 9. 文件改动清单

| 文件 | 动作 | 行数估计 |
|------|------|---------|
| `src/WorldCupToken.sol` | 新建 | ~50 |
| `src/GuessChampion.sol` | 改造（去 payable + 注入 WCT + transfer 替换 call） | -10 / +20 |
| `script/DeployWorldCupToken.s.sol` | 新建 | ~40 |
| `script/DeployGuessChampion.s.sol` | 改（接收 WCT 地址参数） | -2 / +10 |
| `script/DeployAll.s.sol` | 新建（可选，一次部全部） | ~50 |
| `test/WorldCupToken.t.sol` | 新建 | ~150 |
| `test/GuessChampion.t.sol` | 大改（金额单位 + setUp 部署 WCT + approve） | -50 / +80 |
| `docs/LOCAL_E2E_TEST.md` | 改（cast 流程加 claimWelcome + approve 步骤） | +30 |
| `docs/DESIGN_WCT.md` | 本文件，新建 | - |

---

## 10. 本地端到端 cast 命令（更新后）

```powershell
# 1. 用户领币
cast send $WCT "claimWelcome()" --rpc-url $RPC --private-key $ALICE_PK

# 2. 用户授权 GC
cast send $WCT "approve(address,uint256)" $GC 100000000000000000000 `
  --rpc-url $RPC --private-key $ALICE_PK

# 3. 下注（注意 amount 参数）
cast send $GC "bet(uint8,uint256)" 3 50000000000000000000 `
  --rpc-url $RPC --private-key $ALICE_PK

# 4. 查 WCT 余额（应该剩 50）
cast call $WCT "balanceOf(address)(uint256)" $ALICE --rpc-url $RPC

# 5. ... 时间穿越 + 开奖（不变）

# 6. 领奖（无 value 参数）
cast send $GC "claim()" --rpc-url $RPC --private-key $ALICE_PK

# 7. 查 WCT 余额（应增加）
cast call $WCT "balanceOf(address)(uint256)" $ALICE --rpc-url $RPC
```

完整流程详见 `docs/LOCAL_E2E_TEST.md`。

---

## 11. 待决问题（实施时再确认）

- [ ] 是否需要 `claimForBatch` for `claimWelcome`？（让 keeper 替一组用户领）
  → 暂不做，第一版保持简单
- [ ] DeployAll 还是分两个部署脚本？
  → 提供两个：单独的 + DeployAll，灵活性最大
- [ ] 前端是否同步改造？
  → 本次仅改合约层，前端待 wagmi 接入时一并改

---

## 12. 设计权衡总结

| 选择 | 备选 | 选择理由 |
|------|------|---------|
| WCT 替代 ETH | ETH+WCT 双币 | 复杂度对学习收益不划算；娱乐场景 ETH 多余 |
| 一地址一次领取 | 无限次 / 每日 | 用户简洁体验 + 轻度反女巫（虽然女巫无所谓）|
| 领取窗口截止于 WC 结束 | 永久开放 | 给项目"完结"的仪式感；防止合约被遗弃后无意义 mint |
| 100 WCT/次 | 50 / 1000 | 与 MAX_BET 对齐：一次领取的额度恰好是单笔最大下注 |
| 接受女巫攻击 | 引入 PoH/KYC/ETH 抵押 | WCT 无价值，攻击无收益 |
| 不引入 owner mint | owner 可铸 / 紧急增发 | 极简治理，避免合约被中心化质疑 |

---

## 附录 A. 关键时间戳速查

```
1781136000  =  2026-06-11 00:00:00 UTC  (BET_DEADLINE)
1784505600  =  2026-07-20 00:00:00 UTC  (CLAIM_DEADLINE / WC_END)
```

## 附录 B. 单位换算速查

```
1 WCT     = 10^18  wei-WCT  (18 decimals)
100 WCT   = 100e18 = 100000000000000000000
MIN_BET   = 1   WCT  = 1e18
MAX_BET   = 100 WCT  = 100e18
WELCOME   = 100 WCT  = 100e18
```

## 附录 C. 参考实现

- OpenZeppelin ERC20: `lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol`
- OpenZeppelin SafeERC20（可选）: `lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol`
- OZ Wizard 在线生成器: https://wizard.openzeppelin.com
