# worldcup-dapp — 2026 世界杯猜冠军 DApp

一个用来学习 **Solidity + ERC20 + Foundry + viem/wagmi** 全栈 Web3 的练手项目。
玩法：用户先领游戏代币 WCT → 开赛前用 WCT 押冠军 → 决赛后 owner 公布冠军 → 押中的人按比例瓜分整个奖池。

```
[claimWelcome]  ─→  [用户钱包: 100 WCT]
                          │
                          │ approve(GC, amount)  ──或── permit 签名（链下、零 gas）
                          ▼
                  [GuessChampionV2 合约]  ──派奖──►  [赢家钱包]
                          ▲
                       owner declareChampion
```

> **设计转向**：v1 用 ETH 直接下注（仍保留在 `src/GuessChampion.sol`，作历史对照）；
> **v2** 改为 ERC20 游戏代币 WCT，零真实金钱风险、零监管摩擦、零入场门槛。
> 完整动机与权衡见 [`docs/DESIGN_WCT.md`](docs/DESIGN_WCT.md)。

---

## 仓库结构

```
worldcup-dapp/
├── src/                       Solidity 合约
│   ├── WorldCupToken.sol      ← WCT：ERC20 + ERC20Permit，纯娱乐积分
│   ├── GuessChampionV2.sol    ← 主合约（WCT 版）
│   └── GuessChampion.sol      ← v1（ETH 版，保留作对照）
├── test/
│   ├── WorldCupToken.t.sol
│   ├── GuessChampionV2.t.sol
│   └── GuessChampion.t.sol    ← v1 的 41 个测试
├── script/
│   ├── DeployAll.s.sol               ← 一次部 WCT + GC v2
│   ├── DeployWorldCupToken.s.sol
│   ├── DeployGuessChampionV2.s.sol
│   ├── DeployGuessChampion.s.sol     ← v1 部署
│   └── HashTeams.s.sol               ← 重新计算 TEAMS_HASH
├── frontend/                  Vite + React + TS + wagmi（v1 接线，待迁 v2）
├── data/teams.json            ← 队伍数据真相源（被合约 hash 锚定）
├── docs/
│   ├── DESIGN_WCT.md          ← v2 设计文档（含权衡 / 状态机 / 测试矩阵）
│   └── LOCAL_E2E_TEST.md      ← 手测命令手册
├── lib/openzeppelin-contracts ← OZ ERC20 / Permit 实现
├── remappings.txt
├── foundry.toml
└── README.md
```

---

## 合约设计 — v2 (WCT)

### 核心架构

```
┌─────────────────────────────────────────────┐
│ WorldCupToken (WCT)                         │
│   ERC20 + ERC20Permit (EIP-2612)            │
│   · claimWelcome()  → 一地址限领一次 100 WCT │
│   · 领取窗口：~ 2026-07-20 UTC              │
│   · 无 owner、不可暂停、不可销毁              │
└──────────────────┬──────────────────────────┘
                   │ approve / permit
                   │ transferFrom / transfer
                   ▼
┌─────────────────────────────────────────────┐
│ GuessChampionV2                              │
│   按比例分配的下注游戏（pull 派奖）            │
│   · bet(teamId, amount)        ← 标准路径     │
│   · betWithPermit(...)         ← 一笔搞定     │
│   · 不接收 ETH（无 payable / receive）       │
└──────────────────────────────────────────────┘
```

### 状态机

```
                cancelled=false, champion=0
                允许 bet / betWithPermit
                    │
            ┌───────┴───────┐
   emergencyCancel       declareChampion
   (owner)               (owner, ≥ BET_DEADLINE)
            │                   │
            ▼                   ▼
    cancelled=true        champion=N (1..48)
    refund 通道开放        claim 通道开放

特殊路径：declareChampion 选了无人押的队
       → 自动转到 cancelled=true
       → 所有人按 refund 拿回本金
```

| 状态 | `cancelled` | `champion` | 谁能操作 |
|---|---|---|---|
| 下注期 | false | 0 | `bet` / `betWithPermit` |
| 紧急 / 自动取消 | **true** | 0 | `refund` / `refundFor` / `refundForBatch` |
| 已开奖 | false | **N≠0** | `claim` / `claimFor` / `claimForBatch` |

### 关键设计点

1. **WCT 代替 ETH**
   合约持币入池靠 `wct.transferFrom`，派奖/退款靠 `wct.transfer`。OZ ERC20 失败时自动 revert，无需手写返回值检查。

