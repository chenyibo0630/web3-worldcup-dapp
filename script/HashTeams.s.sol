// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

/// @title  TeamsHash 计算脚本
/// @notice 读取 data/teams.json 的原始字节，计算 keccak256 并打印
/// @dev    用法：forge script script/HashTeams.s.sol
///         把输出的 0x... 粘贴到 GuessChampion.TEAMS_HASH 常量
contract HashTeams is Script {
    function run() external view {
        bytes memory raw = vm.readFileBinary("data/teams.json");
        bytes32 h = keccak256(raw);

        console.log("==========================================");
        console.log("data/teams.json size (bytes):", raw.length);
        console.log("keccak256 (paste as TEAMS_HASH):");
        console.logBytes32(h);
        console.log("==========================================");
    }
}
