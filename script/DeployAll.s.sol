// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WorldCupToken} from "../src/WorldCupToken.sol";
import {GuessChampionV2} from "../src/GuessChampionV2.sol";

/// @title  一次性部署 WCT + GuessChampionV2
/// @notice 用法：
///   forge script script/DeployAll.s.sol \
///     --rpc-url http://localhost:8545 --broadcast
contract DeployAll is Script {
    function run() external returns (WorldCupToken wct, GuessChampionV2 gc) {
        // 部署前自检 TEAMS_HASH
        bytes memory raw = vm.readFileBinary("data/teams.json");
        bytes32 expected = keccak256(raw);

        vm.startBroadcast();
        wct = new WorldCupToken();
        gc = new GuessChampionV2(IERC20(address(wct)));
        vm.stopBroadcast();

        require(gc.TEAMS_HASH() == expected, "TEAMS_HASH drift");

        console.log("==========================================");
        console.log("DeployAll complete");
        console.log("  WCT: ", address(wct));
        console.log("  GC:  ", address(gc));
        console.log("==========================================");
    }
}
