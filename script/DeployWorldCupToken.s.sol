// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {WorldCupToken} from "../src/WorldCupToken.sol";

/// @title  WorldCupToken 部署脚本
/// @notice 用法：
///   anvil（本地）：
///     forge script script/DeployWorldCupToken.s.sol --rpc-url http://localhost:8545 --broadcast
///
///   测试网（Sepolia）：
///     forge script script/DeployWorldCupToken.s.sol \
///       --rpc-url $SEPOLIA_RPC_URL \
///       --private-key $PRIVATE_KEY \
///       --broadcast --verify \
///       --etherscan-api-key $ETHERSCAN_API_KEY
contract DeployWorldCupToken is Script {
    function run() external returns (WorldCupToken wct) {
        vm.startBroadcast();
        wct = new WorldCupToken();
        vm.stopBroadcast();

        console.log("==========================================");
        console.log("WorldCupToken deployed");
        console.log("  address:        ", address(wct));
        console.log("  name:           ", wct.name());
        console.log("  symbol:         ", wct.symbol());
        console.log("  decimals:       ", wct.decimals());
        console.log("  WELCOME_AMOUNT: ", wct.WELCOME_AMOUNT());
        console.log("  CLAIM_DEADLINE: ", wct.CLAIM_DEADLINE());
        console.log("  DOMAIN_SEPARATOR:");
        console.logBytes32(wct.DOMAIN_SEPARATOR());
        console.log("==========================================");
    }
}