2. **EIP-2612 Permit：一笔交易完成下注**
   `betWithPermit(teamId, amount, deadline, v, r, s)`：用户在前端用钱包**链下签名**（不上链、不花 gas），合约先调 `wct.permit` 把签名兑现成 allowance，再走标准 `_bet`。
   *安全细节*：permit 调用包在 try/catch 里防"抢跑代提交 permit"DoS——攻击者抢先用同一签名让 nonce 失效后，allowance 已经生效，本笔仍能成功下注。

3. **Pull 模式**
   合约不主动派钱，每个赢家自己（或 Keeper 代）调 `claim()`。避免单 tx push N 用户的 DoS。

4. **每人押一队**
   `mapping(address => uint8) teamOf` 强制约束。首次下注登记 + push 进 `teamBettors`，加注不重复 push。

5. **金额范围**
   `MIN_BET = 1 WCT`、`MAX_BET = 100 WCT`（恰好一次领取额度），避免微尘攻击 / 巨鲸操纵。

6. **CEI 反重入**
   所有 state-changing 函数严格 `Checks → Effects → Interactions`。`delete betAmounts/teamOf` 在外部 `transfer` 之前；重入再来时 `stake = 0` 直接 revert。

7. **派奖公式**
   ```
   payout = totalPool × stake / winnersTotal      // 必须先乘后除，否则整数截断丢精度
   ```
   `totalPool` 在 declareChampion 后保持快照（不递减），作为分子常量。

8. **代领 / 批量代领**
   `claimFor` / `refundFor` / `claimForBatch` / `refundForBatch`：任何人能为某 user 触发，钱**固定**转给 user 本人（不是调用者）。Keeper 可批量代付 gas，模拟"自动到账"。

9. **TEAMS_HASH 链上承诺**
   合约存 `keccak256(data/teams.json 原始字节)` 作为 teamId↔国家映射的指纹。`forge script HashTeams.s.sol` 可重算，`DeployAll.s.sol` 部署前会自检防漂移。

10. **资金不变量**
    `wct.balanceOf(GC) ≥ totalPool`（在所有合法分支都成立）。

### 核心接口（v2）

```solidity
// WorldCupToken
function claimWelcome() external;
function permit(address owner, address spender, uint256 value,
                uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
// + 标准 ERC20 接口

// GuessChampionV2 — 用户
function bet(uint8 teamId, uint256 amount) external;
function betWithPermit(uint8 teamId, uint256 amount,
                       uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
function claim() external;
function refund() external;

// owner
function emergencyCancel() external;
function declareChampion(uint8 winningTeam) external;

// Keeper / 任意人代触发
function claimFor(address user) external;
function refundFor(address user) external;
function claimForBatch(address[] calldata users) external;
function refundForBatch(address[] calldata users) external;

// 公开 view
function totalPool() external view returns (uint256);
function champion() external view returns (uint8);
function cancelled() external view returns (bool);
function winnersTotal() external view returns (uint256);
function betAmounts(address user) external view returns (uint256);
function teamOf(address user) external view returns (uint8);
function wct() external view returns (IERC20);
```

### 已知设计取舍

| 项 | 现状 | 生产级建议 |
|---|---|---|
| owner 决定冠军 | 中心化 | 接 Chainlink Sports Data 或 UMA Optimistic Oracle |
| owner 误判后不可撤销 | 不可逆 | 加 timelock + 多签 |
| 女巫攻击（多钱包重复领 100 WCT）| 接受 | WCT 无真实价值，攻击无收益 |
| dust（精度残留）锁在合约 | wei 级，可忽略 | 加 `sweep()` 由 owner 回收 |
| 输家的 `betAmounts/teamOf` 永久残留 | 灰尘，无影响 | 不必清 |
| 大规模 N → declareChampion 单循环求和 | N=10000 安全 | N>14k 接近 block gas 上限，需分页 |
| 前端尚未迁 v2 | 仍是 v1 ETH 接线 | 待办（见 §前端） |

---

## 前端工作原理

> ⚠️ 当前 `frontend/` 仍接的是 **v1（ETH 版）**。迁到 v2 需要：
> ① ABI 切到 `GuessChampionV2` + `WorldCupToken` ②
> 加 claimWelcome / approve / 或用 viem `signTypedData` 走 permit 路径。
> 见 §迁移 v2 前端待办。

