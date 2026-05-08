# GuessChampion 本地端到端手测手册

本文档给出一组**可复制粘贴**的命令，覆盖：
- 启动本地链（anvil）
- 部署合约（forge script）
- 用 cast 模拟下注、开奖、领奖完整流程
- 失败/异常分支验证

> 所有命令默认在仓库根目录 `worldcup-dapp/` 执行。
> 跨终端使用时，环境变量需要在每个新终端重新设置。

## Shell 差异速查（重要）

本文档示例用 **Bash 语法**（`export VAR=value`、行尾 `\` 续行）。
**Windows PowerShell** 用户请按以下规则改写：

| 场景 | Bash | PowerShell |
|------|------|------------|
| 设置环境变量 | `export GC=0x123` | `$env:GC = "0x123"` 或 `$GC = "0x123"` |
| 引用变量 | `$GC` | `$env:GC`（环境变量）/ `$GC`（普通变量） |
| 引用变量到子进程 | `$GC` 自动传递 | `$env:GC` 自动传递；`$GC` 也能在同一会话内引用 |
| 多行续行 | 行尾 `\` | 行尾反引号 `` ` ``（注意 PowerShell 的反引号是续行符） |
| 比较运算 | `[ $a -eq 1 ]` | `$a -eq 1` |
| 命令置换 | `$(cmd)` | `$(cmd)`（PowerShell 也支持） |

**简单建议**：PowerShell 下直接用 `$VAR = "value"`（普通变量，作用域是当前会话），引用就用 `$VAR`，本文所有 `$VAR` 引用都能正常工作。**不要**用 `$env:VAR` 除非你确实想写到环境变量层。

> Git Bash / WSL / macOS / Linux 用户可以原样使用 Bash 命令。

---

## 0. 准备

确认本地装好 Foundry：

```bash
forge --version
cast --version
anvil --version
```

确认合约能编译 + 测试通过：

```bash
forge build
forge test -vv
```

---

## 1. 启动本地链（终端 A，保持运行）

```bash
anvil
```

**默认产物**（每次启动完全一致，可硬编码）：

| 角色 | 地址 | 私钥 |
|------|------|------|
| `OWNER` (account 0) | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| `ALICE` (account 1) | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` |
| `BOB`   (account 2) | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` |
| `CAROL` (account 3) | `0x90F79bf6EB2c4f870365E785982E1f101E93b906` | `0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6` |
| `DAVE`  (account 4) | `0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65` | `0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a` |

每个账户初始 10000 ETH。**保持这个终端不关**，一关链就没了。

---

## 2. 编程化获取账户（可选）

在新终端 B 验证 RPC 连通：

```bash
cast rpc eth_accounts --rpc-url http://localhost:8545
cast chain-id          --rpc-url http://localhost:8545   # 期望 31337
cast block-number      --rpc-url http://localhost:8545
cast balance 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url http://localhost:8545
```

---

## 3. 设置环境变量（终端 B，整套测试都在这里跑）

### Bash / Git Bash / macOS / Linux

```bash
export RPC=http://localhost:8545

# Anvil 默认账户
export OWNER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export OWNER_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export ALICE=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
export ALICE_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
export BOB=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
export BOB_PK=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
export CAROL=0x90F79bf6EB2c4f870365E785982E1f101E93b906
export CAROL_PK=0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
```

### Windows PowerShell

```powershell
$RPC = "http://localhost:8545"

# Anvil 默认账户
$OWNER     = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
$OWNER_PK  = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
$ALICE     = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
$ALICE_PK  = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
$BOB       = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
$BOB_PK    = "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
$CAROL     = "0x90F79bf6EB2c4f870365E785982E1f101E93b906"
$CAROL_PK  = "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6"
```

> 之后所有 `$RPC` / `$ALICE_PK` 等引用方式两种 shell 完全一致，
> **唯一差异**只在多行命令的续行符：Bash 用 `\`，PowerShell 用反引号 `` ` ``。

---

## 4. 部署合约

```bash
forge script script/DeployGuessChampion.s.sol --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

输出末尾会打印：

```
GuessChampion deployed
  address:       0x5FbDB2315678afecb367f032d93F642f64180aa3
  owner:         0xf39F...92266
  ...
