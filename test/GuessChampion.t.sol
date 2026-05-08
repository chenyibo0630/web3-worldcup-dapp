// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/GuessChampion.sol";

contract GuessChampionTest is Test {
    GuessChampion gc;

    address owner = address(0xA11CE);
    address alice = address(0xA1);
    address bob = address(0xB0);
    address carol = address(0xC0);
    address dave = address(0xD0);

    // 几个常用 teamId
    uint8 constant ARGENTINA = 11;
    uint8 constant FRANCE = 33;
    uint8 constant BRAZIL = 12;

    function setUp() public {
        // 把测试时间设到 2026-05-01，确保在 BET_DEADLINE (2026-06-11) 之前
        vm.warp(1777939200);

        vm.prank(owner);
        gc = new GuessChampion();

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
        vm.deal(dave, 100 ether);
    }

    // ════════════════════════════════════════════════════════
    // 基本部署 / 常量
    // ════════════════════════════════════════════════════════

    function test_constants() public view {
        assertEq(gc.TEAM_COUNT(), 48);
        assertEq(gc.MIN_BET(), 0.01 ether);
        assertEq(gc.MAX_BET(), 1 ether);
        assertEq(gc.BET_DEADLINE(), 1781136000);
        assertEq(gc.owner(), owner);
        assertFalse(gc.cancelled());
        assertEq(gc.champion(), 0);
    }

    // ════════════════════════════════════════════════════════
    // bet()
    // ════════════════════════════════════════════════════════

    function test_bet_recordsBalances() public {
        vm.prank(alice);
        gc.bet{value: 0.5 ether}(ARGENTINA);

        assertEq(gc.betAmounts(alice), 0.5 ether);
        assertEq(gc.teamOf(alice), ARGENTINA);
        assertEq(gc.totalPool(), 0.5 ether);
        assertEq(address(gc).balance, 0.5 ether);
    }

    function test_bet_firstBetPushesToBettors() public {
        vm.prank(alice);
        gc.bet{value: 0.1 ether}(ARGENTINA);

        assertEq(gc.teamBettors(ARGENTINA, 0), alice);
    }

    function test_bet_topUpDoesNotDuplicateBettorEntry() public {
        vm.startPrank(alice);
        gc.bet{value: 0.1 ether}(ARGENTINA);
        gc.bet{value: 0.2 ether}(ARGENTINA);
        gc.bet{value: 0.3 ether}(ARGENTINA);
        vm.stopPrank();

        // 累加金额
        assertEq(gc.betAmounts(alice), 0.6 ether);
        assertEq(gc.totalPool(), 0.6 ether);
        // bettors 列表只有 alice 一次
        assertEq(gc.teamBettors(ARGENTINA, 0), alice);
        // 数组长度也是 1（用 vm.expectRevert 测越界，间接验证）
        vm.expectRevert();
        gc.teamBettors(ARGENTINA, 1);
    }

    function test_bet_revertsOnSecondTeam() public {
        vm.prank(alice);
        gc.bet{value: 0.1 ether}(ARGENTINA);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuessChampion.AlreadyBetOnDifferentTeam.selector,
                ARGENTINA
            )
        );
        gc.bet{value: 0.1 ether}(FRANCE);
    }

    function test_bet_keepsUsersSeparate() public {
        vm.prank(alice);
        gc.bet{value: 0.2 ether}(ARGENTINA);
        vm.prank(bob);
        gc.bet{value: 0.3 ether}(FRANCE);

        assertEq(gc.teamOf(alice), ARGENTINA);
        assertEq(gc.teamOf(bob), FRANCE);
        assertEq(gc.betAmounts(alice), 0.2 ether);
        assertEq(gc.betAmounts(bob), 0.3 ether);
        assertEq(gc.totalPool(), 0.5 ether);
    }

    function test_bet_revertsOnTeamZero() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(GuessChampion.InvalidTeam.selector, uint8(0))
        );
        gc.bet{value: 0.1 ether}(0);
    }

    function test_bet_revertsOnTeamOverMax() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(GuessChampion.InvalidTeam.selector, uint8(49))
        );
        gc.bet{value: 0.1 ether}(49);
    }

    function test_bet_revertsBelowMin() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuessChampion.BetOutOfRange.selector,
                0.001 ether
            )
        );
        gc.bet{value: 0.001 ether}(ARGENTINA);
    }

    function test_bet_revertsAboveMax() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuessChampion.BetOutOfRange.selector,
                2 ether
            )
        );
        gc.bet{value: 2 ether}(ARGENTINA);
    }

    function test_bet_revertsAtDeadline() public {
        vm.warp(gc.BET_DEADLINE());
        vm.prank(alice);
        vm.expectRevert(GuessChampion.BettingClosed.selector);
        gc.bet{value: 0.1 ether}(ARGENTINA);
    }

    function test_bet_revertsAfterDeadline() public {
        vm.warp(gc.BET_DEADLINE() + 1 days);
        vm.prank(alice);
        vm.expectRevert(GuessChampion.BettingClosed.selector);
        gc.bet{value: 0.1 ether}(ARGENTINA);
    }

    function test_bet_revertsWhenCancelled() public {
        vm.prank(owner);
        gc.emergencyCancel();
        vm.prank(alice);
        vm.expectRevert(GuessChampion.AlreadyCancelled.selector);
        gc.bet{value: 0.1 ether}(ARGENTINA);
    }

    function test_bet_emitsEvent() public {
        vm.expectEmit(true, true, false, true, address(gc));
        emit GuessChampion.BetPlaced(alice, ARGENTINA, 0.5 ether);
        vm.prank(alice);
        gc.bet{value: 0.5 ether}(ARGENTINA);
    }

    // ════════════════════════════════════════════════════════
    // emergencyCancel()
    // ════════════════════════════════════════════════════════

    function test_cancel_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(GuessChampion.NotOwner.selector);
        gc.emergencyCancel();
    }

    function test_cancel_setsFlag() public {
        vm.prank(owner);
        gc.emergencyCancel();
        assertTrue(gc.cancelled());
    }

    function test_cancel_emitsEvent() public {
        vm.expectEmit(false, false, false, false, address(gc));
        emit GuessChampion.Cancelled();
        vm.prank(owner);
        gc.emergencyCancel();
    }

    function test_cancel_revertsAfterDraw() public {
        vm.prank(alice);
        gc.bet{value: 0.1 ether}(ARGENTINA);
        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        vm.prank(owner);
        vm.expectRevert(GuessChampion.AlreadyDrawn.selector);
        gc.emergencyCancel();
    }

    function test_cancel_doubleCancelReverts() public {
        vm.prank(owner);
        gc.emergencyCancel();
        vm.prank(owner);
        vm.expectRevert(GuessChampion.AlreadyCancelled.selector);
        gc.emergencyCancel();
    }

    // ════════════════════════════════════════════════════════
    // refund / refundFor / refundForBatch
    // ════════════════════════════════════════════════════════

    function test_refund_revertsBeforeCancel() public {
        vm.prank(alice);
        gc.bet{value: 0.1 ether}(ARGENTINA);
        vm.prank(alice);
        vm.expectRevert(GuessChampion.NotCancelled.selector);
        gc.refund();
    }

    function test_refund_returnsFullStake() public {
        vm.prank(alice);
        gc.bet{value: 0.4 ether}(ARGENTINA);
        vm.prank(bob);
        gc.bet{value: 0.6 ether}(FRANCE);

        vm.prank(owner);
        gc.emergencyCancel();

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        gc.refund();

        assertEq(alice.balance - aliceBefore, 0.4 ether);
        assertEq(gc.betAmounts(alice), 0);
        assertEq(gc.teamOf(alice), 0);
        // bob 不受影响
        assertEq(gc.betAmounts(bob), 0.6 ether);
        assertEq(gc.totalPool(), 0.6 ether);
    }

    function test_refund_revertsOnDoubleClaim() public {
        vm.prank(alice);
        gc.bet{value: 0.1 ether}(ARGENTINA);
        vm.prank(owner);
        gc.emergencyCancel();

        vm.prank(alice);
        gc.refund();
        vm.prank(alice);
        vm.expectRevert(GuessChampion.NothingToRefund.selector);
        gc.refund();
    }

    function test_refund_revertsForNonBettor() public {
        vm.prank(owner);
        gc.emergencyCancel();
        vm.prank(alice);
        vm.expectRevert(GuessChampion.NothingToRefund.selector);
        gc.refund();
    }

    function test_refund_emitsEvent() public {
        vm.prank(alice);
        gc.bet{value: 0.5 ether}(ARGENTINA);
        vm.prank(owner);
        gc.emergencyCancel();

        vm.expectEmit(true, false, false, true, address(gc));
        emit GuessChampion.Refunded(alice, 0.5 ether);
        vm.prank(alice);
        gc.refund();
    }

    function test_refundFor_paysToUserNotCaller() public {
        vm.prank(alice);
        gc.bet{value: 0.5 ether}(ARGENTINA);
        vm.prank(owner);
        gc.emergencyCancel();

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;

        // bob 替 alice 触发退款
        vm.prank(bob);
        gc.refundFor(alice);

        // 钱进 alice 钱包，bob 只付 gas
        assertEq(alice.balance - aliceBefore, 0.5 ether);
        assertEq(bobBefore, bob.balance);
    }

    function test_refundForBatch_processesMultiple() public {
        vm.prank(alice);
        gc.bet{value: 0.2 ether}(ARGENTINA);
        vm.prank(bob);
        gc.bet{value: 0.3 ether}(FRANCE);
        vm.prank(carol);
        gc.bet{value: 0.4 ether}(BRAZIL);

        vm.prank(owner);
        gc.emergencyCancel();

        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = carol;

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        uint256 carolBefore = carol.balance;

        vm.prank(dave);
        gc.refundForBatch(users);

        assertEq(alice.balance - aliceBefore, 0.2 ether);
        assertEq(bob.balance - bobBefore, 0.3 ether);
        assertEq(carol.balance - carolBefore, 0.4 ether);
        assertEq(gc.totalPool(), 0);
    }

    function test_refund_decrementsTotalPool() public {
        vm.prank(alice);
        gc.bet{value: 0.4 ether}(ARGENTINA);
        vm.prank(bob);
        gc.bet{value: 0.6 ether}(FRANCE);
        assertEq(gc.totalPool(), 1 ether);

        vm.prank(owner);
        gc.emergencyCancel();

        vm.prank(alice);
        gc.refund();
        assertEq(gc.totalPool(), 0.6 ether);

        vm.prank(bob);
        gc.refund();
        assertEq(gc.totalPool(), 0);
    }

    // ════════════════════════════════════════════════════════
    // declareChampion()
    // ════════════════════════════════════════════════════════

    function test_declare_onlyOwner() public {
        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(alice);
        vm.expectRevert(GuessChampion.NotOwner.selector);
        gc.declareChampion(ARGENTINA);
    }

    function test_declare_revertsBeforeDeadline() public {
        vm.prank(owner);
        vm.expectRevert(GuessChampion.NotDrawable.selector);
        gc.declareChampion(ARGENTINA);
    }

    function test_declare_revertsOnInvalidTeam() public {
        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(GuessChampion.InvalidTeam.selector, uint8(0))
        );
        gc.declareChampion(0);
    }

    function test_declare_revertsAfterCancel() public {
        vm.prank(owner);
        gc.emergencyCancel();
        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        vm.expectRevert(GuessChampion.AlreadyCancelled.selector);
        gc.declareChampion(ARGENTINA);
    }

    function test_declare_doubleDrawReverts() public {
        vm.prank(alice);
        gc.bet{value: 0.1 ether}(ARGENTINA);
        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);
        vm.prank(owner);
        vm.expectRevert(GuessChampion.AlreadyDrawn.selector);
        gc.declareChampion(ARGENTINA);
    }

    function test_declare_setsChampionAndWinnersTotal() public {
        vm.prank(alice);
        gc.bet{value: 0.3 ether}(ARGENTINA);
        vm.prank(bob);
        gc.bet{value: 0.5 ether}(ARGENTINA);
        vm.prank(carol);
        gc.bet{value: 0.2 ether}(FRANCE);

        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        assertEq(gc.champion(), ARGENTINA);
        assertEq(gc.winnersTotal(), 0.8 ether);
        assertEq(gc.totalPool(), 1 ether); // 不动，作快照
        assertFalse(gc.cancelled());
    }

    function test_declare_noBettorsTriggersAutoCancel() public {
        vm.prank(alice);
        gc.bet{value: 0.5 ether}(ARGENTINA);
        // 没人押 FRANCE
        vm.warp(gc.BET_DEADLINE() + 1);

        vm.expectEmit(false, false, false, false, address(gc));
        emit GuessChampion.Cancelled();

        vm.prank(owner);
        gc.declareChampion(FRANCE);

        assertTrue(gc.cancelled());
        assertEq(gc.champion(), 0); // 没设
        assertEq(gc.totalPool(), 0.5 ether); // 不动，等 refund
    }

    function test_declare_autoCancelEnablesRefund() public {
        // alice 押了 ARGENTINA
        vm.prank(alice);
        gc.bet{value: 0.5 ether}(ARGENTINA);

        // owner 宣布 FRANCE 夺冠（无人押）→ 自动取消
        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(FRANCE);

        // alice 走 refund 通道拿回本金
        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        gc.refund();
        assertEq(alice.balance - aliceBefore, 0.5 ether);
    }

    function test_declare_emitsDrawn() public {
        vm.prank(alice);
        gc.bet{value: 0.5 ether}(ARGENTINA);
        vm.warp(gc.BET_DEADLINE() + 1);

        vm.expectEmit(true, false, false, true, address(gc));
        emit GuessChampion.Drawn(ARGENTINA, 0.5 ether, 0.5 ether);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);
    }

    // ════════════════════════════════════════════════════════
    // claim / claimFor / claimForBatch
    // ════════════════════════════════════════════════════════

    function test_claim_revertsBeforeDraw() public {
        vm.prank(alice);
        gc.bet{value: 0.5 ether}(ARGENTINA);
        vm.prank(alice);
        vm.expectRevert(GuessChampion.NotDrawn.selector);
        gc.claim();
    }

    function test_claim_revertsWhenCancelled() public {
        vm.prank(alice);
        gc.bet{value: 0.5 ether}(ARGENTINA);
        vm.prank(owner);
        gc.emergencyCancel();
        vm.prank(alice);
        vm.expectRevert(GuessChampion.AlreadyCancelled.selector);
        gc.claim();
    }

    function test_claim_revertsForLoser() public {
        vm.prank(alice);
        gc.bet{value: 0.5 ether}(ARGENTINA);
        vm.prank(bob);
        gc.bet{value: 0.5 ether}(FRANCE);
        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        // bob 押的是法国，不是冠军
        vm.prank(bob);
        vm.expectRevert(GuessChampion.NotWinner.selector);
        gc.claim();
    }

    function test_claim_singleWinnerGetsAllPool() public {
        vm.prank(alice);
        gc.bet{value: 0.5 ether}(ARGENTINA);
        vm.prank(bob);
        gc.bet{value: 0.7 ether}(FRANCE);
        vm.prank(carol);
        gc.bet{value: 0.3 ether}(BRAZIL);

        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        gc.claim();

        // alice 一人独占 0.5+0.7+0.3 = 1.5 ether 整个奖池
        assertEq(alice.balance - aliceBefore, 1.5 ether);
    }

    function test_claim_multipleWinnersProportional() public {
        // alice 押 0.3，bob 押 0.7，都押 ARGENTINA（赢）
        // carol 押 0.5 给 FRANCE（输）
        // 总池 1.5，winnersTotal = 1.0
        vm.prank(alice);
        gc.bet{value: 0.3 ether}(ARGENTINA);
        vm.prank(bob);
        gc.bet{value: 0.7 ether}(ARGENTINA);
        vm.prank(carol);
        gc.bet{value: 0.5 ether}(FRANCE);

        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;

        vm.prank(alice);
        gc.claim();
        vm.prank(bob);
        gc.claim();

        // alice 占 winnersTotal 30%，应得 1.5 * 0.3/1.0 = 0.45 ether
        // bob 占 70%，应得 1.5 * 0.7/1.0 = 1.05 ether
        assertEq(alice.balance - aliceBefore, 0.45 ether);
        assertEq(bob.balance - bobBefore, 1.05 ether);
    }

    function test_claim_revertsOnDoubleClaim() public {
        vm.prank(alice);
        gc.bet{value: 0.5 ether}(ARGENTINA);
        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        vm.prank(alice);
        gc.claim();
        vm.prank(alice);
        // 第二次：teamOf[alice] 已被 delete，触发 NotWinner
        vm.expectRevert(GuessChampion.NotWinner.selector);
        gc.claim();
    }

    function test_claim_emitsEvent() public {
        vm.prank(alice);
        gc.bet{value: 0.5 ether}(ARGENTINA);
        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        vm.expectEmit(true, false, false, true, address(gc));
        emit GuessChampion.Claimed(alice, 0.5 ether);
        vm.prank(alice);
        gc.claim();
    }

    function test_claimFor_paysToUserNotCaller() public {
        vm.prank(alice);
        gc.bet{value: 0.5 ether}(ARGENTINA);
        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        uint256 aliceBefore = alice.balance;
        // bob 替 alice 调
        vm.prank(bob);
        gc.claimFor(alice);
        assertEq(alice.balance - aliceBefore, 0.5 ether);
    }

    function test_claimForBatch_processesMultipleWinners() public {
        vm.prank(alice);
        gc.bet{value: 0.3 ether}(ARGENTINA);
        vm.prank(bob);
        gc.bet{value: 0.7 ether}(ARGENTINA);
        vm.prank(carol);
        gc.bet{value: 1 ether}(FRANCE);

        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        address[] memory winners = new address[](2);
        winners[0] = alice;
        winners[1] = bob;

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;

        vm.prank(dave);
        gc.claimForBatch(winners);

        // 池 2 ETH，winnersTotal 1 ETH
        // alice：2 * 0.3 / 1 = 0.6
        // bob：2 * 0.7 / 1 = 1.4
        assertEq(alice.balance - aliceBefore, 0.6 ether);
        assertEq(bob.balance - bobBefore, 1.4 ether);
    }

    // ════════════════════════════════════════════════════════
    // 数学精度验证
    // ════════════════════════════════════════════════════════

    function test_payout_precisionLoss_isMinimal() public {
        // 故意制造除不尽的情况：池 7 ether，3 个赢家各 1 ether
        vm.prank(alice);
        gc.bet{value: 1 ether}(ARGENTINA);
        vm.prank(bob);
        gc.bet{value: 1 ether}(ARGENTINA);
        vm.prank(carol);
        gc.bet{value: 1 ether}(ARGENTINA);
        vm.prank(dave);
        gc.bet{value: 1 ether}(FRANCE);
        // 第 5 个用户也押 FRANCE 让池更不整除
        address eve = address(0xE0);
        vm.deal(eve, 10 ether);
        vm.prank(eve);
        gc.bet{value: 1 ether}(FRANCE);
        // 加押到池 = 7
        vm.prank(eve);
        gc.bet{value: 1 ether}(FRANCE);
        vm.prank(dave);
        gc.bet{value: 1 ether}(FRANCE);

        // 池 = 7 ether, ARGENTINA 总押 = 3 ether
        assertEq(gc.totalPool(), 7 ether);

        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        vm.prank(alice);
        gc.claim();
        vm.prank(bob);
        gc.claim();
        vm.prank(carol);
        gc.claim();

        // 每人应得 7 * 1 / 3 = 2.333... ether → 截断为 2333333333333333333 wei
        // 三人合计 6999999999999999999 wei → dust = 1 wei
        assertEq(address(gc).balance, 1); // 残留 1 wei dust
    }

    // ════════════════════════════════════════════════════════
    // 端到端集成场景
    // ════════════════════════════════════════════════════════

    function test_e2e_fullHappyPath() public {
        vm.prank(alice);
        gc.bet{value: 0.4 ether}(ARGENTINA);
        vm.prank(bob);
        gc.bet{value: 0.6 ether}(ARGENTINA);
        vm.prank(carol);
        gc.bet{value: 0.5 ether}(FRANCE);

        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(ARGENTINA);

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;

        vm.prank(alice);
        gc.claim();
        vm.prank(bob);
        gc.claim();

        // 池 1.5，winnersTotal 1.0
        // alice: 1.5 * 0.4 / 1.0 = 0.6
        // bob:   1.5 * 0.6 / 1.0 = 0.9
        assertEq(alice.balance - aliceBefore, 0.6 ether);
        assertEq(bob.balance - bobBefore, 0.9 ether);

        // carol 是输家
        vm.prank(carol);
        vm.expectRevert(GuessChampion.NotWinner.selector);
        gc.claim();
    }

    function test_e2e_emergencyCancelFlow() public {
        vm.prank(alice);
        gc.bet{value: 0.4 ether}(ARGENTINA);
        vm.prank(bob);
        gc.bet{value: 0.6 ether}(FRANCE);

        vm.prank(owner);
        gc.emergencyCancel();

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;

        vm.prank(alice);
        gc.refund();
        vm.prank(bob);
        gc.refund();

        assertEq(alice.balance - aliceBefore, 0.4 ether);
        assertEq(bob.balance - bobBefore, 0.6 ether);
        assertEq(address(gc).balance, 0);
    }

    function test_e2e_autoCancelOnNoWinner() public {
        vm.prank(alice);
        gc.bet{value: 0.4 ether}(ARGENTINA);
        vm.prank(bob);
        gc.bet{value: 0.6 ether}(FRANCE);
        // 没人押 BRAZIL

        vm.warp(gc.BET_DEADLINE() + 1);
        vm.prank(owner);
        gc.declareChampion(BRAZIL); // 触发自动取消

        assertTrue(gc.cancelled());

        // 所有人都能 refund
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        vm.prank(alice);
        gc.refund();
        vm.prank(bob);
        gc.refund();

        assertEq(alice.balance - aliceBefore, 0.4 ether);
        assertEq(bob.balance - bobBefore, 0.6 ether);
    }
}
