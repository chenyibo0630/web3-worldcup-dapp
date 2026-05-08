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
        vm.startBroadcast();

        gc = new GuessChampion();

        vm.stopBroadcast();

        console.log("==========================================");
        console.log("GuessChampion deployed");
        console.log("  address:      ", address(gc));
        console.log("  owner:        ", gc.owner());
        console.log("  TEAM_COUNT:   ", gc.TEAM_COUNT());
        console.log("  MIN_BET (wei):", gc.MIN_BET());
        console.log("  MAX_BET (wei):", gc.MAX_BET());
        console.log("  BET_DEADLINE: ", gc.BET_DEADLINE());
        console.log("==========================================");
    }
}
