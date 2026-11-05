// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SimpleVault} from "../src/SimpleVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// Random sequences of everything users can do. Calls that would revert are skipped or caught.
contract VaultHandler is Test {
    SimpleVault internal vault;
    MockERC20 internal usdc;
    address[] internal actors;

    uint256 public ghostIn; // assets users paid in
    uint256 public ghostOut; // assets users took out
    uint256 public ghostDonated; // yield sent straight to the vault
    bool public ghostPaidOutMoreThanQuoted; // a withdraw/redeem gave more than its preview promised
    bool public ghostMovedWhilePaused; // a deposit/mint/withdraw/redeem succeeded while paused
    bool public ghostDepositBrokeTheCap; // a deposit/mint pushed assets above both the cap and where they were
    address internal owner;

    constructor(SimpleVault vault_, MockERC20 usdc_, address[] memory actors_, address owner_) {
        owner = owner_;
        vault = vault_;
        usdc = usdc_;
        actors = actors_;
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

    function setCap(uint256 cap, bool unlimited) external {
        cap = unlimited ? type(uint256).max : bound(cap, 0, 4e15);
        vm.prank(owner);
        vault.setDepositCap(cap);
    }

    function togglePause(uint256 seed) external {
        if (seed % 4 != 0) return; // pause only now and then, so most sequences keep running
        vm.prank(owner);
        if (vault.paused()) vault.unpause();
        else vault.pause();
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function deposit(uint256 seed, uint256 assets) external watch(true) {
        address who = _actor(seed);
        assets = bound(assets, 0, usdc.balanceOf(who));
        vm.prank(who);
        vault.deposit(assets, who);
        ghostIn += assets;
    }

    function mint(uint256 seed, uint256 shares) external watch(true) {
        address who = _actor(seed);
        shares = bound(shares, 0, 1e15);
        if (vault.previewMint(shares) > usdc.balanceOf(who)) return;
        vm.prank(who);
        ghostIn += vault.mint(shares, who);
    }

    function withdraw(uint256 seed, uint256 receiverSeed, uint256 assets, bool viaOperator) external watch(false) {
        address owner = _actor(seed);
        address caller = viaOperator ? _actor(seed + 1) : owner;
        assets = bound(assets, 0, vault.maxWithdraw(owner));
        uint256 burn = vault.previewWithdraw(assets);
        if (viaOperator && caller != owner) {
            vm.prank(owner);
            vault.approve(caller, burn);
        }
        address receiver = _actor(receiverSeed);
        uint256 before = usdc.balanceOf(receiver);
        vm.prank(caller);
        vault.withdraw(assets, receiver, owner);
        if (usdc.balanceOf(receiver) - before > assets) ghostPaidOutMoreThanQuoted = true;
        ghostOut += assets;
    }

    function redeem(uint256 seed, uint256 receiverSeed, uint256 shares, bool viaOperator) external watch(false) {
        address owner = _actor(seed);
        address caller = viaOperator ? _actor(seed + 1) : owner;
        shares = bound(shares, 0, vault.maxRedeem(owner));
        uint256 quoted = vault.previewRedeem(shares);
        if (viaOperator && caller != owner) {
            vm.prank(owner);
            vault.approve(caller, shares);
        }
        address receiver = _actor(receiverSeed);
        uint256 before = usdc.balanceOf(receiver);
        vm.prank(caller);
        uint256 got = vault.redeem(shares, receiver, owner);
        if (got > quoted || usdc.balanceOf(receiver) - before > quoted) ghostPaidOutMoreThanQuoted = true;
        ghostOut += got;
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
}

contract SimpleVaultInvariantTest is Test {
    MockERC20 internal usdc;
    SimpleVault internal vault;
    VaultHandler internal handler;
    address[] internal actors;

    address internal owner = makeAddr("owner");

    function setUp() public {
        usdc = new MockERC20(6);
        vault = new SimpleVault(IERC20(address(usdc)), "Simple Vault USDC", "svUSDC", owner, 2e15);
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

    /// The vault can always pay everyone what it says they can withdraw.
    function invariant_Solvent_EveryoneCanBePaidAtOnce() public view {
        uint256 owed;
        for (uint256 i = 0; i < actors.length; i++) {
            owed += vault.maxWithdraw(actors[i]);
        }
        assertLe(owed, vault.totalAssets());
    }

    /// The tokens the vault holds are exactly what came in minus what went out.
    function invariant_Accounting_AssetsInMinusOut() public view {
        assertEq(vault.totalAssets(), handler.ghostIn() + handler.ghostDonated() - handler.ghostOut());
        assertEq(vault.totalAssets(), usdc.balanceOf(address(vault)));
    }

    function invariant_SharesSupplyEqualsTheSumOfBalances() public view {
        uint256 sum;
        for (uint256 i = 0; i < actors.length; i++) {
            sum += vault.balanceOf(actors[i]);
        }
        assertEq(vault.totalSupply(), sum);
    }

    /// Shares outstanding never claim more than the vault holds (rounding stays in the vault's favour).
    function invariant_AllSharesTogetherAreWorthAtMostTheAssets() public view {
        assertLe(vault.convertToAssets(vault.totalSupply()), vault.totalAssets());
    }

    function invariant_NoPayoutExceedsItsQuote() public view {
        assertFalse(handler.ghostPaidOutMoreThanQuoted());
    }

    function invariant_NothingMovesWhilePaused() public view {
        assertFalse(handler.ghostMovedWhilePaused());
    }

    function invariant_DepositsNeverBreakTheCap() public view {
        assertFalse(handler.ghostDepositBrokeTheCap());
    }
}
