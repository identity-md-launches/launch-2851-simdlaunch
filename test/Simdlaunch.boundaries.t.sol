// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Simdlaunch} from "src/Simdlaunch.sol";

/// @dev A real contract spender checks msg.sender handling without impersonating a contract.
contract SIMDSpenderFixture {
    function pull(Simdlaunch token, address owner, address recipient, uint256 amount) external returns (bool) {
        return token.transferFrom(owner, recipient, amount);
    }
}

/// @dev ERC-20 recipients do not need a callback or even a payable fallback.
contract SIMDRejectingRecipient {
    fallback() external {
        revert("recipient must not be called");
    }
}

/// @notice Boundary and sequence properties complement the existing basic ERC-20 tests.
/// forge-config: default.fuzz.runs = 1000
contract SimdlaunchBoundaryTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Simdlaunch private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new Simdlaunch();
        alice = makeAddr("boundary alice");
        bob = makeAddr("boundary bob");
        spender = makeAddr("boundary spender");
    }

    function test_OneBaseUnitCanBeTransferredAndSpent() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumMinusOneAllowanceIsFinite() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferRevertsWithAndWithoutInfiniteApproval() public {
        uint256 maximum = type(uint256).max;
        bytes memory error =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum);
        vm.expectRevert(error);
        token.transfer(alice, maximum);
        token.approve(spender, maximum);
        vm.expectRevert(error);
        vm.prank(spender);
        token.transferFrom(address(this), alice, maximum);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), maximum);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_OwnerNeedsSelfApprovalForTransferFrom() public {
        token.transfer(alice, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(bob), 0);

        vm.startPrank(alice);
        assertTrue(token.approve(alice, 1));
        assertTrue(token.transferFrom(alice, bob, 1));
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, alice), 0);
    }

    function test_ApprovalDoesNotFollowTokensToANewOwner() public {
        token.transfer(alice, 10);
        vm.startPrank(alice);
        token.approve(spender, 10);
        token.transfer(bob, 10);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(bob, spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, spender, 1);
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.allowance(bob, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 10);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_InfiniteAllowanceCanBeReducedAndExhausted() public {
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(alice, bob, 3);
        assertEq(token.allowance(alice, spender), type(uint256).max);

        vm.prank(alice);
        token.approve(spender, 2);
        vm.prank(spender);
        token.transferFrom(alice, bob, 2);
        assertEq(token.allowance(alice, spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 5);
        assertEq(token.balanceOf(bob), 5);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroSpenderRejectedAtZeroAndMaximumApproval() public {
        token.approve(spender, 17);
        bytes memory error = abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0));
        vm.expectRevert(error);
        token.approve(address(0), 0);
        vm.expectRevert(error);
        token.approve(address(0), type(uint256).max);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), spender), 17);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroDelegatedTransferStillRejectsZeroRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_FailedSpendDoesNotConsumeAnOtherwiseUsableApproval() public {
        token.transfer(alice, 7);
        vm.prank(alice);
        token.approve(spender, 8);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 7, 8));
        vm.prank(spender);
        token.transferFrom(alice, bob, 8);
        assertEq(token.allowance(alice, spender), 8);
        assertEq(token.balanceOf(alice), 7);
        assertEq(token.balanceOf(bob), 0);

        token.transfer(alice, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 8));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 8);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ContractSpenderUsesItsOwnAllowanceAndRecipientNeedsNoCallback() public {
        SIMDSpenderFixture contractSpender = new SIMDSpenderFixture();
        SIMDRejectingRecipient recipient = new SIMDRejectingRecipient();
        token.transfer(alice, 9);
        vm.prank(alice);
        token.approve(address(contractSpender), 9);
        vm.prank(bob, bob);
        assertTrue(contractSpender.pull(token, alice, address(recipient), 9));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(recipient)), 9);
        assertEq(token.balanceOf(address(contractSpender)), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, address(contractSpender)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToTokenItselfIsAccountedForAsABalance() public {
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_NonpayableSelectorsRejectEtherWithoutChangingTokensOrAllowances() public {
        token.transfer(alice, 3);
        vm.prank(alice);
        token.approve(spender, 2);
        vm.deal(alice, 1);
        vm.deal(spender, 1);

        vm.prank(alice);
        (bool transferred,) = address(token).call{value: 1}(abi.encodeCall(token.transfer, (bob, 1)));
        assertFalse(transferred);
        vm.prank(alice);
        (bool approved,) = address(token).call{value: 1}(abi.encodeCall(token.approve, (spender, 3)));
        assertFalse(approved);
        vm.prank(spender);
        (bool spent,) = address(token).call{value: 1}(abi.encodeCall(token.transferFrom, (alice, bob, 1)));
        assertFalse(spent);
        assertEq(token.balanceOf(alice), 3);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), 2);
        assertEq(address(token).balance, 0);
        assertEq(alice.balance, 1);
        assertEq(spender.balance, 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalReplacementIsExactIdempotentAndIsolated(uint256 first, uint256 replacement) public {
        token.transfer(alice, 7);
        token.approve(spender, 23);
        vm.startPrank(alice);
        token.approve(bob, 41);
        token.approve(spender, first);
        assertEq(token.allowance(alice, spender), first);
        token.approve(spender, replacement);
        assertEq(token.allowance(alice, spender), replacement);
        token.approve(spender, replacement);
        vm.stopPrank();
        assertEq(token.allowance(alice, spender), replacement);
        assertEq(token.allowance(alice, bob), 41);
        assertEq(token.allowance(address(this), spender), 23);
        assertEq(token.allowance(spender, alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 7);
        assertEq(token.balanceOf(alice), 7);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedOverdrawRollsBackAnyAllowance(uint256 balanceSeed, uint256 amountSeed, bool infinite)
        public
    {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        uint256 approval = infinite ? type(uint256).max : amount;
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, approval);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_AllRolesMayAliasWithoutCreatingTokens(uint256 balanceSeed, uint256 approval, uint256 amountSeed)
        public
    {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = bound(amountSeed, 0, balance < approval ? balance : approval);
        token.transfer(alice, balance);
        vm.startPrank(alice);
        token.approve(alice, approval);
        assertTrue(token.transferFrom(alice, alice, amount));
        vm.stopPrank();
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.allowance(alice, alice), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ExhaustedAllowanceCannotBeReplayedAfterTokensReturn(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, 1, SUPPLY);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.approve(spender, amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.allowance(alice, spender), 0);

        vm.prank(bob);
        token.transfer(alice, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RepeatedRoundTripsRestoreBalancesAndPreserveApprovals(
        uint256 balanceSeed,
        uint256 amountSeed,
        uint256 cyclesSeed
    ) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = bound(amountSeed, 0, balance);
        uint256 cycles = bound(cyclesSeed, 1, 8);
        token.transfer(alice, balance);
        token.transfer(bob, SUPPLY - balance);
        vm.prank(alice);
        token.approve(spender, amount);
        for (uint256 i; i < cycles; ++i) {
            vm.prank(alice);
            assertTrue(token.transfer(bob, amount));
            assertEq(token.balanceOf(alice), balance - amount);
            assertEq(token.balanceOf(bob), SUPPLY - balance + amount);
            vm.prank(bob);
            assertTrue(token.transfer(alice, amount));
            assertEq(token.balanceOf(alice), balance);
            assertEq(token.balanceOf(bob), SUPPLY - balance);
            assertEq(token.allowance(alice, spender), amount);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function testFuzz_SplittingDelegatedTransfersHasTheSameFinalState(uint256 totalSeed, uint256 firstSeed) public {
        uint256 total = bound(totalSeed, 0, SUPPLY);
        uint256 first = bound(firstSeed, 0, total);
        Simdlaunch single = new Simdlaunch();
        token.approve(spender, total);
        single.approve(spender, total);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertTrue(token.transferFrom(address(this), alice, total - first));
        assertTrue(single.transferFrom(address(this), alice, total));
        vm.stopPrank();
        assertEq(token.balanceOf(alice), total);
        assertEq(token.balanceOf(address(this)), SUPPLY - total);
        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(single.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }
}
