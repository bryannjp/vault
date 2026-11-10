// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SimpleVault} from "../src/SimpleVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract SimpleVaultV3Test is Test {
    MockERC20 usdc;
    SimpleVault vault;
    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    uint256 constant DELAY = 3 days;
    uint256 constant T0 = 1_700_000_000; // a Tuesday, 22:13 UTC

    event WithdrawalRequested(address indexed owner, uint256 shares, uint256 assets, uint256 claimableAt);
    event WithdrawalClaimed(address indexed owner, address indexed receiver, uint256 assets);
    event DailyLimitChanged(uint256 oldLimit, uint256 newLimit);

    function setUp() public {
        vm.warp(T0);
        usdc = new MockERC20(6);
        vault = new SimpleVault(IERC20(address(usdc)), "V", "V", owner, type(uint256).max, DELAY);
        address[2] memory us = [alice, bob];
        for (uint256 i; i < 2; i++) {
            usdc.mint(us[i], 1e30);
            vm.startPrank(us[i]);
            usdc.approve(address(vault), type(uint256).max);
            vault.deposit(10_000, us[i]);
            vm.stopPrank();
        }
    }

    function _request(address who, uint256 shares) internal returns (uint256) {
        vm.prank(who);
        return vault.requestRedeem(shares);
    }

    function _claim(address who, uint256 assets, address to) internal {
        vm.prank(who);
        vault.claim(assets, to);
    }

    // constructor
    function test_Constructor_DelayStored_LimitStartsUnlimited() public view {
        assertEq(vault.withdrawalDelay(), DELAY);
        assertEq(vault.dailyLimit(), type(uint256).max);
        assertEq(vault.remainingToday(), type(uint256).max);
    }

    function test_RevertWhen_DelayAbove30Days() public {
        vm.expectRevert(abi.encodeWithSelector(SimpleVault.Vault__DelayTooLong.selector, 31 days, 30 days));
        new SimpleVault(IERC20(address(usdc)), "V", "V", owner, type(uint256).max, 31 days);
    }

    // sync exits are off
    function test_SyncWithdrawAndRedeem_AreOff() public {
        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxRedeem(alice), 0);
        vm.startPrank(alice);
        vm.expectRevert(SimpleVault.Vault__UseRequestRedeem.selector);
        vault.withdraw(1, alice, alice);
        vm.expectRevert(SimpleVault.Vault__UseRequestRedeem.selector);
        vault.redeem(1, alice, alice);
        vm.stopPrank();
    }

    // request
    function test_Request_BurnsShares_FixesAssets_ReservesThem() public {
        usdc.mint(address(vault), 2_000); // yield: 22,000 assets, 20,000 shares
        uint256 quote = vault.previewRedeem(5_000);
        vm.expectEmit(true, false, false, true, address(vault));
        emit WithdrawalRequested(alice, 5_000, quote, T0 + DELAY);
        uint256 assets = _request(alice, 5_000);

        assertEq(assets, quote);
        assertEq(assets, 5_499); // 5,000 * 22,001 / 20,001 rounded down
        assertEq(vault.balanceOf(alice), 5_000);
        assertEq(vault.totalSupply(), 15_000);
        assertEq(vault.totalPending(), 5_499);
        assertEq(vault.totalAssets(), 22_000 - 5_499);
        assertEq(usdc.balanceOf(address(vault)), 22_000); // nothing left yet
        (uint256 a, uint256 claimableAt) = vault.requests(alice);
        assertEq(a, 5_499);
        assertEq(claimableAt, T0 + DELAY);
    }

    function test_Request_DoesNotLowerTheSharePriceForOthers() public {
        usdc.mint(address(vault), 2_000);
        uint256 bobBefore = vault.convertToAssets(vault.balanceOf(bob));
        _request(alice, 7_777);
        assertGe(vault.convertToAssets(vault.balanceOf(bob)), bobBefore);
    }

    function test_Request_YieldAfterTheRequest_GoesToRemainingHolders() public {
        uint256 assets = _request(alice, 10_000); // her whole position, 10,000
        usdc.mint(address(vault), 3_000);
        vm.warp(T0 + DELAY);
        _claim(alice, assets, alice);
        assertEq(assets, 10_000);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 12_999); // bob got the 3,000 yield
    }

    function test_RevertWhen_SecondRequestWhilePending() public {
        _request(alice, 100);
        vm.prank(alice);
        vm.expectRevert(SimpleVault.Vault__RequestPending.selector);
        vault.requestRedeem(100);
    }

    function test_CanRequestAgain_AfterTheFullClaim() public {
        _request(alice, 100);
        vm.warp(T0 + DELAY);
        _claim(alice, 100, alice);
        _request(alice, 100);
    }

    function test_RevertWhen_RequestIsZeroOrDust() public {
        vm.startPrank(alice);
        vm.expectRevert(SimpleVault.Vault__ZeroAssets.selector);
        vault.requestRedeem(0);
        vm.stopPrank();
    }

    function test_RevertWhen_RequestMoreSharesThanOwned() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10_000, 10_001));
        vault.requestRedeem(10_001);
    }

    // claim
    function test_RevertWhen_ClaimBeforeTheDelay_ThenWorksExactlyAtIt() public {
        _request(alice, 1_000);
        vm.warp(T0 + DELAY - 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SimpleVault.Vault__NotClaimableYet.selector, T0 + DELAY));
        vault.claim(1_000, alice);
        vm.warp(T0 + DELAY);
        vm.expectEmit(true, true, false, true, address(vault));
        emit WithdrawalClaimed(alice, carol, 1_000);
        _claim(alice, 1_000, carol);
        assertEq(usdc.balanceOf(carol), 1_000);
        assertEq(vault.totalPending(), 0);
    }

    function test_Claim_Partial_ThenRest() public {
        _request(alice, 1_000);
        vm.warp(T0 + DELAY);
        _claim(alice, 400, alice);
        (uint256 left,) = vault.requests(alice);
        assertEq(left, 600);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SimpleVault.Vault__ExceedsRequest.selector, 601, 600));
        vault.claim(601, alice);
        _claim(alice, 600, alice);
        vm.prank(alice);
        vm.expectRevert(SimpleVault.Vault__NoRequest.selector);
        vault.claim(1, alice);
    }

    function test_RevertWhen_ClaimWithoutRequest_OrZero() public {
        vm.prank(bob);
        vm.expectRevert(SimpleVault.Vault__NoRequest.selector);
        vault.claim(1, bob);
        _request(bob, 10);
        vm.warp(T0 + DELAY);
        vm.prank(bob);
        vm.expectRevert(SimpleVault.Vault__ZeroAssets.selector);
        vault.claim(0, bob);
    }

    // daily limit
    function test_DailyLimit_SharedByEveryone_ResetsAtUtcMidnight() public {
        vm.prank(owner);
        vault.setDailyLimit(1_000);
        _request(alice, 900);
        _request(bob, 900);
        vm.warp(T0 + DELAY); // Friday 22:13 UTC
        _claim(alice, 600, alice);
        assertEq(vault.remainingToday(), 400);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(SimpleVault.Vault__DailyLimitExceeded.selector, 500, 400));
        vault.claim(500, bob);
        _claim(bob, 400, bob);

        vm.warp((block.timestamp / 1 days + 1) * 1 days); // Saturday 00:00 UTC, 1h47m later
        assertEq(vault.remainingToday(), 1_000);
        _claim(bob, 500, bob);
        _claim(alice, 300, alice);
        assertEq(vault.remainingToday(), 200);
    }

    function test_DailyLimit_BigRequest_IsClaimedOverSeveralDays() public {
        vm.prank(owner);
        vault.setDailyLimit(2_000);
        _request(alice, 10_000);
        vm.warp(T0 + DELAY);
        for (uint256 d; d < 5; d++) {
            _claim(alice, 2_000, alice);
            vm.warp(block.timestamp + 1 days);
        }
        (uint256 left,) = vault.requests(alice);
        assertEq(left, 0);
        assertEq(usdc.balanceOf(alice), 1e30 - 10_000 + 10_000);
    }

    function test_DailyLimit_LoweredBelowUsed_LeavesZero() public {
        _request(alice, 1_000);
        vm.warp(T0 + DELAY);
        vm.prank(owner);
        vault.setDailyLimit(800);
        _claim(alice, 700, alice);
        vm.prank(owner);
        vault.setDailyLimit(500);
        assertEq(vault.remainingToday(), 0);
    }

    function test_SetDailyLimit_OnlyOwner_Emits() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vault.setDailyLimit(1);
        vm.expectEmit(false, false, false, true, address(vault));
        emit DailyLimitChanged(type(uint256).max, 5);
        vm.prank(owner);
        vault.setDailyLimit(5);
    }

    // pause and cap
    function test_Pause_BlocksRequestAndClaim() public {
        _request(alice, 100);
        vm.warp(T0 + DELAY);
        vm.prank(owner);
        vault.pause();
        vm.startPrank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.claim(100, alice);
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.requestRedeem(100);
    }

    function test_Cap_IgnoresPendingAssets() public {
        vm.prank(owner);
        vault.setDepositCap(25_000);
        assertEq(vault.maxDeposit(carol), 5_000);
        _request(alice, 5_000);
        assertEq(vault.maxDeposit(carol), 10_000); // reserved assets no longer count
    }

    function test_Delay_ExactlyThe30DayMaximum_IsAllowed() public {
        SimpleVault v = new SimpleVault(IERC20(address(usdc)), "V", "V", owner, type(uint256).max, 30 days);
        assertEq(v.withdrawalDelay(), 30 days);
    }

    function test_NoLimit_RemainingStaysEffectivelyUnlimited() public {
        _request(alice, 1_000);
        vm.warp(T0 + DELAY);
        _claim(alice, 1_000, alice);
        assertEq(vault.remainingToday(), type(uint256).max - 1_000);
    }
}