```

把部署地址记下来：

**Bash:**
```bash
export GC=0x5FbDB2315678afecb367f032d93F642f64180aa3   # ← 替换为你实际的地址
```

**PowerShell:**
```powershell
$GC = "0x5FbDB2315678afecb367f032d93F642f64180aa3"     # ← 替换为你实际的地址
```

> 也可以从 `broadcast/DeployGuessChampion.s.sol/31337/run-latest.json` 自动提取：
>
> **Bash（需要 jq）:**
> ```bash
> export GC=$(jq -r '.transactions[0].contractAddress' broadcast/DeployGuessChampion.s.sol/31337/run-latest.json)
> echo $GC
> ```
>
> **PowerShell（无依赖，原生 JSON 解析）:**
> ```powershell
> $GC = (Get-Content broadcast/DeployGuessChampion.s.sol/31337/run-latest.json | ConvertFrom-Json).transactions[0].contractAddress
> echo $GC
> ```

---

## 5. 部署后只读检查

```bash
cast call $GC "owner()(address)"          --rpc-url $RPC
cast call $GC "TEAM_COUNT()(uint8)"       --rpc-url $RPC   # 48
cast call $GC "MIN_BET()(uint256)"        --rpc-url $RPC   # 10000000000000000  (0.01 ether)
cast call $GC "MAX_BET()(uint256)"        --rpc-url $RPC   # 1000000000000000000 (1 ether)
cast call $GC "BET_DEADLINE()(uint64)"    --rpc-url $RPC   # 1781136000
cast call $GC "drawn()(bool)"             --rpc-url $RPC   # false
cast call $GC "totalPool()(uint256)"      --rpc-url $RPC   # 0

# 5.1 验证 teams 映射指纹（链上承诺的 keccak256(data/teams.json)）
cast call $GC "TEAMS_HASH()(bytes32)"     --rpc-url $RPC
# 期望：0x8ccca76bebb51a66704e72959299c5db802e3a20fc186333c52fee50788fbca9

# 重新计算本地 data/teams.json 的指纹做比对：
forge script script/HashTeams.s.sol
# 输出末尾的 keccak256 值应与上面的链上 TEAMS_HASH 完全一致；
# 不一致 → 仓库 JSON 已被改动且未同步合约常量，前端/索引器应拒绝交互
```

---

## 6. 下注（happy path）

剧本：Alice、Bob 都押 **3 号队**；Carol 押 **5 号队**。

```bash
# Alice 押 3 号队 0.5 ether
cast send 0x5FbDB2315678afecb367f032d93F642f64180aa3 "bet(uint8)" 3  --value 0.5ether  --rpc-url http://localhost:8545 --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

# Bob 押 3 号队 0.3 ether
cast send 0x5FbDB2315678afecb367f032d93F642f64180aa3 "bet(uint8)" 3  --value 0.3ether  --rpc-url http://localhost:8545 --private-key 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a

# Carol 押 5 号队 0.4 ether
cast send 0x5FbDB2315678afecb367f032d93F642f64180aa3 "bet(uint8)" 5 --value 0.4ether  --rpc-url http://localhost:8545 --private-key 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6

# Alice 同队加注 0.2 ether（合法）
cast send 0x5FbDB2315678afecb367f032d93F642f64180aa3 "bet(uint8)" 3  --value 0.2ether  --rpc-url http://localhost:8545 --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
```

校验状态：

```bash
cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "totalPool()(uint256)"          --rpc-url $RPC   # 1.4 ether
cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "betAmounts(address)(uint256)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --rpc-url $RPC   # 0.7 ether
cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "betAmounts(address)(uint256)" 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC   --rpc-url $RPC   # 0.3 ether
cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "betAmounts(address)(uint256)" 0x90F79bf6EB2c4f870365E785982E1f101E93b906 --rpc-url $RPC   # 0.4 ether
cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "teamOf(address)(uint8)"       0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --rpc-url $RPC   # 3
cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "teamOf(address)(uint8)"       0x90F79bf6EB2c4f870365E785982E1f101E93b906 --rpc-url $RPC   # 5
cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "teamBettors(uint8,uint256)(address)" 3 0 --rpc-url $RPC   # ALICE
cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "teamBettors(uint8,uint256)(address)" 3 1 --rpc-url $RPC   # BOB
```

---

## 7. 异常分支（必跑，验证 revert）

每条命令应该**失败**，仔细读 cast 报错信息中的 selector，能反推自定义 error。

```bash
# 7.1 金额越界（< MIN_BET）
cast send $GC "bet(uint8)" 3 --value 0.001ether \
  --rpc-url $RPC --private-key $ALICE_PK
