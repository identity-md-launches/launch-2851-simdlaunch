// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Simdlaunch} from "../src/Simdlaunch.sol";
import {TokenFactory} from "./helpers/TokenFactory.sol";

contract SimdlaunchTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    Simdlaunch private token;
    address private deployer;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        vm.prank(deployer);
        token = new Simdlaunch();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "Simdlaunch");
        assertEq(token.symbol(), "SIMD");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_ConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        vm.prank(deployer);
        Simdlaunch fresh = new Simdlaunch();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(deployer))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_FactoryReceivesAllSupply() public {
        TokenFactory factory = new TokenFactory();
        vm.prank(alice, alice);
        Simdlaunch launched = factory.deploy();

        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(alice), 0);
        assertEq(launched.balanceOf(address(this)), 0);
    }

    function test_Create2DeploymentUsesArgumentFreeCreationCode() public {
        TokenFactory factory = new TokenFactory();
        bytes32 salt = keccak256("local launch fixture");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(Simdlaunch).creationCode))
                    )
                )
            )
        );
        Simdlaunch launched = factory.deployDeterministic(salt);

        assertEq(address(launched), predicted);
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
    }

    function test_LaunchDistributionClaimsAndTradingTransfersArriveWhole() public {
        TokenFactory factory = new TokenFactory();
        Simdlaunch launched = factory.deploy();
        address distributor = makeAddr("distributor fixture");
        address pool = makeAddr("pool custody fixture");
        address recipient = makeAddr("remainder recipient fixture");

        factory.distribute(launched, distributor, SUPPLY / 10);
        factory.distribute(launched, pool, SUPPLY * 7 / 10);
        factory.distribute(launched, recipient, SUPPLY / 5);

        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), SUPPLY / 10);
        assertEq(launched.balanceOf(pool), SUPPLY * 7 / 10);
        assertEq(launched.balanceOf(recipient), SUPPLY / 5);

        vm.prank(distributor);
        assertTrue(launched.transfer(alice, SUPPLY / 10));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(alice), SUPPLY / 10);

        vm.prank(pool);
        assertTrue(launched.transfer(bob, 125 ether));
        assertEq(launched.balanceOf(bob), 125 ether);
        vm.prank(bob);
        assertTrue(launched.transfer(pool, 125 ether));
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.balanceOf(pool), SUPPLY * 7 / 10);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferMovesExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, alice, 25 ether);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 25 ether));

        assertEq(token.balanceOf(deployer), SUPPLY - 25 ether);
        assertEq(token.balanceOf(alice), 25 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_SelfTransferPreservesBalanceAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, deployer, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferInsufficientBalanceRevertsWithoutChanges() public {
        _fund(alice, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10 ether, 10 ether + 1)
        );
        vm.prank(alice);
        token.transfer(bob, 10 ether + 1);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferStillRequiresBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
    }

    function test_TransferToZeroRevertsEvenForZeroAmount() public {
        vm.startPrank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.stopPrank();
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveEmitsEventAndDoesNotMoveTokens() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(deployer, spender, 50 ether);
        vm.prank(deployer);
        assertTrue(token.approve(spender, 50 ether));
        assertEq(token.allowance(deployer, spender), 50 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_ApproveOverwritesAndCanBeRevoked() public {
        vm.startPrank(alice);
        assertTrue(token.approve(spender, 50 ether));
        assertTrue(token.approve(spender, 7 ether));
        assertEq(token.allowance(alice, spender), 7 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(alice, spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.stopPrank();
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(alice);
        token.approve(address(0), 1);
        assertEq(token.allowance(alice, address(0)), 0);
    }

    function test_TransferFromConsumesAllowanceAndEmitsTransfer() public {
        _fund(alice, 50 ether);
        vm.prank(alice);
        token.approve(spender, 30 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 12 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 12 ether));
        assertEq(token.balanceOf(alice), 38 ether);
        assertEq(token.balanceOf(bob), 12 ether);
        assertEq(token.allowance(alice, spender), 18 ether);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 18 ether));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(bob), 30 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromInfiniteAllowanceIsNotDecremented() public {
        _fund(alice, 10 ether);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 10 ether));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_ZeroTransferFromNeedsNoAllowanceAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_TransferFromSelfConsumesAllowanceWithoutChangingBalance() public {
        _fund(alice, 20 ether);
        vm.prank(alice);
        token.approve(spender, 20 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, 15 ether));
        assertEq(token.balanceOf(alice), 20 ether);
        assertEq(token.allowance(alice, spender), 5 ether);
    }

    function test_TransferFromInsufficientAllowanceRevertsWithoutChanges() public {
        _fund(alice, 10 ether);
        vm.prank(alice);
        token.approve(spender, 5 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 5 ether, 5 ether + 1)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 5 ether + 1);
        assertEq(token.allowance(alice, spender), 5 ether);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromCannotUseAnotherSpendersApproval() public {
        _fund(alice, 10 ether);
        vm.prank(alice);
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 10 ether);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function test_RevokedApprovalCannotSpend() public {
        _fund(alice, 10 ether);
        vm.startPrank(alice);
        token.approve(spender, type(uint256).max);
        token.approve(spender, 0);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function test_TransferFromInsufficientBalanceRollsBackAllowance() public {
        _fund(alice, 10 ether);
        vm.prank(alice);
        token.approve(spender, 20 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10 ether, 11 ether)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 11 ether);
        assertEq(token.allowance(alice, spender), 20 ether);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromToZeroRollsBackAllowance() public {
        _fund(alice, 10 ether);
        vm.prank(alice);
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 10 ether);
        assertEq(token.allowance(alice, spender), 10 ether);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroSenderReverts() public {
        // OpenZeppelin checks the allowance owner before validating the transfer's sender.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), bob, 0);
    }

    function test_DeployerCannotSpendHolderTokensWithoutApproval() public {
        _fund(alice, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 10 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
    }

    function test_NoExternalMintBurnAdminOrUpgradeEntryPoints() public {
        _fund(alice, 10 ether);
        bytes[] memory calls = new bytes[](15);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[3] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[4] = abi.encodeWithSignature("initialize(address)", bob);
        calls[5] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[6] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[7] = abi.encodeWithSignature("pause()");
        calls[8] = abi.encodeWithSignature("unpause()");
        calls[9] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[10] = abi.encodeWithSignature("freeze(address)", alice);
        calls[11] = abi.encodeWithSignature("seize(address)", alice);
        calls[12] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[13] = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", bob, bytes(""));
        calls[14] = abi.encodeWithSignature("owner()");

        for (uint256 i; i < calls.length; ++i) {
            vm.prank(deployer);
            (bool deployerSuccess,) = address(token).call(calls[i]);
            assertFalse(deployerSuccess);
            vm.prank(bob);
            (bool strangerSuccess,) = address(token).call(calls[i]);
            assertFalse(strangerSuccess);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
    }

    function test_RejectsNativeEtherAndUnknownCalls() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool received,) = address(token).call{value: 1 ether}("");
        assertFalse(received);
        (bool unknown,) = address(token).call(hex"ffffffff");
        assertFalse(unknown);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferConservesSupply(uint256 rawAmount, address recipient) public {
        vm.assume(recipient != address(0));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(recipient, amount));
        if (recipient == deployer) {
            assertEq(token.balanceOf(deployer), SUPPLY);
        } else {
            assertEq(token.balanceOf(deployer), SUPPLY - amount);
            assertEq(token.balanceOf(recipient), amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApproveSetsExactAllowance(uint256 amount) public {
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(alice, spender), amount);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromConservesSupplyAndAccountsForAllowance(uint256 rawAmount, uint256 approval) public {
        uint256 maxAmount = approval < SUPPLY ? approval : SUPPLY;
        uint256 amount = bound(rawAmount, 0, maxAmount);
        vm.prank(deployer);
        token.approve(spender, approval);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, amount));
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.allowance(deployer, spender), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverdrawReverts(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, amount)
        );
        vm.prank(deployer);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_AllowanceOverdrawReverts(uint256 rawApproval, uint256 rawAmount) public {
        uint256 approval = bound(rawApproval, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, approval + 1, SUPPLY);
        vm.prank(deployer);
        token.approve(spender, approval);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, amount)
        );
        vm.prank(spender);
        token.transferFrom(deployer, alice, amount);
        assertEq(token.allowance(deployer, spender), approval);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function _fund(address recipient, uint256 amount) private {
        vm.prank(deployer);
        assertTrue(token.transfer(recipient, amount));
    }
}
