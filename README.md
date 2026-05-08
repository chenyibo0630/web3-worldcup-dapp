# worldcup-dapp — 2026 世界杯猜冠军 DApp

一个用来学习 Solidity + Foundry + viem/wagmi 全栈 Web3 的练手项目。
玩法：用户开赛前下注押冠军 → 决赛后 owner 公布冠军 → 押中的人按比例瓜分整个奖池。

```
[用户钱包]  ─bet (ETH)─►  [GuessChampion 合约]  ─派奖─►  [赢家钱包]
                                  ▲
                               owner declareChampion
```

---

## 仓库结构

```
worldcup-dapp/
├── src/                       Solidity 合约
│   ├── GuessChampion.sol      ← 主合约
│   ├── IChampionOracle.sol    ← Oracle 接口（备用）
│   └── MockChampionOracle.sol ← Mock 实现（备用）
├── test/
│   └── GuessChampion.t.sol    ← 41 个 forge 测试用例
├── script/
│   └── DeployGuessChampion.s.sol
├── frontend/                  Vite + React + TS + wagmi
│   └── src/
│       ├── App.tsx            ← 主页面
│       ├── wagmi.ts           ← wagmi 配置
│       ├── contract.ts        ← 合约地址 + ABI
│       ├── teams.ts           ← 48 队硬编码数据
│       └── schedule.ts        ← BET_DEADLINE 时间戳
├── data/teams.json            ← 队伍数据真相源（被合约 hash 锚定）
├── docs/
│   └── LOCAL_E2E_TEST.md      ← 手测命令手册
├── foundry.toml               ← Foundry 配置
└── README.md                  ← 本文件
```

---

## 合约设计

### 状态机

```
                cancelled=false, champion=0
                允许 bet
                    │
            ┌───────┴───────┐
   emergencyCancel       declareChampion
   （owner，pre-deadline 也可）  (owner，post-deadline)
            │                   │
            ▼                   ▼
    cancelled=true        champion=N (1..48)
    refund 通道开放        claim 通道开放

特殊路径：declareChampion 选了无人押的队
       → 自动转到 cancelled=true 分支
       → 所有人按 refund 通道拿回本金
```

两条互斥不可逆分支：

| 状态 | `cancelled` | `champion` | 谁能操作 |
|---|---|---|---|
| 下注期 | false | 0 | 用户 `bet` |
| 紧急 / 自动取消 | **true** | 0 | 用户 `refund / refundFor / refundForBatch` |
| 已开奖 | false | **N≠0** | 用户 `claim / claimFor / claimForBatch` |

### 关键设计点

1. **Pull 模式（业界主流）**
   合约不主动派钱，每个赢家自己（或 Keeper 代）调 `claim()`。避免 N 用户单 tx push 的 DoS 风险。

2. **每人押一队**
   `mapping(address => uint8) teamOf` 强制约束。用户首次下注登记 + push 进 `teamBettors`，后续加注不重复 push。

3. **金额范围**
   `MIN_BET = 0.01 ETH`、`MAX_BET = 1 ETH`，避免微尘粉尘攻击 / 巨鲸操纵。

4. **CEI 反重入**
   所有 state-changing 函数严格 `Checks → Effects → Interactions` 顺序。`delete betAmounts/teamOf` 在 `call{value:}` 之前，重入再来时 `stake = 0` 直接 revert。

5. **派奖公式**
   ```
   payout = totalPool × stake / winnersTotal   // 必须先乘后除，否则整数截断丢精度
   ```
   `totalPool` 在 declareChampion 后保持快照（不递减），作为常量分子。

6. **代领（claimFor / refundFor）**
   任何人可触发某 user 的 claim/refund，钱**固定**转给 user 本人（不是调用者）。这让运营 Keeper 能批量代付 gas，模拟"自动到账"UX。

7. **批量代领（claimForBatch / refundForBatch）**
   一笔 tx 处理多个用户，摊销 21K tx 基础 gas。建议单批 ≤ 50。