# 期望：BetOutOfRange

# 7.2 金额越界（> MAX_BET）
cast send $GC "bet(uint8)" 3 --value 2ether \
  --rpc-url $RPC --private-key $ALICE_PK
# 期望：BetOutOfRange

# 7.3 非法 teamId = 0
cast send $GC "bet(uint8)" 0 --value 0.1ether \
  --rpc-url $RPC --private-key $ALICE_PK
# 期望：InvalidTeam(0)

# 7.4 非法 teamId > 48
cast send $GC "bet(uint8)" 49 --value 0.1ether \
  --rpc-url $RPC --private-key $ALICE_PK
# 期望：InvalidTeam(49)

# 7.5 改押别队（Alice 已押 3，再押 4 必败）
cast send $GC "bet(uint8)" 4 --value 0.1ether \
  --rpc-url $RPC --private-key $ALICE_PK
# 期望：AlreadyBetOnDifferentTeam(3)

# 7.6 截止前开奖
cast send $GC "declareChampion(uint8)" 3 \
  --rpc-url $RPC --private-key $OWNER_PK
# 期望：NotDrawable

# 7.7 非 owner 开奖
cast send $GC "declareChampion(uint8)" 3 \
  --rpc-url $RPC --private-key $ALICE_PK
# 期望：NotOwner

# 7.8 未开奖就 claim
cast send $GC "claim()" \
  --rpc-url $RPC --private-key $ALICE_PK
# 期望：NotDrawn
```

---

## 8. 时间穿越到截止之后（Anvil 专属）

合约 `BET_DEADLINE = 1781136000`（2026-06-11 UTC）。直接把链时间设到截止后：

```bash
# 设置下一个区块时间戳为 deadline + 1 秒
cast rpc evm_setNextBlockTimestamp 1781136001 --rpc-url $RPC
cast rpc evm_mine --rpc-url $RPC
cast block latest --rpc-url $RPC | grep timestamp
```

此时再 `bet` 应失败：

```bash
cast send $GC "bet(uint8)" 7 --value 0.1ether \
  --rpc-url $RPC --private-key $DAVE
# 期望：BettingClosed
```

---

## 9. 开奖

owner 宣布 **3 号队**为冠军：

```bash
cast send $GC "declareChampion(uint8)" 3 \
  --rpc-url $RPC --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

校验：

```bash
cast call $GC "drawn()(bool)"               --rpc-url $RPC   # true
cast call $GC "champion()(uint8)"           --rpc-url $RPC   # 3
cast call $GC "winnersTotal()(uint256)"     --rpc-url $RPC   # 1.0 ether (Alice 0.7 + Bob 0.3)
cast call $GC "totalPool()(uint256)"        --rpc-url $RPC   # 1.4 ether（保持快照）
```

抓 `Drawn` 事件：

```bash
cast logs --address $GC \
  --from-block 0 \
  "Drawn(uint8,uint256,uint256)" \
  --rpc-url $RPC
```

不能重复开奖：

```bash
cast send $GC "declareChampion(uint8)" 5 \
  --rpc-url $RPC --private-key $OWNER_PK
# 期望：AlreadyDrawn
```

---

## 10. 领奖（pull 模式）

### 10.1 Alice 自己 claim

```bash
# 领奖前余额
cast balance $ALICE --rpc-url $RPC

cast send $GC "claim()" \
  --rpc-url $RPC --private-key $ALICE_PK

# 领奖后余额（应增加 ≈ 1.4 * 0.7 / 1.0 = 0.98 ether，再扣少量 gas）
cast balance $ALICE --rpc-url $RPC

# 状态被清空
cast call $GC "betAmounts(address)(uint256)" $ALICE --rpc-url $RPC   # 0
cast call $GC "teamOf(address)(uint8)"       $ALICE --rpc-url $RPC   # 0
```

