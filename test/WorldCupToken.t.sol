// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/WorldCupToken.sol";

contract WorldCupTokenTest is Test {
    WorldCupToken wct;

    address alice = address(0xA1);
    address bob = address(0xB0);

    // 用一个已知私钥造一个 alice 地址，测 permit 时需要它来签名
    uint256 constant ALICE_PK = 0xA11CE;
    address aliceFromPk;

    function setUp() public {
        // 锁定到 2026-05-01（在 CLAIM_DEADLINE 之前）
        vm.warp(1777939200);

        wct = new WorldCupToken();
        aliceFromPk = vm.addr(ALICE_PK);
    }

    // ════════════════════════════════════════════════════════
    // 常量 / 元数据
    // ════════════════════════════════════════════════════════

    function test_constants() public view {
        assertEq(wct.name(), "WorldCup Token");
        assertEq(wct.symbol(), "WCT");
        assertEq(wct.decimals(), 18);
        assertEq(wct.WELCOME_AMOUNT(), 100 * 10 ** 18);
        assertEq(wct.CLAIM_DEADLINE(), 1784505600);
        assertEq(wct.totalSupply(), 0);
    }

    // ════════════════════════════════════════════════════════
    // claimWelcome
    // ════════════════════════════════════════════════════════

    function test_claim_firstClaimMints100() public {
        vm.prank(alice);
        wct.claimWelcome();

        assertEq(wct.balanceOf(alice), 100 * 10 ** 18);
        assertTrue(wct.hasClaimed(alice));
        assertEq(wct.totalSupply(), 100 * 10 ** 18);
    }

    function test_claim_secondClaimReverts() public {
        vm.prank(alice);
        wct.claimWelcome();

        vm.prank(alice);
        vm.expectRevert(WorldCupToken.AlreadyClaimed.selector);
        wct.claimWelcome();
    }

    function test_claim_afterDeadlineReverts() public {
        vm.warp(wct.CLAIM_DEADLINE());
        vm.prank(alice);
        vm.expectRevert(WorldCupToken.ClaimWindowClosed.selector);
        wct.claimWelcome();
    }

    function test_claim_oneSecondBeforeDeadlineWorks() public {
        vm.warp(wct.CLAIM_DEADLINE() - 1);
        vm.prank(alice);
        wct.claimWelcome();
        assertEq(wct.balanceOf(alice), 100 * 10 ** 18);
    }

    function test_claim_emitsEvent() public {
        vm.expectEmit(true, false, false, true, address(wct));
        emit WorldCupToken.WelcomeClaimed(alice, 100 * 10 ** 18);
        vm.prank(alice);
        wct.claimWelcome();
    }

    function test_claim_differentUsersIndependent() public {
        vm.prank(alice);
        wct.claimWelcome();
        vm.prank(bob);
        wct.claimWelcome();

        assertEq(wct.balanceOf(alice), 100 * 10 ** 18);
        assertEq(wct.balanceOf(bob), 100 * 10 ** 18);
        assertEq(wct.totalSupply(), 200 * 10 ** 18);
    }

    // ════════════════════════════════════════════════════════
    // 标准 ERC20 行为
    // ════════════════════════════════════════════════════════

    function test_transfer_standard() public {
        vm.prank(alice);
        wct.claimWelcome();

        vm.prank(alice);
        wct.transfer(bob, 30 * 10 ** 18);

        assertEq(wct.balanceOf(alice), 70 * 10 ** 18);
        assertEq(wct.balanceOf(bob), 30 * 10 ** 18);
    }

    function test_approveAndTransferFrom() public {
        vm.prank(alice);
        wct.claimWelcome();

        vm.prank(alice);
        wct.approve(bob, 40 * 10 ** 18);
        assertEq(wct.allowance(alice, bob), 40 * 10 ** 18);

        vm.prank(bob);
        wct.transferFrom(alice, bob, 40 * 10 ** 18);
        assertEq(wct.balanceOf(alice), 60 * 10 ** 18);
        assertEq(wct.balanceOf(bob), 40 * 10 ** 18);
        assertEq(wct.allowance(alice, bob), 0);
    }

    // ════════════════════════════════════════════════════════
    // ERC20Permit (EIP-2612)
    // ════════════════════════════════════════════════════════

    /// @dev 帮 ALICE_PK 对 permit 类型化数据签名
    function _signPermit(
        address owner_,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner_, spender, value, nonce, deadline)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", wct.DOMAIN_SEPARATOR(), structHash)
        );
        (v, r, s) = vm.sign(ALICE_PK, digest);
    }

    function test_permit_setsAllowance() public {
        // alice 先领币
        vm.prank(aliceFromPk);
        wct.claimWelcome();

        uint256 amount = 50 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            aliceFromPk, bob, amount, wct.nonces(aliceFromPk), deadline
        );

        // 任何人（这里是 bob）都能提交签名
        vm.prank(bob);
        wct.permit(aliceFromPk, bob, amount, deadline, v, r, s);

        assertEq(wct.allowance(aliceFromPk, bob), amount);
        assertEq(wct.nonces(aliceFromPk), 1);
    }

    function test_permit_replayReverts() public {
        vm.prank(aliceFromPk);
        wct.claimWelcome();

        uint256 amount = 50 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            aliceFromPk, bob, amount, wct.nonces(aliceFromPk), deadline
        );

        wct.permit(aliceFromPk, bob, amount, deadline, v, r, s);

        // 同一签名再用 → nonce 已被消费 → 恢复出错误的 signer → revert
        vm.expectRevert();
        wct.permit(aliceFromPk, bob, amount, deadline, v, r, s);
    }

    function test_permit_expiredReverts() public {
        uint256 amount = 50 * 10 ** 18;
        uint256 deadline = block.timestamp - 1; // 已过期
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            aliceFromPk, bob, amount, 0, deadline
        );

        vm.expectRevert();
        wct.permit(aliceFromPk, bob, amount, deadline, v, r, s);
    }

    function test_permit_thenTransferFrom_endToEnd() public {
        vm.prank(aliceFromPk);
        wct.claimWelcome();

        uint256 amount = 50 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            aliceFromPk, bob, amount, 0, deadline
        );

        // bob 一笔 tx 内 permit + transferFrom（典型 dApp 用法）
        vm.startPrank(bob);
        wct.permit(aliceFromPk, bob, amount, deadline, v, r, s);
        wct.transferFrom(aliceFromPk, bob, amount);
        vm.stopPrank();

        assertEq(wct.balanceOf(aliceFromPk), 50 * 10 ** 18);
        assertEq(wct.balanceOf(bob), 50 * 10 ** 18);
    }

    function test_DOMAIN_SEPARATOR_isStable() public view {
        bytes32 ds1 = wct.DOMAIN_SEPARATOR();
        bytes32 ds2 = wct.DOMAIN_SEPARATOR();
        assertEq(ds1, ds2);
        assertTrue(ds1 != bytes32(0));
    }
}