8. **状态打包**
   `cancelled`(bool) + `champion`(uint8) 自动塞同一个 storage slot，部署成本最低。

9. **常量哨兵值**
   - `champion == 0` ≡ "未开奖"
   - `teamOf[user] == 0` ≡ "未下注"
   合并使用让状态机字段最少，gas 最省。

### 核心接口

```solidity
// 用户
function bet(uint8 teamId) external payable;
function claim() external;
function refund() external;

// owner
function emergencyCancel() external;
function declareChampion(uint8 winningTeam) external;

// Keeper / 任何人代触发
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
```

### 已知设计取舍

| 项 | 现状 | 生产级建议 |
|---|---|---|
| owner 决定冠军 | 中心化 | 接 Chainlink Sports Data 或 UMA Optimistic Oracle |
| owner 误判后不可撤销（除非自动取消触发） | 不可逆 | 加 timelock + 多签 |
| dust（精度残留）锁在合约 | wei 级，可忽略 | 加 `sweep()` 由 owner 回收 |
| `teamBettors[winningTeam]` 在 declareChampion 后被 delete 清理 | ✅ 已做 | — |
| 输家的 `betAmounts/teamOf` 永久残留 | 灰尘，无影响 | 不必清，refund cap 限制下不划算 |
| 大规模 N → declareChampion 单循环求和 | N=10000 仍安全 | N>14k 接近 block gas 上限，需分页 |

---

## 前端工作原理

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
| `frontend/src/wagmi.ts` | 定义链（Anvil / Sepolia / Mainnet）+ connectors（injected MetaMask）+ transport |
| `frontend/src/contract.ts` | 合约地址 + 用 `parseAbi` 写的可读 ABI（类型自动推导）|
| `frontend/src/teams.ts` | 48 队硬编码数据，每个 team 的 `id` 与链上 `teamId` 一一对应 |
| `frontend/src/schedule.ts` | `BET_DEADLINE` 同步、Intl 时间格式化（按浏览器时区显示）|
| `frontend/src/main.tsx` | 入口：`WagmiProvider` + `QueryClientProvider` 包住 App |
| `frontend/src/App.tsx` | 钱包连接 + 奖池/用户状态 + 下注表单 + 队伍网格 |

### 数据流

#### 读链上状态：`useReadContract`

```tsx
const { data: totalPool } = useReadContract({
  address: GUESS_CHAMPION_ADDRESS,
  abi: GUESS_CHAMPION_ABI,
  functionName: "totalPool",
});
```

- 自动用 wagmi 的 `QueryClient` 缓存（`@tanstack/react-query`）
- 区块更新时按需刷新（默认 4 秒轮询，可配置）
- 类型从 ABI 自动推导：`totalPool` 是 `bigint | undefined`

#### 用户下注：`useWriteContract` + `useWaitForTransactionReceipt`

```tsx
const { writeContract, data: hash, isPending } = useWriteContract();
const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

writeContract({
  address: GUESS_CHAMPION_ADDRESS,
  abi: GUESS_CHAMPION_ABI,
  functionName: "bet",
  args: [selected.id],
  value: parseEther(amount),  // ← 转 wei
});
```

两阶段：
1. `writeContract` 弹钱包让用户签 tx → 得到 `hash`
2. `useWaitForTransactionReceipt` 监听 hash 上链 → `isSuccess = true`

#### 钱包连接：`useAccount` + `useConnect` + `useDisconnect`

```tsx
const { address, isConnected, chain } = useAccount();
const { connect, connectors } = useConnect();
connect({ connector: connectors[0] });  // 第 0 个是 injected (MetaMask 等)
```

### 时区显示

```ts
new Intl.DateTimeFormat(undefined, {
  year: "numeric", month: "short", day: "2-digit",
  hour: "2-digit", minute: "2-digit", timeZoneName: "short",
}).format(new Date(unixSeconds * 1000));
```