### 10.2 任何人代 Bob 领（claimFor）

```bash
# 用 Carol 的私钥替 Bob 触发，钱仍打到 Bob 地址
cast send $GC "claimFor(address)" $BOB \
  --rpc-url $RPC --private-key $CAROL_PK

cast balance $BOB --rpc-url $RPC          # 增加 ≈ 0.42 ether
cast call $GC "betAmounts(address)(uint256)" $BOB --rpc-url $RPC   # 0
```

### 10.3 重复 claim 必败

```bash
cast send $GC "claim()" \
  --rpc-url $RPC --private-key $ALICE_PK
# 期望：NothingToClaim
```

### 10.4 非中奖者 claim 必败

```bash
cast send $GC "claim()" \
  --rpc-url $RPC --private-key $CAROL_PK
# Carol 押的是 5 号队，非冠军 → 期望：NotWinner
```

### 10.5 抓 Claimed 事件

```bash
cast logs --address $GC \
  --from-block 0 \
  "Claimed(address,uint256)" \
  --rpc-url $RPC
```

---

## 11. 批量代领（claimForBatch）

重新部署一次合约，让多个用户中奖，然后一次性批量领。流程参照 §4–§9，开奖后：

```bash
cast send $GC "claimForBatch(address[])" "[$ALICE,$BOB]" \
  --rpc-url $RPC --private-key $CAROL_PK
```

注意 array 参数语法：方括号包裹、逗号分隔，**不要带空格**。

---

## 12. 一键重置

不想重启 anvil，但想清空状态？最简单办法：直接重新部署一份新合约，更新 `$GC`：

```bash
forge script script/DeployGuessChampion.s.sol \
  --rpc-url $RPC --broadcast --private-key $OWNER_PK

export GC=$(jq -r '.transactions[0].contractAddress' \
  broadcast/DeployGuessChampion.s.sol/31337/run-latest.json)
```

或者整个 anvil 进程 Ctrl+C 重启，链状态会全部丢失（这是好事，状态干净）。

---

## 13. 常见问题

| 现象 | 原因 / 解决 |
|------|-------------|
| `cast: error sending request` | anvil 没启动 / 端口被占用 |
| `execution reverted, data: "0x..."` | 命中自定义 error，用 `cast 4byte 0x...` 反查 |
| 部署成功但 `$GC` 调不通 | 合约地址打错；或 anvil 重启了，需要重新部署 |
| `claim` 后余额没变 | 看是否被 gas 抵消了；或 tx 实际 revert（看 `cast receipt`） |
| 时间穿越后 `bet` 仍成功 | `evm_setNextBlockTimestamp` 只影响**下一个**区块；记得 `evm_mine` |

---

## 14. 速查命令对照

| 操作 | 命令 |
|------|------|
| 启动链 | `anvil` |
| 看 chainId | `cast chain-id --rpc-url $RPC` |
| 看余额 | `cast balance <addr> --rpc-url $RPC` |
| 部署 | `forge script script/DeployGuessChampion.s.sol --rpc-url $RPC --broadcast --private-key $OWNER_PK` |
| 写函数 | `cast send <addr> "<sig>" <args> --value <eth>ether --rpc-url $RPC --private-key <pk>` |
| 读函数 | `cast call <addr> "<sig>(<rettype>)" <args> --rpc-url $RPC` |
| 看事件 | `cast logs --address <addr> --from-block 0 "<EventSig>" --rpc-url $RPC` |
| 看 tx 详情 | `cast tx <txhash> --rpc-url $RPC` |
| 看 receipt | `cast receipt <txhash> --rpc-url $RPC` |
| 反查 selector | `cast 4byte 0xa9059cbb` |
| 时间穿越 | `cast rpc evm_setNextBlockTimestamp <ts> --rpc-url $RPC && cast rpc evm_mine --rpc-url $RPC` |
| 切换账户余额 | `cast rpc anvil_setBalance <addr> 0x<hex_wei> --rpc-url $RPC` |
