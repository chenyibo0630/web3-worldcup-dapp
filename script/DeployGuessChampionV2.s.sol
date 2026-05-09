// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GuessChampionV2} from "../src/GuessChampionV2.sol";

/// @title  GuessChampionV2 部署脚本（需要传入已部署的 WCT 地址）
/// @notice 用法：
///   anvil（本地）：
///     forge script script/DeployGuessChampionV2.s.sol \
///       --sig "run(address)" <WCT_ADDR> \
///       --rpc-url http://localhost:8545 --broadcast
///
///   测试网：同上，加 --verify --etherscan-api-key
contract DeployGuessChampionV2 is Script {
    function run(address wctAddr) external returns (GuessChampionV2 gc) {
        require(wctAddr != address(0), "wct address required");

        // ⚠ 部署前自检：data/teams.json 的实际指纹必须等于合约里写死的 TEAMS_HASH
        bytes memory raw = vm.readFileBinary("data/teams.json");
        bytes32 expected = keccak256(raw);

        // dry-run 一份合约（不在 broadcast 范围 → 不上链、不花 gas），
        // 只为读出 bytecode 里编进去的 TEAMS_HASH 常量做对比
        GuessChampionV2 probe = new GuessChampionV2(IERC20(wctAddr));
        require(
            probe.TEAMS_HASH() == expected,
            "TEAMS_HASH mismatch: update GuessChampionV2.TEAMS_HASH or revert teams.json"
        );

        vm.startBroadcast();
        gc = new GuessChampionV2(IERC20(wctAddr));
        vm.stopBroadcast();

        require(gc.TEAMS_HASH() == expected, "Deployed TEAMS_HASH != local hash");

        console.log("==========================================");
        console.log("GuessChampionV2 deployed");
        console.log("  address:      ", address(gc));
        console.log("  owner:        ", gc.owner());
        console.log("  wct:          ", address(gc.wct()));
        console.log("  TEAM_COUNT:   ", gc.TEAM_COUNT());
        console.log("  MIN_BET (WCT):", gc.MIN_BET());
        console.log("  MAX_BET (WCT):", gc.MAX_BET());
        console.log("  BET_DEADLINE: ", gc.BET_DEADLINE());
        console.log("  TEAMS_HASH:   ");
        console.logBytes32(gc.TEAMS_HASH());
        console.log("==========================================");
    }
}
