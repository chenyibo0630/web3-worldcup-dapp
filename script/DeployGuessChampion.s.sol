// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {GuessChampion} from "../src/GuessChampion.sol";

/// @title  GuessChampion 部署脚本
/// @notice 用法：
///   anvil（本地）：
///     forge script script/DeployGuessChampion.s.sol --rpc-url http://localhost:8545 --broadcast
///
///   测试网（Sepolia）：
///     forge script script/DeployGuessChampion.s.sol \
///       --rpc-url $SEPOLIA_RPC_URL \
///       --private-key $PRIVATE_KEY \
///       --broadcast --verify \
///       --etherscan-api-key $ETHERSCAN_API_KEY
contract DeployGuessChampion is Script {
    function run() external returns (GuessChampion gc) {
        // ⚠ 部署前自检：data/teams.json 的实际指纹必须等于合约里写死的 TEAMS_HASH
        // 防止"改了 JSON 忘改常量"或反之导致前端/合约失同步
        bytes memory raw = vm.readFileBinary("data/teams.json");
        bytes32 expected = keccak256(raw);

        // 本地 dry-run 一份合约（不在 broadcast 范围内 → 不上链、不花 gas），
        // 只为读出 bytecode 里编进去的 TEAMS_HASH 常量做对比
        GuessChampion probe = new GuessChampion();
        require(
            probe.TEAMS_HASH() == expected,
            "TEAMS_HASH mismatch: update GuessChampion.TEAMS_HASH or revert teams.json"
        );

        vm.startBroadcast();

        gc = new GuessChampion();

        vm.stopBroadcast();

        // 双保险：真部署到链上的常量也要等于本地算出来的
        require(gc.TEAMS_HASH() == expected, "Deployed TEAMS_HASH != local hash");

        console.log("==========================================");
        console.log("GuessChampion deployed");
        console.log("  address:      ", address(gc));
        console.log("  owner:        ", gc.owner());
        console.log("  TEAM_COUNT:   ", gc.TEAM_COUNT());
        console.log("  MIN_BET (wei):", gc.MIN_BET());
        console.log("  MAX_BET (wei):", gc.MAX_BET());
        console.log("  BET_DEADLINE: ", gc.BET_DEADLINE());
        console.log("  teams.json B: ", raw.length);
        console.log("  TEAMS_HASH:   ");
        console.logBytes32(gc.TEAMS_HASH());
        console.log("==========================================");
    }
}
