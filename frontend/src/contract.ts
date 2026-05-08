import { parseAbi } from "viem";

// Anvil 默认部署器（0xf39F...）首次部署的确定性地址
// 部署到测试网/主网后改这里（或改用环境变量 VITE_GUESS_CHAMPION_ADDRESS）
export const GUESS_CHAMPION_ADDRESS =
  (import.meta.env.VITE_GUESS_CHAMPION_ADDRESS as `0x${string}` | undefined) ??
  "0x5FbDB2315678afecb367f032d93F642f64180aa3";

// 用 parseAbi 写人类可读 ABI，类型自动推导
export const GUESS_CHAMPION_ABI = parseAbi([
  // ── 常量 / 状态 view ────────────────────
  "function TEAM_COUNT() view returns (uint8)",
  "function MIN_BET() view returns (uint256)",
  "function MAX_BET() view returns (uint256)",
  "function BET_DEADLINE() view returns (uint64)",
  "function owner() view returns (address)",
  "function totalPool() view returns (uint256)",
  "function cancelled() view returns (bool)",
  "function champion() view returns (uint8)",
  "function winnersTotal() view returns (uint256)",
  "function betAmounts(address) view returns (uint256)",
  "function teamOf(address) view returns (uint8)",

  // ── 用户写入 ────────────────────────────
  "function bet(uint8 teamId) payable",
  "function claim()",
  "function refund()",

  // ── owner 写入 ─────────────────────────
  "function emergencyCancel()",
  "function declareChampion(uint8 winningTeam)",

  // ── 事件 ────────────────────────────────
  "event BetPlaced(address indexed user, uint8 indexed teamId, uint256 amount)",
  "event Cancelled()",
  "event Refunded(address indexed user, uint256 amount)",
  "event Drawn(uint8 indexed champion, uint256 winnersTotal, uint256 pool)",
  "event Claimed(address indexed user, uint256 amount)",
]);