### 架构

```
[Browser]
   ↓
[React App]  ← Vite dev server
   ↓
[wagmi hooks]  ── useReadContract / useWriteContract / useAccount
   ↓
[viem]  ── transport (HTTP RPC) + ABI 编码 + 事件解码
   ↓
[MetaMask / Browser Wallet]  (injected provider)
   ↓
[Anvil / Sepolia / Mainnet RPC]
```

### 关键文件

| 文件 | 职责 |
|---|---|
| `frontend/src/wagmi.ts` | 链定义（Anvil/Sepolia/Mainnet）+ injected connector + transport |
| `frontend/src/contract.ts` | 合约地址 + `parseAbi` 写的可读 ABI（类型自动推导） |
| `frontend/src/teams.ts` | 48 队硬编码数据，`id` 与链上 `teamId` 一一对应 |
| `frontend/src/schedule.ts` | `BET_DEADLINE` 同步、Intl 时间格式化（按浏览器时区显示） |
| `frontend/src/main.tsx` | 入口：`WagmiProvider` + `QueryClientProvider` |
| `frontend/src/App.tsx` | 钱包连接 + 奖池 / 用户状态 + 下注表单 + 队伍网格 |

### 数据流

#### 读链上状态：`useReadContract`

```tsx
const { data: totalPool } = useReadContract({
  address: GUESS_CHAMPION_ADDRESS,
  abi: GUESS_CHAMPION_ABI,
  functionName: "totalPool",
});
```

#### 用户下注：`useWriteContract` + `useWaitForTransactionReceipt`

v2 流程（推荐 permit 路径，省一笔 approve）：

```tsx
// ① 用户用钱包签 EIP-712 typed data（链下、零 gas）
const sig = await walletClient.signTypedData({
  domain: { name: "WorldCup Token", version: "1", chainId, verifyingContract: WCT },
  types: { Permit: [...] },
  primaryType: "Permit",
  message: { owner, spender: GC, value, nonce, deadline },
});
const { v, r, s } = parseSignature(sig);

// ② 调 betWithPermit 一笔搞定（permit + bet）
writeContract({
  address: GUESS_CHAMPION_ADDRESS,
  abi: GUESS_CHAMPION_ABI,
  functionName: "betWithPermit",
  args: [teamId, amount, deadline, v, r, s],
});
```

非 permit 路径（标准 approve + bet）：

```tsx
// ① 授权
writeContract({ address: WCT, abi, functionName: "approve", args: [GC, amount] });
// ② 等 tx 上链
// ③ 下注
writeContract({ address: GC, abi, functionName: "bet", args: [teamId, amount] });
```

### 链上 / 链下数据一致性

- `data/teams.json` 是 **Single Source of Truth**
- 合约 `TEAMS_HASH = keccak256(data/teams.json 原始字节)`
- `DeployAll.s.sol` 部署前自检；`HashTeams.s.sol` 用于重算
- 测试 `test_TeamsHash_matchesJsonFile` 防漂移：改了 json 没改合约常量就 RED
- 前端 `teams.ts` 内容必须等于 json 字段值（建议加启动期断言）

---

## 本地运行

### 1. 安装依赖

```bash
# 合约（含 OZ submodule）
forge install   # 或先 foundryup 拉最新工具链

# 前端
cd frontend && npm install
```

### 2. 启动本地链

```bash
anvil
```

`http://localhost:8545`，chainId = 31337，10 个测试账户每个 10000 ETH。

### 3. 一次部署 WCT + GC v2

新开终端：

```bash
forge script script/DeployAll.s.sol \
  --rpc-url http://localhost:8545 --broadcast
```

输出会显示两个地址：

```
DeployAll complete
  WCT: 0x5FbDB2315678afecb367f032d93F642f64180aa3
  GC:  0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
```

也可分两步部：先 `DeployWorldCupToken.s.sol`，再带 WCT 地址跑 `DeployGuessChampionV2.s.sol`。

### 4. 启动前端

```bash
cd frontend && npm run dev
```

打开 http://localhost:5173。

### 5. 在 MetaMask 里加 Anvil 网络

- Network Name: Anvil
- RPC URL: `http://localhost:8545`
- Chain ID: 31337
- Currency Symbol: ETH

把 Anvil 输出的某个测试账户私钥导入 MetaMask 即可。

### 6. 跑测试

