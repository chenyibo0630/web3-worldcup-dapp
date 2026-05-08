#!/usr/bin/env node
// 把 forge build 产物里的 ABI 抽取到前端 src/ 目录
//
// 用法：
//   forge build
//   node scripts/extract-abi.mjs
//
// 产出：frontend/src/GuessChampion.abi.json
// 在前端代码里：import abi from "./GuessChampion.abi.json";

import { readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "..");

const artifact = resolve(repoRoot, "out/GuessChampion.sol/GuessChampion.json");
const target = resolve(repoRoot, "frontend/src/GuessChampion.abi.json");

const json = JSON.parse(readFileSync(artifact, "utf8"));
if (!Array.isArray(json.abi)) {
  console.error("Unexpected artifact shape: missing .abi[]");
  process.exit(1);
}

writeFileSync(target, JSON.stringify(json.abi, null, 2) + "\n", "utf8");
console.log(`Wrote ${target}  (${json.abi.length} ABI entries)`);
