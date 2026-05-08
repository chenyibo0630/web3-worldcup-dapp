// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/GuessChampion.sol";

contract GuessChampionTest is Test {
    GuessChampion gc;

    address owner = address(0xA11CE);
    address alice = address(0xA1);
    address bob = address(0xB0);

    function setUp() public {
        // 把测试时间设到 2026-05-01，确保在 BET_DEADLINE 之前
        vm.warp(1777939200);

        vm.prank(owner);
        gc = new GuessChampion();

        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
    }

    function test_constants() public view {
        assertEq(gc.TEAM_COUNT(), 48);
        assertEq(gc.MIN_BET(), 1 ether);
        assertEq(gc.MAX_BET(), 100 ether);
        assertEq(gc.BET_DEADLINE(), 1781136000);
        assertEq(gc.CLAIM_DEADLINE(), 1784678400);
        // 必要的不变量：下注截止必须早于领奖截止
        assertLt(gc.BET_DEADLINE(), gc.CLAIM_DEADLINE());
    }

    function test_bet_recordsBalances() public {
        vm.prank(alice);
        gc.bet{value: 5 ether}(11); // Argentina

        assertEq(gc.betsOf(alice, 11), 5 ether);
        assertEq(gc.teamTotal(11), 5 ether);
        assertEq(gc.totalPool(), 5 ether);
        assertEq(address(gc).balance, 5 ether);
    }

    function test_bet_accumulatesSameTeam() public {
        vm.startPrank(alice);
        gc.bet{value: 2 ether}(11);
        gc.bet{value: 3 ether}(11);
        vm.stopPrank();

        assertEq(gc.betsOf(alice, 11), 5 ether);
        assertEq(gc.teamTotal(11), 5 ether);
    }

    function test_bet_keepsTeamsSeparate() public {
        vm.prank(alice);
        gc.bet{value: 2 ether}(11); // Argentina
        vm.prank(alice);
        gc.bet{value: 3 ether}(33); // France

        assertEq(gc.betsOf(alice, 11), 2 ether);
        assertEq(gc.betsOf(alice, 33), 3 ether);
        assertEq(gc.totalPool(), 5 ether);
    }

    function test_bet_keepsUsersSeparate() public {
        vm.prank(alice);
        gc.bet{value: 2 ether}(11);
        vm.prank(bob);
        gc.bet{value: 3 ether}(11);

        assertEq(gc.betsOf(alice, 11), 2 ether);
        assertEq(gc.betsOf(bob, 11), 3 ether);
        assertEq(gc.teamTotal(11), 5 ether);
    }

    function test_bet_emitsEvent() public {
        vm.expectEmit(true, true, false, true, address(gc));
        emit GuessChampion.BetPlaced(alice, 11, 5 ether);
        vm.prank(alice);
        gc.bet{value: 5 ether}(11);
    }

    function test_bet_revertsOnTeamZero() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(GuessChampion.InvalidTeam.selector, uint8(0)));
        gc.bet{value: 1 ether}(0);
    }

    function test_bet_revertsOnTeamOutOfRange() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(GuessChampion.InvalidTeam.selector, uint8(49)));
        gc.bet{value: 1 ether}(49);
    }

    function test_bet_revertsBelowMin() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(GuessChampion.BetOutOfRange.selector, 0.5 ether)
        );
        gc.bet{value: 0.5 ether}(11);
    }

    function test_bet_revertsAboveMax() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(GuessChampion.BetOutOfRange.selector, 101 ether)
        );
        gc.bet{value: 101 ether}(11);
    }

    function test_bet_revertsAtBetDeadline() public {
        vm.warp(gc.BET_DEADLINE());
        vm.prank(alice);
        vm.expectRevert(GuessChampion.BettingClosed.selector);
        gc.bet{value: 1 ether}(11);
    }

    function test_bet_revertsBetweenDeadlines() public {
        // 已过开赛日但还没到领奖截止——同样不能下注
        vm.warp(gc.BET_DEADLINE() + 1 days);
        vm.prank(alice);
        vm.expectRevert(GuessChampion.BettingClosed.selector);
        gc.bet{value: 1 ether}(11);
    }

    // ─── 紧急取消 / 退款 ─────────────────────────────────────

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

    function test_cancel_blocksBet() public {
        vm.prank(owner);
        gc.emergencyCancel();
        vm.prank(alice);
        vm.expectRevert(GuessChampion.AlreadyCancelled.selector);
        gc.bet{value: 1 ether}(11);
    }

    function test_cancel_doubleCancelReverts() public {
        vm.prank(owner);
        gc.emergencyCancel();
        vm.prank(owner);
        vm.expectRevert(GuessChampion.AlreadyCancelled.selector);
        gc.emergencyCancel();
    }

    function test_refund_revertsBeforeCancel() public {
        vm.prank(alice);
        gc.bet{value: 1 ether}(11);
        vm.prank(alice);
        vm.expectRevert(GuessChampion.NotCancelled.selector);
        gc.refund();
    }

    function test_refund_returnsFullStakeAcrossTeams() public {
        // alice 在 3 支不同队上各下注，bob 在另一支
        vm.startPrank(alice);
        gc.bet{value: 2 ether}(11);  // Argentina
        gc.bet{value: 3 ether}(33);  // France
        gc.bet{value: 1 ether}(12);  // Brazil
        vm.stopPrank();
        vm.prank(bob);
        gc.bet{value: 5 ether}(11);

        vm.prank(owner);
        gc.emergencyCancel();

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        gc.refund();

        // alice 拿回 2+3+1 = 6 ether
        assertEq(alice.balance - aliceBefore, 6 ether);
        // alice 的下注全部清零
        assertEq(gc.betsOf(alice, 11), 0);
        assertEq(gc.betsOf(alice, 33), 0);
        assertEq(gc.betsOf(alice, 12), 0);
        // bob 的下注不受影响
        assertEq(gc.betsOf(bob, 11), 5 ether);
        // teamTotal 仅扣除 alice 部分
        assertEq(gc.teamTotal(11), 5 ether);
        assertEq(gc.teamTotal(33), 0);
        assertEq(gc.totalPool(), 5 ether);
    }

    function test_refund_revertsOnDoubleClaim() public {
        vm.prank(alice);
        gc.bet{value: 2 ether}(11);
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
}