```bash
forge test                                      # 全部
forge test --match-contract WorldCupTokenTest -vv
forge test --match-contract GuessChampionV2Test -vv
forge test --gas-report
```

### 7. 端到端手测（cast）

```bash
WCT=0x5FbDB2315678afecb367f032d93F642f64180aa3
GC=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
ALICE_PK=0xac09...                              # Anvil account[1]

# 领币
cast send $WCT "claimWelcome()" --private-key $ALICE_PK
cast call $WCT "balanceOf(address)(uint256)" $ALICE             # → 100e18

# 授权 + 下注
cast send $WCT "approve(address,uint256)" $GC 50000000000000000000 --private-key $ALICE_PK
cast send $GC  "bet(uint8,uint256)"        3   50000000000000000000 --private-key $ALICE_PK

# ... 时间穿越 + owner 开奖（详见 docs/LOCAL_E2E_TEST.md）

# 领奖
cast send $GC "claim()" --private-key $ALICE_PK
cast call $WCT "balanceOf(address)(uint256)" $ALICE             # → 派奖后余额
```

---

## 部署到测试网

```bash
# .env
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/...
PRIVATE_KEY=0x...
ETHERSCAN_API_KEY=...

# 部署 + 自动 verify
forge script script/DeployAll.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

把两个地址写进 `frontend/.env.local`：

```
VITE_WCT_ADDRESS=0x...
VITE_GUESS_CHAMPION_ADDRESS=0x...
```

---

## 学习路径里覆盖的 Solidity 概念

### 基础语言

- **可见性 / 状态变量**：`public` / `external` / `internal` / `private` / `immutable` / `constant`
- **函数修饰**：`view` / `pure` / `payable` / `virtual` / `override`
- **数据位置**：`storage` 引用 vs `memory` 拷贝 vs `calldata` 只读
- **整数类型**：`uint8` / `uint64` / `uint256` 的打包、溢出检查、`unchecked`
- **Custom errors with context** vs `require(string)`
- **Events** + `indexed` topics + 链下索引
- **`payable` + `msg.value` + `msg.sender`**
- **构造函数 + immutable**
- **modifier** + 访问控制
- **NatSpec**（@notice / @dev / @param）
- **Sentinel value** 哨兵值与状态机

### ERC20 与 EIP

- **ERC-20** 标准接口与实现（OpenZeppelin 继承）
- **`approve` / `transferFrom` 双步授权模型** — 为什么需要、风险在哪
- **EIP-2612 ERC20Permit** — 链下签名授权，省一笔 tx
- **EIP-712 Typed Structured Data** — `domain` + `types` + `message` 三段式
- **签名拆分** `(v, r, s)` — ECDSA 签名格式
- **front-run-permit DoS** + try/catch 缓解模式
- **EIP-1363**（payable token，扩展阅读）

### 安全与设计模式

- **CEI 模式 + reentrancy 防护**
- **Pull vs Push payment** + DoS 风险
- **OZ SafeERC20**（兼容非标 token）
- **派奖公式精度**（先乘后除）
- **状态机两条互斥不可逆分支**
- **Storage gas 成本**（SSTORE/SLOAD/refund + EIP-3529 上限）
- **Storage slot 打包**（`bool` + `uint8` 同槽）

### Foundry

- **Test cheatcodes**：`vm.warp` / `vm.prank` / `vm.deal` / `vm.expectRevert` / `vm.expectEmit`
- **Foundry script**：`vm.startBroadcast` / `vm.stopBroadcast` / `vm.readFileBinary`
- **Remappings**：`@openzeppelin/=lib/openzeppelin-contracts/`

### 前端 Web3

- **viem ABI**：`parseAbi` 人类可读 ABI / 类型推导
- **wagmi hooks**：`useReadContract` / `useWriteContract` / `useWaitForTransactionReceipt`
- **viem signTypedData**：构造 EIP-712 签名（permit 路径）

---

## 参考

- [Solidity 文档](https://docs.soliditylang.org/)
- [Foundry Book](https://book.getfoundry.sh/)
- [viem 文档](https://viem.sh/)
- [wagmi 文档](https://wagmi.sh/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [EIP-2612: ERC20 permit](https://eips.ethereum.org/EIPS/eip-2612)
- [EIP-712: Typed structured data hashing and signing](https://eips.ethereum.org/EIPS/eip-712)
- [Solidity Patterns（设计模式合集）](https://github.com/fravoll/solidity-patterns)
