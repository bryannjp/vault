// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SimpleVault} from "../src/SimpleVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// Random sequences of everything users and the owner can do. Calls that revert are simply undone.
contract VaultHandler is Test {
    SimpleVault internal vault;
    MockERC20 internal usdc;
    address[] internal actors;
    address internal owner;

    uint256 public ghostIn; // assets users paid in
    uint256 public ghostOut; // assets users claimed
    uint256 public ghostDonated; // yield sent straight to the vault
    bool public ghostPaidMoreThanAsked; // a claim delivered more than the amount claimed
    bool public ghostMovedWhilePaused; // a deposit/mint/request/claim succeeded while paused
    bool public ghostDepositBrokeTheCap; // a deposit/mint pushed assets above both the cap and where they were
    bool public ghostClaimedEarly; // a claim succeeded before its claimableAt
    bool public ghostClaimOverLimit; // a claim took more than what was left of the daily limit
    bool public ghostPriceDropped; // a request or claim lowered the share price

    constructor(SimpleVault vault_, MockERC20 usdc_, address[] memory actors_, address owner_) {
        vault = vault_;
        usdc = usdc_;
        actors = actors_;
        owner = owner_;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// Records anything a successful action did that it must never do.
    modifier watch(bool isDeposit) {
        bool wasPaused = vault.paused();
        uint256 before = vault.totalAssets();
        uint256 cap = vault.depositCap();
        _;
        if (wasPaused) ghostMovedWhilePaused = true;
        if (isDeposit && vault.totalAssets() > (cap > before ? cap : before)) ghostDepositBrokeTheCap = true;
    }

    /// Share price = (assets + 1) / (shares + 1); compared by cross-multiplying to avoid rounding.
    modifier priceNeverDrops() {
        uint256 a0 = vault.totalAssets() + 1;
        uint256 s0 = vault.totalSupply() + 1;
        _;
        if ((vault.totalAssets() + 1) * s0 < a0 * (vault.totalSupply() + 1)) ghostPriceDropped = true;
    }

    // ---------------------------------------------------------------- users

    function deposit(uint256 seed, uint256 assets) external watch(true) {
        address who = _actor(seed);
        assets = bound(assets, 0, 1e12);
        vm.prank(who);
        vault.deposit(assets, who);
        ghostIn += assets;
    }

    function mint(uint256 seed, uint256 shares) external watch(true) {
        address who = _actor(seed);
        shares = bound(shares, 0, 1e12);
        vm.prank(who);
        ghostIn += vault.mint(shares, who);
    }

    function requestRedeem(uint256 seed, uint256 shares) external watch(false) priceNeverDrops {
        address who = _actor(seed);
        shares = bound(shares, 0, vault.balanceOf(who));
        vm.prank(who);
        vault.requestRedeem(shares);
    }

    function claim(uint256 seed, uint256 receiverSeed, uint256 assets) external watch(false) priceNeverDrops {
        address who = _actor(seed);
        (uint256 requested, uint256 claimableAt) = vault.requests(who);
        uint256 remaining = vault.remainingToday();
        // mostly ask for an amount that can succeed; sometimes anything up to the request
        uint256 fits = requested < remaining ? requested : remaining;
        assets = assets % 4 == 0 || fits == 0 ? bound(assets, 0, requested) : bound(assets, 1, fits);
        address receiver = _actor(receiverSeed);
        uint256 before = usdc.balanceOf(receiver);

        vm.prank(who);
        vault.claim(assets, receiver);

        if (usdc.balanceOf(receiver) - before != assets) ghostPaidMoreThanAsked = true;
        if (block.timestamp < claimableAt) ghostClaimedEarly = true;
        if (assets > remaining) ghostClaimOverLimit = true;
        ghostOut += assets;
    }

    function transferShares(uint256 fromSeed, uint256 toSeed, uint256 shares) external {
        address from = _actor(fromSeed);
        shares = bound(shares, 0, vault.balanceOf(from));
        vm.prank(from);
        vault.transfer(_actor(toSeed), shares);
    }

    function donate(uint256 amount) external {
        amount = bound(amount, 0, 1e12);
        usdc.mint(address(vault), amount);
        ghostDonated += amount;
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 0, 2 days));
    }

    // ---------------------------------------------------------------- owner

    function setCap(uint256 cap, bool unlimited) external {
        cap = unlimited ? type(uint256).max : bound(cap, 0, 4e12);
        vm.prank(owner);
        vault.setDepositCap(cap);
    }

    function setDailyLimit(uint256 limit, bool unlimited) external {
        limit = unlimited ? type(uint256).max : bound(limit, 0, 2e12);
        vm.prank(owner);
        vault.setDailyLimit(limit);
    }

    function togglePause(uint256 seed) external {
        if (seed % 4 != 0) return; // pause only now and then, so most sequences keep running
        vm.prank(owner);
        if (vault.paused()) vault.unpause();
        else vault.pause();
    }
}

