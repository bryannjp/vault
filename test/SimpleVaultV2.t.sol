// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SimpleVault} from "../src/SimpleVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract SimpleVaultV2Test is Test {
    MockERC20 usdc;
    SimpleVault vault;
    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    uint256 constant CAP = 10_000;

    event DepositCapChanged(uint256 oldCap, uint256 newCap);

    function setUp() public {
        usdc = new MockERC20(6);
        vault = new SimpleVault(IERC20(address(usdc)), "V", "V", owner, CAP);
        for (uint256 i; i < 2; i++) {
            address u = i == 0 ? alice : bob;
            usdc.mint(u, 1e30);
            vm.prank(u);
            usdc.approve(address(vault), type(uint256).max);
        }
    }

    function _unauth(address who) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, who);
    }

    // ---------------- cap
    function test_Constructor_SetsOwnerAndCap_AndEmits() public {
        vm.expectEmit(false, false, false, true);
        emit DepositCapChanged(0, 123);
        SimpleVault v = new SimpleVault(IERC20(address(usdc)), "V", "V", owner, 123);
        assertEq(v.owner(), owner);
        assertEq(v.depositCap(), 123);
    }

    function test_RevertWhen_OwnerIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new SimpleVault(IERC20(address(usdc)), "V", "V", address(0), CAP);
    }

    function test_Cap_RoomShrinksAsAssetsGrow() public {
        assertEq(vault.maxDeposit(alice), 10_000);
        vm.prank(alice);
        vault.deposit(4_000, alice);
        assertEq(vault.maxDeposit(alice), 6_000);
        assertEq(vault.maxDeposit(bob), 6_000); // global, not per user
    }

    function test_Cap_DepositExactlyTheRoom_ThenOneMoreReverts() public {
        vm.prank(alice);
        vault.deposit(10_000, alice);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(SimpleVault.Vault__ExceededMaxDeposit.selector, bob, 1, 0));
        vault.deposit(1, bob);
    }

    function test_Cap_OverByOne_RevertsWithTheRoom() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SimpleVault.Vault__ExceededMaxDeposit.selector, alice, 10_001, 10_000));
        vault.deposit(10_001, alice);
    }

    function test_Cap_MintIsCappedToo() public {
        usdc.mint(address(vault), 0);
        vm.prank(alice);
        vault.deposit(5_000, alice);
        usdc.mint(address(vault), 1_000); // yield: shares now worth more
        uint256 m = vault.maxMint(alice);
        assertEq(m, vault.previewDeposit(vault.maxDeposit(alice)));
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(SimpleVault.Vault__ExceededMaxMint.selector, bob, m + 1, m));
        vault.mint(m + 1, bob);
        vm.prank(bob);
        vault.mint(m, bob);
        assertLe(vault.totalAssets(), CAP);
    }

    function test_Cap_YieldAboveTheCap_DoesNotRevert_AndBlocksOnlyDeposits() public {
        vm.prank(alice);
        vault.deposit(9_000, alice);
        usdc.mint(address(vault), 5_000); // now 14,000 > cap
        assertEq(vault.maxDeposit(alice), 0);
        assertEq(vault.maxMint(alice), 0);
        vm.prank(alice);
        vault.redeem(1_000, alice, alice); // exits still work
    }

    function test_Cap_Unlimited_ReturnsUintMax() public {
        vm.prank(owner);
        vault.setDepositCap(type(uint256).max);
        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);
    }

    function test_SetDepositCap_OnlyOwner_Emits() public {
        vm.prank(alice);
        vm.expectRevert(_unauth(alice));
        vault.setDepositCap(1);
        vm.expectEmit(false, false, false, true, address(vault));
        emit DepositCapChanged(CAP, 5);
        vm.prank(owner);
        vault.setDepositCap(5);
        assertEq(vault.depositCap(), 5);
    }

    function testFuzz_MaxFunctions_NeverRevert_AndMaxMintFitsTheRoom(uint256 cap, uint256 dep, uint256 yield_) public {
        dep = bound(dep, 0, 1e24);
        yield_ = bound(yield_, 0, 1e24);
        vm.prank(owner);
        vault.setDepositCap(type(uint256).max);
        vm.prank(alice);
        vault.deposit(dep, alice);
        usdc.mint(address(vault), yield_);
        vm.prank(owner);
        vault.setDepositCap(cap);

        uint256 room = vault.maxDeposit(bob);
        uint256 m = vault.maxMint(bob);
        vault.maxWithdraw(alice);
        vault.maxRedeem(alice);
        if (room != type(uint256).max) {
            assertLe(vault.previewMint(m), room);
            if (room <= 1e27) {
                vm.prank(bob);
                vault.mint(m, bob);
                assertLe(vault.totalAssets(), cap > dep + yield_ ? cap : dep + yield_);
            }
        }
    }

    // ---------------- pause
    function test_Pause_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(_unauth(alice));
        vault.pause();
        vm.prank(owner);
        vault.pause();
        vm.prank(alice);
        vm.expectRevert(_unauth(alice));
        vault.unpause();
    }

    function test_Pause_StopsAllFour_EvenZeroAmounts_AndMaxIsZero() public {
        vm.prank(alice);
        vault.deposit(1_000, alice);
        vm.prank(alice);
        vault.approve(bob, 1_000);
        vm.prank(owner);
        vault.pause();

        assertEq(vault.maxDeposit(alice), 0);
        assertEq(vault.maxMint(alice), 0);
        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxRedeem(alice), 0);
        assertEq(vault.previewRedeem(100), 100); // previews still answer

        vm.startPrank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.deposit(0, alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.mint(1, alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.withdraw(1, alice, alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.redeem(1, alice, alice);
        vault.transfer(bob, 10); // shares stay transferable
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.redeem(1, bob, alice);

        vm.prank(owner);
        vault.unpause();
        vm.prank(alice);
        vault.redeem(100, alice, alice);
    }

    function test_Pause_Twice_And_UnpauseWhenRunning_Revert() public {
        vm.startPrank(owner);
        vm.expectRevert(Pausable.ExpectedPause.selector);
        vault.unpause();
        vault.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.pause();
        vm.stopPrank();
    }

    // ---------------- ownership
    function test_Ownership_IsTwoStep() public {
        vm.prank(owner);
        vault.transferOwnership(bob);
        assertEq(vault.owner(), owner); // nothing changes yet
        assertEq(vault.pendingOwner(), bob);

        vm.prank(alice);
        vm.expectRevert(_unauth(alice));
        vault.acceptOwnership();

        vm.prank(bob);
        vault.acceptOwnership();
        assertEq(vault.owner(), bob);
        vm.prank(owner);
        vm.expectRevert(_unauth(owner));
        vault.pause();
    }

    function test_Renounce_IsDisabled() public {
        vm.prank(owner);
        vm.expectRevert(SimpleVault.Vault__RenounceDisabled.selector);
        vault.renounceOwnership();
        vm.prank(alice);
        vm.expectRevert(_unauth(alice));
        vault.renounceOwnership();
        assertEq(vault.owner(), owner);
    }

    function test_Cap_Unlimited_StaysUintMax_WhenTheVaultHoldsAssets() public {
        vm.prank(owner);
        vault.setDepositCap(type(uint256).max);
        vm.prank(alice);
        vault.deposit(5_000, alice);
        usdc.mint(address(vault), 1_000); // yield, so assets > shares
        assertEq(vault.maxDeposit(alice), type(uint256).max); // spec: MUST return 2**256-1 when there is no limit
        assertEq(vault.maxMint(alice), type(uint256).max);
    }
}
