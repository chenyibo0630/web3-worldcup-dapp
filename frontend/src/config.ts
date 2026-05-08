// 合约地址配置 — 按链 ID 索引
//
// 用户个人地址不在这里配置：通过 wagmi 的 useAccount() 从已连接钱包动态读取。
// 这里只放公开的、可入仓库的"链上资源标识"。
//
// 真实地址放在 frontend/.env.local（已 gitignore）；本文件只负责类型化和聚合。

import type { Address } from "viem";

// Vite 内置 chainId（避免引入 wagmi/chains 让本文件保持零依赖）
const CHAIN_ID = {
  ANVIL: 31337,
  SEPOLIA: 11155111,
  MAINNET: 1,
} as const;

/// 注意：env 在 build 阶段被 Vite 静态替换，缺失会变成 undefined → 运行期校验
function readEnv(key: string): Address | undefined {
  const v = (import.meta.env as Record<string, string | undefined>)[key];
  if (!v || v === "0x0000000000000000000000000000000000000000") return undefined;
  return v as Address;
}

export const CONTRACT_ADDRESS: Readonly<Record<number, Address | undefined>> = {
  [CHAIN_ID.ANVIL]: readEnv("VITE_GUESS_CHAMPION_ANVIL"),
  [CHAIN_ID.SEPOLIA]: readEnv("VITE_GUESS_CHAMPION_SEPOLIA"),
  [CHAIN_ID.MAINNET]: readEnv("VITE_GUESS_CHAMPION_MAINNET"),
};

/// 当前链上的 GuessChampion 地址，没配置就 undefined（调用方要做 fallback）
export function getContractAddress(chainId: number | undefined): Address | undefined {
  if (!chainId) return undefined;
  return CONTRACT_ADDRESS[chainId];
}

export const SUPPORTED_CHAIN_IDS = Object.entries(CONTRACT_ADDRESS)
  .filter(([, addr]) => !!addr)
  .map(([id]) => Number(id));