contract SimpleVaultInvariantTest is Test {
    MockERC20 internal usdc;
    SimpleVault internal vault;
    VaultHandler internal handler;
    address[] internal actors;
    address internal owner = makeAddr("owner");

    function setUp() public {
        vm.warp(1_700_000_000);
        usdc = new MockERC20(6);
        vault = new SimpleVault(IERC20(address(usdc)), "Simple Vault USDC", "svUSDC", owner, 2e12, 1 days);
        for (uint256 i = 0; i < 4; i++) {
            address a = makeAddr(string.concat("actor", vm.toString(i)));
            actors.push(a);
            usdc.mint(a, 1e15);
            vm.prank(a);
            usdc.approve(address(vault), type(uint256).max);
        }
        handler = new VaultHandler(vault, usdc, actors, owner);
        targetContract(address(handler));
    }

    /// Every token the vault holds is either free (backing shares) or promised to a request.
    function invariant_Accounting_HeldEqualsFreePlusPending() public view {
        assertEq(usdc.balanceOf(address(vault)), vault.totalAssets() + vault.totalPending());
        assertEq(usdc.balanceOf(address(vault)), handler.ghostIn() + handler.ghostDonated() - handler.ghostOut());
    }

    function invariant_PendingIsTheSumOfAllRequests() public view {
        uint256 sum;
        for (uint256 i = 0; i < actors.length; i++) {
            (uint256 requested,) = vault.requests(actors[i]);
            sum += requested;
        }
        assertEq(vault.totalPending(), sum);
    }

    function invariant_SharesSupplyEqualsTheSumOfBalances() public view {
        uint256 sum;
        for (uint256 i = 0; i < actors.length; i++) {
            sum += vault.balanceOf(actors[i]);
        }
        assertEq(vault.totalSupply(), sum);
    }

    /// Outstanding shares never claim more than the free assets (rounding stays in the vault's favour).
    function invariant_Solvent_SharesWorthAtMostTheFreeAssets() public view {
        assertLe(vault.convertToAssets(vault.totalSupply()), vault.totalAssets());
    }

    function invariant_ClaimsPayExactlyWhatWasClaimed() public view {
        assertFalse(handler.ghostPaidMoreThanAsked());
    }

    function invariant_NothingMovesWhilePaused() public view {
        assertFalse(handler.ghostMovedWhilePaused());
    }

    function invariant_DepositsNeverBreakTheCap() public view {
        assertFalse(handler.ghostDepositBrokeTheCap());
    }

    function invariant_NoClaimBeforeTheDelay() public view {
        assertFalse(handler.ghostClaimedEarly());
    }

    function invariant_NoClaimAboveTheDailyLimit() public view {
        assertFalse(handler.ghostClaimOverLimit());
    }

    function invariant_RequestsAndClaimsNeverLowerTheSharePrice() public view {
        assertFalse(handler.ghostPriceDropped());
    }
}