`undefined` 让浏览器用本地时区。EVM 用绝对 Unix 时间戳（永远 UTC），渲染时再转本地。

### 链上 / 链下数据一致性

- `data/teams.json` 是**Single Source of Truth**
- 合约 `TEAMS_HASH = keccak256(data/teams.json 原始字节)`（已加，待集成）
- 测试 `test_TeamsHash_matchesJsonFile` 防止漂移：改了 json 没改合约常量就 RED
- 前端 `teams.ts` 内容必须等于 json 字段值（可加启动期断言）

---

## 本地运行

### 1. 安装依赖

```bash
# 合约
forge install   # 或 foundryup 拉最新工具链

# 前端
cd frontend && npm install
```

### 2. 启动本地链

```bash
anvil
```

默认起在 `http://localhost:8545`，chainId = 31337，10 个测试账户每个 10000 ETH。

### 3. 部署合约

新开终端：

```bash
forge script script/DeployGuessChampion.s.sol --rpc-url http://localhost:8545 --broadcast
```

输出会显示部署地址（默认是 `0x5FbDB2315678afecb367f032d93F642f64180aa3`，Anvil 第一个部署）。

### 4. 启动前端

```bash
cd frontend && npm run dev
```

打开 [http://localhost:5173](http://localhost:5173)。

### 5. 在 MetaMask 里加 Anvil 网络

- Network Name: Anvil
- RPC URL: `http://localhost:8545`
- Chain ID: 31337
- Currency Symbol: ETH

把 Anvil 输出的某个测试账户私钥（如 `0xac09...`）导入 MetaMask，就能下注了。

### 6. 跑测试

```bash
forge test --match-contract GuessChampionTest -vv
forge test --match-test test_e2e_fullHappyPath -vvvv  # 单个测试详细
forge test --gas-report
```

### 7. 端到端手测

详见 `docs/LOCAL_E2E_TEST.md`——一组可复制粘贴的 cast 命令。

---

## 部署到测试网

```bash
# .env 文件
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/...
PRIVATE_KEY=0x...你的私钥
ETHERSCAN_API_KEY=...

# 部署 + 自动 verify
forge script script/DeployGuessChampion.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

部署成功后，把合约地址写到 `frontend/.env.local`：

```
VITE_GUESS_CHAMPION_ADDRESS=0x...你的部署地址
```

前端自动从环境变量读取。

---

## 学习路径里覆盖的 Solidity 概念

- **可见性 / 状态变量**：`public`、`immutable`、`constant`
- **数据位置**：`storage` 引用 vs `memory` 拷贝
- **整数类型**：`uint8`/`uint64`/`uint256` 的打包、溢出检查、`unchecked`
- **Custom errors with context** vs `require(string)`
- **Events** + `indexed` topics + 链下索引
- **`payable` + `msg.value` + `msg.sender`**
- **CEI 模式 + reentrancy 防护**
- **Pull vs Push payment** + DoS 风险
- **Storage gas 成本**（SSTORE/SLOAD/refund + EIP-3529 上限）
- **派奖公式精度**（先乘后除）
- **构造函数 + immutable**
- **modifier** + 访问控制
- **Sentinel value** 哨兵值与状态机
- **NatSpec**（@notice / @dev / @param）
- **Foundry**：`vm.warp` / `vm.prank` / `vm.deal` / `vm.expectRevert` / `vm.expectEmit`
- **Foundry script**：`vm.startBroadcast` / `vm.stopBroadcast` / `forge script`
- **viem ABI**：`parseAbi` 人类可读 ABI / 类型推导
- **wagmi hooks**：`useReadContract` / `useWriteContract` / `useWaitForTransactionReceipt`

---

## 参考

- [Solidity 文档](https://docs.soliditylang.org/)
- [Foundry Book](https://book.getfoundry.sh/)
- [viem 文档](https://viem.sh/)
- [wagmi 文档](https://wagmi.sh/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [Solidity Patterns（设计模式合集）](https://github.com/fravoll/solidity-patterns)
