// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/GuessChampionV2.sol";
import "../src/WorldCupToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GuessChampionV2Test is Test {
    GuessChampionV2 gc;
    WorldCupToken wct;

    address owner = address(0xA11CE);
    address alice = address(0xA1);
    address bob = address(0xB0);
    address carol = address(0xC0);
    address dave = address(0xD0);

    uint8 constant ARGENTINA = 11;
    uint8 constant FRANCE = 33;
    uint8 constant BRAZIL = 12;

    // 单位糖：1 WCT
    uint256 constant ONE = 1 ether; // 1e18

    function setUp() public {
        // 2026-05-01：在 BET_DEADLINE (2026-06-11) 和 CLAIM_DEADLINE (2026-07-20) 之前
        vm.warp(1777939200);

        // 部署 WCT 和 GC
        wct = new WorldCupToken();
        vm.prank(owner);
        gc = new GuessChampionV2(IERC20(address(wct)));

        // 给四个用户领币 + 预授权
        _setupUser(alice);
        _setupUser(bob);
        _setupUser(carol);
        _setupUser(dave);
    }

    function _setupUser(address u) internal {
        vm.startPrank(u);
        wct.claimWelcome(); // 100 WCT
        wct.approve(address(gc), type(uint256).max);
        vm.stopPrank();
    }

    // ════════════════════════════════════════════════════════
    // 常量 / 部署
    // ════════════════════════════════════════════════════════

    function test_constants() public view {
        assertEq(gc.TEAM_COUNT(), 48);
        assertEq(gc.MIN_BET(), 1 ether);
        assertEq(gc.MAX_BET(), 100 ether);
        assertEq(gc.BET_DEADLINE(), 1781136000);
        assertEq(gc.owner(), owner);
        assertEq(address(gc.wct()), address(wct));
        assertFalse(gc.cancelled());
        assertEq(gc.champion(), 0);
    }

    function test_TeamsHash_matchesJsonFile() public view {
        bytes memory raw = vm.readFileBinary("data/teams.json");
        bytes32 actual = keccak256(raw);
        assertEq(actual, gc.TEAMS_HASH(), "data/teams.json drifted");
    }

    function test_doesNotAcceptETH() public {
        // 直接 send ETH → 失败（没有 receive/fallback）
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok, ) = address(gc).call{value: 1 ether}("");
        assertFalse(ok);
    }

    // ════════════════════════════════════════════════════════
    // bet()
    // ════════════════════════════════════════════════════════

    function test_bet_recordsBalances() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 50 * ONE);

        assertEq(gc.betAmounts(alice), 50 * ONE);
        assertEq(gc.teamOf(alice), ARGENTINA);
        assertEq(gc.totalPool(), 50 * ONE);
        assertEq(wct.balanceOf(address(gc)), 50 * ONE);
        assertEq(wct.balanceOf(alice), 50 * ONE); // 领了 100，下注 50，剩 50
    }

    function test_bet_firstBetPushesToBettors() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 10 * ONE);
        assertEq(gc.teamBettors(ARGENTINA, 0), alice);
    }

    function test_bet_topUpDoesNotDuplicateBettorEntry() public {
        vm.startPrank(alice);
        gc.bet(ARGENTINA, 10 * ONE);
        gc.bet(ARGENTINA, 20 * ONE);
        gc.bet(ARGENTINA, 30 * ONE);
        vm.stopPrank();

        assertEq(gc.betAmounts(alice), 60 * ONE);
        assertEq(gc.totalPool(), 60 * ONE);
        assertEq(gc.teamBettors(ARGENTINA, 0), alice);
        vm.expectRevert();
        gc.teamBettors(ARGENTINA, 1);
    }

    function test_bet_revertsOnSecondTeam() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 10 * ONE);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuessChampionV2.AlreadyBetOnDifferentTeam.selector,
                ARGENTINA
            )
        );
        gc.bet(FRANCE, 10 * ONE);
    }

    function test_bet_revertsOnTeamZero() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(GuessChampionV2.InvalidTeam.selector, uint8(0))
        );
        gc.bet(0, 10 * ONE);
    }

    function test_bet_revertsOnTeamOverMax() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(GuessChampionV2.InvalidTeam.selector, uint8(49))
        );
        gc.bet(49, 10 * ONE);
    }

    function test_bet_revertsBelowMin() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuessChampionV2.BetOutOfRange.selector,
                ONE / 2 // 0.5 WCT，低于 MIN_BET = 1 WCT
            )
        );
        gc.bet(ARGENTINA, ONE / 2);
    }

    function test_bet_revertsAboveMax() public {
        // alice 领了 100，先弄到 200 让她有钱押超 MAX_BET
        // bob 领 100 然后 transfer 给 alice
        vm.prank(bob);
        wct.transfer(alice, 100 * ONE);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuessChampionV2.BetOutOfRange.selector,
                101 * ONE
            )
        );
        gc.bet(ARGENTINA, 101 * ONE);
    }

    function test_bet_revertsAtDeadline() public {
        vm.warp(gc.BET_DEADLINE());
        vm.prank(alice);
        vm.expectRevert(GuessChampionV2.BettingClosed.selector);
        gc.bet(ARGENTINA, 10 * ONE);
    }

    function test_bet_revertsWhenCancelled() public {
        vm.prank(owner);
        gc.emergencyCancel();
        vm.prank(alice);
        vm.expectRevert(GuessChampionV2.AlreadyCancelled.selector);
        gc.bet(ARGENTINA, 10 * ONE);
    }

    function test_bet_revertsWithoutApproval() public {
        // eve 领了币但没 approve
        address eve = address(0xE0);
        vm.prank(eve);
        wct.claimWelcome();

        vm.prank(eve);
        vm.expectRevert(); // OZ ERC20InsufficientAllowance
        gc.bet(ARGENTINA, 10 * ONE);
    }

    function test_bet_revertsWithoutBalance() public {
        // eve approve 了但没领币 → 余额 0
        address eve = address(0xE0);
        vm.prank(eve);
        wct.approve(address(gc), type(uint256).max);

        vm.prank(eve);
        vm.expectRevert(); // OZ ERC20InsufficientBalance
        gc.bet(ARGENTINA, 10 * ONE);
    }

    function test_bet_emitsEvent() public {
        vm.expectEmit(true, true, false, true, address(gc));
        emit GuessChampionV2.BetPlaced(alice, ARGENTINA, 50 * ONE);
        vm.prank(alice);
        gc.bet(ARGENTINA, 50 * ONE);
    }

    // ════════════════════════════════════════════════════════
    // betWithPermit
    // ════════════════════════════════════════════════════════

    uint256 constant FRANK_PK = 0xF1A1;

    function _signPermit(
        uint256 pk,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        address signer = vm.addr(pk);
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, signer, spender, value, nonce, deadline)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", wct.DOMAIN_SEPARATOR(), structHash)
        );
        (v, r, s) = vm.sign(pk, digest);
    }

    function test_betWithPermit_oneTxFlow() public {
        address frank = vm.addr(FRANK_PK);
        // frank 领币（不 approve）
        vm.prank(frank);
        wct.claimWelcome();

        uint256 amount = 30 * ONE;
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            FRANK_PK, address(gc), amount, 0, deadline
        );

        // 一笔 tx：betWithPermit 内部 permit + transferFrom + 记账
        vm.prank(frank);
        gc.betWithPermit(ARGENTINA, amount, deadline, v, r, s);

        assertEq(gc.betAmounts(frank), amount);
        assertEq(gc.teamOf(frank), ARGENTINA);
        assertEq(wct.balanceOf(address(gc)), amount);
    }

    function test_betWithPermit_survivesPermitFrontRun() public {
        address frank = vm.addr(FRANK_PK);
        vm.prank(frank);
        wct.claimWelcome();

        uint256 amount = 30 * ONE;
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            FRANK_PK, address(gc), amount, 0, deadline
        );

        // 攻击者抢先用 frank 的签名调 wct.permit（让 nonce 用掉）
        wct.permit(frank, address(gc), amount, deadline, v, r, s);
        assertEq(wct.allowance(frank, address(gc)), amount);
        assertEq(wct.nonces(frank), 1);

        // frank 的 betWithPermit tx 现在包含的 permit 会因 nonce 错而 revert，
        // 但 try/catch 吞掉，下注照常继续（依赖已设的 allowance）
        vm.prank(frank);
        gc.betWithPermit(ARGENTINA, amount, deadline, v, r, s);

        assertEq(gc.betAmounts(frank), amount);
    }

    // ════════════════════════════════════════════════════════
    // emergencyCancel + refund
    // ════════════════════════════════════════════════════════

    function test_cancel_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(GuessChampionV2.NotOwner.selector);
        gc.emergencyCancel();
    }

    function test_cancel_doubleCancelReverts() public {
        vm.prank(owner);
        gc.emergencyCancel();
        vm.prank(owner);
        vm.expectRevert(GuessChampionV2.AlreadyCancelled.selector);
        gc.emergencyCancel();
    }

    function test_refund_returnsFullStake() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 40 * ONE);
        vm.prank(bob);
        gc.bet(FRANCE, 60 * ONE);

        vm.prank(owner);
        gc.emergencyCancel();

        uint256 aliceWctBefore = wct.balanceOf(alice);
        vm.prank(alice);
        gc.refund();

        assertEq(wct.balanceOf(alice) - aliceWctBefore, 40 * ONE);
        assertEq(gc.betAmounts(alice), 0);
        assertEq(gc.teamOf(alice), 0);
        // bob 不受影响
        assertEq(gc.betAmounts(bob), 60 * ONE);
        assertEq(gc.totalPool(), 60 * ONE);
    }

    function test_refund_revertsOnDoubleClaim() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 10 * ONE);
        vm.prank(owner);
        gc.emergencyCancel();
        vm.prank(alice);
        gc.refund();
        vm.prank(alice);
        vm.expectRevert(GuessChampionV2.NothingToRefund.selector);
        gc.refund();
    }

    function test_refundFor_paysToUserNotCaller() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 50 * ONE);
        vm.prank(owner);
        gc.emergencyCancel();

        uint256 aliceBefore = wct.balanceOf(alice);
        uint256 bobBefore = wct.balanceOf(bob);
        vm.prank(bob);
        gc.refundFor(alice);

        assertEq(wct.balanceOf(alice) - aliceBefore, 50 * ONE);
        assertEq(wct.balanceOf(bob), bobBefore); // bob 没多没少
    }

    function test_refundForBatch_processesMultiple() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 20 * ONE);
        vm.prank(bob);
        gc.bet(FRANCE, 30 * ONE);
        vm.prank(carol);
        gc.bet(BRAZIL, 40 * ONE);

        vm.prank(owner);
        gc.emergencyCancel();

        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = carol;

        uint256 aBefore = wct.balanceOf(alice);
        uint256 bBefore = wct.balanceOf(bob);
        uint256 cBefore = wct.balanceOf(carol);

        vm.prank(dave);
        gc.refundForBatch(users);

        assertEq(wct.balanceOf(alice) - aBefore, 20 * ONE);
        assertEq(wct.balanceOf(bob) - bBefore, 30 * ONE);
        assertEq(wct.balanceOf(carol) - cBefore, 40 * ONE);
        assertEq(gc.totalPool(), 0);
    }

    // ════════════════════════════════════════════════════════
    // declareChampion
    // ════════════════════════════════════════════════════════

    function test_declare_setsChampionAndWinnersTotal() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 30 * ONE);
        vm.prank(bob);
        gc.bet(ARGENTINA, 50 * ONE);
        vm.prank(carol);
        gc.bet(FRANCE, 20 * ONE);

        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        assertEq(gc.champion(), ARGENTINA);
        assertEq(gc.winnersTotal(), 80 * ONE);
        assertEq(gc.totalPool(), 100 * ONE);
        assertFalse(gc.cancelled());
    }

    function test_declare_noBettorsTriggersAutoCancel() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 50 * ONE);

        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(FRANCE); // 没人押法国

        assertTrue(gc.cancelled());
        assertEq(gc.champion(), 0);
        assertEq(gc.totalPool(), 50 * ONE);
    }

    function test_declare_autoCancelEnablesRefund() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 50 * ONE);

        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(FRANCE);

        uint256 aliceBefore = wct.balanceOf(alice);
        vm.prank(alice);
        gc.refund();
        assertEq(wct.balanceOf(alice) - aliceBefore, 50 * ONE);
    }

    // ════════════════════════════════════════════════════════
    // claim
    // ════════════════════════════════════════════════════════

    function test_claim_revertsForLoser() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 50 * ONE);
        vm.prank(bob);
        gc.bet(FRANCE, 50 * ONE);

        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        vm.prank(bob);
        vm.expectRevert(GuessChampionV2.NotWinner.selector);
        gc.claim();
    }

    function test_claim_singleWinnerGetsAllPool() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 50 * ONE);
        vm.prank(bob);
        gc.bet(FRANCE, 70 * ONE);
        vm.prank(carol);
        gc.bet(BRAZIL, 30 * ONE);

        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        uint256 aliceBefore = wct.balanceOf(alice);
        vm.prank(alice);
        gc.claim();

        // alice 一人独占 50+70+30 = 150 WCT 整个奖池
        assertEq(wct.balanceOf(alice) - aliceBefore, 150 * ONE);
    }

    function test_claim_multipleWinnersProportional() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 30 * ONE);
        vm.prank(bob);
        gc.bet(ARGENTINA, 70 * ONE);
        vm.prank(carol);
        gc.bet(FRANCE, 50 * ONE);

        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        uint256 aliceBefore = wct.balanceOf(alice);
        uint256 bobBefore = wct.balanceOf(bob);

        vm.prank(alice);
        gc.claim();
        vm.prank(bob);
        gc.claim();

        // 池 150，winnersTotal 100
        // alice: 150 * 30 / 100 = 45
        // bob:   150 * 70 / 100 = 105
        assertEq(wct.balanceOf(alice) - aliceBefore, 45 * ONE);
        assertEq(wct.balanceOf(bob) - bobBefore, 105 * ONE);
    }

    function test_claim_revertsOnDoubleClaim() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 50 * ONE);
        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        vm.prank(alice);
        gc.claim();
        vm.prank(alice);
        vm.expectRevert(GuessChampionV2.NotWinner.selector);
        gc.claim();
    }

    function test_claim_emitsEvent() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 50 * ONE);
        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        vm.expectEmit(true, false, false, true, address(gc));
        emit GuessChampionV2.Claimed(alice, 50 * ONE);
        vm.prank(alice);
        gc.claim();
    }

    function test_claimForBatch_processesMultipleWinners() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 30 * ONE);
        vm.prank(bob);
        gc.bet(ARGENTINA, 70 * ONE);
        vm.prank(carol);
        gc.bet(FRANCE, 100 * ONE);

        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        address[] memory winners = new address[](2);
        winners[0] = alice;
        winners[1] = bob;

        uint256 aBefore = wct.balanceOf(alice);
        uint256 bBefore = wct.balanceOf(bob);

        vm.prank(dave);
        gc.claimForBatch(winners);

        // 池 200，winnersTotal 100
        // alice: 200 * 30 / 100 = 60
        // bob:   200 * 70 / 100 = 140
        assertEq(wct.balanceOf(alice) - aBefore, 60 * ONE);
        assertEq(wct.balanceOf(bob) - bBefore, 140 * ONE);
    }

    // ════════════════════════════════════════════════════════
    // 不变量与端到端
    // ════════════════════════════════════════════════════════

    function test_balanceInvariant_holdsAfterBets() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 30 * ONE);
        vm.prank(bob);
        gc.bet(FRANCE, 50 * ONE);

        // wct.balanceOf(GC) >= totalPool
        assertGe(wct.balanceOf(address(gc)), gc.totalPool());
        assertEq(wct.balanceOf(address(gc)), gc.totalPool());
    }

    function test_e2e_fullHappyPath() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 40 * ONE);
        vm.prank(bob);
        gc.bet(ARGENTINA, 60 * ONE);
        vm.prank(carol);
        gc.bet(FRANCE, 50 * ONE);

        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        uint256 aliceBefore = wct.balanceOf(alice);
        uint256 bobBefore = wct.balanceOf(bob);

        vm.prank(alice);
        gc.claim();
        vm.prank(bob);
        gc.claim();

        // 池 150，winnersTotal 100
        // alice: 150 * 40 / 100 = 60
        // bob:   150 * 60 / 100 = 90
        assertEq(wct.balanceOf(alice) - aliceBefore, 60 * ONE);
        assertEq(wct.balanceOf(bob) - bobBefore, 90 * ONE);

        vm.prank(carol);
        vm.expectRevert(GuessChampionV2.NotWinner.selector);
        gc.claim();
    }

    function test_e2e_emergencyCancelFlow() public {
        vm.prank(alice);
        gc.bet(ARGENTINA, 40 * ONE);
        vm.prank(bob);
        gc.bet(FRANCE, 60 * ONE);

        vm.prank(owner);
        gc.emergencyCancel();

        uint256 aBefore = wct.balanceOf(alice);
        uint256 bBefore = wct.balanceOf(bob);

        vm.prank(alice);
        gc.refund();
        vm.prank(bob);
        gc.refund();

        assertEq(wct.balanceOf(alice) - aBefore, 40 * ONE);
        assertEq(wct.balanceOf(bob) - bBefore, 60 * ONE);
        assertEq(wct.balanceOf(address(gc)), 0);
    }
}
