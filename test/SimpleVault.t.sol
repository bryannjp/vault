// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SimpleVault} from "../src/SimpleVault.sol";
import {MockERC20, NoDecimalsToken, HugeDecimalsToken, SnoopingToken} from "./mocks/MockERC20.sol";

/// OpenZeppelin's own vault, used as the answer key in the differential tests.
contract OZVault is ERC4626 {
    constructor(IERC20 asset_) ERC4626(asset_) ERC20("OZ Vault", "ozV") {}
}

contract SimpleVaultTest is Test {
    MockERC20 internal usdc;
    SimpleVault internal vault;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal early = makeAddr("early");

    uint256 internal constant START = 1_000_000e6; // every user's starting USDC

    // declared locally so a wrong `indexed` or argument order in the contract is caught
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public {
        usdc = new MockERC20(6);
        vault = new SimpleVault(IERC20(address(usdc)), "Simple Vault USDC", "svUSDC");
        address[4] memory users = [alice, bob, carol, early];
        for (uint256 i = 0; i < users.length; i++) {
            usdc.mint(users[i], START);
            vm.prank(users[i]);
            usdc.approve(address(vault), type(uint256).max);
        }
    }

    // ------------------------------------------------------------------ helpers

    function _deposit(address who, uint256 assets) internal returns (uint256 shares) {
        vm.prank(who);
        shares = vault.deposit(assets, who);
    }

    /// The scenario from the explanation: 1,000 assets backing 800 shares (1 share = 1.25 USDC).
    function _scenario() internal {
        _deposit(early, 800);
        usdc.mint(address(vault), 200); // yield
        assertEq(vault.totalAssets(), 1_000);
        assertEq(vault.totalSupply(), 800);
    }

    function _insufficientAllowance(address spender, uint256 allowance_, uint256 needed)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance_, needed);
    }

    // ------------------------------------------------------------------ constructor and metadata

    function test_Constructor_SetsAssetNameAndSymbol() public view {
        assertEq(vault.asset(), address(usdc));
        assertEq(vault.name(), "Simple Vault USDC");
        assertEq(vault.symbol(), "svUSDC");
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
    }

    function test_RevertWhen_AssetIsTheZeroAddress() public {
        vm.expectRevert(SimpleVault.ZeroAddress.selector);
        new SimpleVault(IERC20(address(0)), "V", "V");
    }

    function testFuzz_Decimals_FollowTheAsset(uint8 assetDecimals) public {
        MockERC20 token = new MockERC20(assetDecimals);
        SimpleVault v = new SimpleVault(IERC20(address(token)), "V", "V");
        assertEq(v.decimals(), assetDecimals);
    }

    function test_Decimals_FallBackTo18_WhenTheAssetHasNoCode() public {
        SimpleVault v = new SimpleVault(IERC20(makeAddr("not a contract")), "V", "V");
        assertEq(v.decimals(), 18);
    }

    function test_Decimals_FallBackTo18_WhenTheAssetHasNoDecimalsFunction() public {
        SimpleVault v = new SimpleVault(IERC20(address(new NoDecimalsToken())), "V", "V");
        assertEq(v.decimals(), 18);
    }

    function test_Decimals_FallBackTo18_WhenTheAssetsDecimalsDoNotFitInUint8() public {
        SimpleVault v = new SimpleVault(IERC20(address(new HugeDecimalsToken())), "V", "V");
        assertEq(v.decimals(), 18);
    }

    // ------------------------------------------------------------------ totalAssets

    function test_TotalAssets_IsTheVaultsOwnBalance() public {
        usdc.mint(address(vault), 500);
        usdc.mint(address(usdc), 7); // tokens held by the token contract itself must not count
        assertEq(vault.totalAssets(), 500);
    }

    function test_TotalAssets_CountsDonationsAsYield() public {
        _deposit(alice, 100);
        usdc.mint(address(vault), 50);
        assertEq(vault.totalAssets(), 150);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 149); // the virtual share keeps a sliver
    }

    // ------------------------------------------------------------------ the empty vault

    function test_EmptyVault_EverythingIsOneToOne() public view {
        assertEq(vault.convertToShares(1_234), 1_234);
        assertEq(vault.convertToAssets(1_234), 1_234);
        assertEq(vault.previewDeposit(1_234), 1_234);
        assertEq(vault.previewMint(1_234), 1_234);
        assertEq(vault.previewWithdraw(1_234), 1_234);
        assertEq(vault.previewRedeem(1_234), 1_234);
    }

    function test_EmptyVault_FirstDepositGetsSharesOneToOne() public {
        uint256 shares = _deposit(alice, 1_000e6);
        assertEq(shares, 1_000e6);
        assertEq(vault.balanceOf(alice), 1_000e6);
        assertEq(vault.totalAssets(), 1_000e6);
    }

    // ------------------------------------------------------------------ the scenario (1,000 assets / 800 shares)

    function test_Scenario_Deposit100_Gets80Shares() public {
        _scenario();
        vm.expectEmit(true, true, false, true, address(vault));
        emit Deposit(alice, alice, 100, 80);
        vm.prank(alice);
        uint256 shares = vault.deposit(100, alice);

        assertEq(shares, 80);
        assertEq(vault.balanceOf(alice), 80);
        assertEq(usdc.balanceOf(alice), START - 100);
        assertEq(vault.totalAssets(), 1_100);
    }

    function test_Scenario_Mint80_Costs100() public {
        _scenario();
        vm.expectEmit(true, true, false, true, address(vault));
        emit Deposit(alice, alice, 100, 80);
        vm.prank(alice);
        uint256 assets = vault.mint(80, alice);

        assertEq(assets, 100);
        assertEq(vault.balanceOf(alice), 80);
        assertEq(usdc.balanceOf(alice), START - 100);
    }

    function test_Scenario_Withdraw100_Burns81() public {
        _scenario();
        vm.expectEmit(true, true, true, true, address(vault));
        emit Withdraw(early, early, early, 100, 81);
        vm.prank(early);
        uint256 shares = vault.withdraw(100, early, early);

        assertEq(shares, 81);
        assertEq(vault.balanceOf(early), 800 - 81);
        assertEq(usdc.balanceOf(early), START - 800 + 100);
    }

    function test_Scenario_Redeem80_Pays99() public {
        _scenario();
        vm.expectEmit(true, true, true, true, address(vault));
        emit Withdraw(early, early, early, 99, 80);
        vm.prank(early);
        uint256 assets = vault.redeem(80, early, early);

        assertEq(assets, 99);
        assertEq(vault.balanceOf(early), 720);
        assertEq(usdc.balanceOf(early), START - 800 + 99);
    }

    function test_Scenario_ConvertFunctionsRoundDown() public {
        _scenario();
        assertEq(vault.convertToShares(100), 80); // 80.02
        assertEq(vault.convertToAssets(80), 99); // 99.98
    }

    // ------------------------------------------------------------------ deposit and mint

    function test_Deposit_SharesGoToTheReceiver_AssetsComeFromTheCaller() public {
        vm.expectEmit(true, true, false, true, address(vault));
        emit Deposit(alice, bob, 500, 500);
        vm.prank(alice);
        vault.deposit(500, bob);

        assertEq(vault.balanceOf(bob), 500);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(alice), START - 500);
        assertEq(usdc.balanceOf(bob), START);
    }

    function test_Mint_SharesGoToTheReceiver_AssetsComeFromTheCaller() public {
        vm.expectEmit(true, true, false, true, address(vault));
        emit Deposit(alice, bob, 500, 500);
        vm.prank(alice);
        vault.mint(500, bob);

        assertEq(vault.balanceOf(bob), 500);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(alice), START - 500);
    }

    function test_RevertWhen_Deposit_WithoutApproval() public {
        address dave = makeAddr("dave");
        usdc.mint(dave, 100);
        vm.prank(dave);
        vm.expectRevert(_insufficientAllowance(address(vault), 0, 100));
        vault.deposit(100, dave);
    }

    function test_RevertWhen_Mint_WithoutApproval() public {
        address dave = makeAddr("dave");
        usdc.mint(dave, 100);
        vm.prank(dave);
        vm.expectRevert(_insufficientAllowance(address(vault), 0, 100));
        vault.mint(100, dave);
    }

    function test_Deposit_Zero_MintsNothing_AndStillEmits() public {
        _scenario();
        vm.expectEmit(true, true, false, true, address(vault));
        emit Deposit(alice, alice, 0, 0);
        vm.prank(alice);
        assertEq(vault.deposit(0, alice), 0);
        assertEq(vault.totalSupply(), 800);
    }

    // ------------------------------------------------------------------ max functions

    function testFuzz_MaxDepositAndMaxMint_AreUnlimited(address anyone) public view {
        assertEq(vault.maxDeposit(anyone), type(uint256).max);
        assertEq(vault.maxMint(anyone), type(uint256).max);
    }

    function test_MaxWithdrawAndMaxRedeem_FollowTheOwnersShares() public {
        _scenario();
        assertEq(vault.maxRedeem(early), 800);
        assertEq(vault.maxWithdraw(early), 999); // 800 shares are worth 999.75 USDC, rounded down
        assertEq(vault.maxRedeem(alice), 0);
        assertEq(vault.maxWithdraw(alice), 0);
    }

    function test_RevertWhen_Withdraw_MoreThanMax() public {
        _scenario();
        vm.prank(early);
        vm.expectRevert(abi.encodeWithSelector(SimpleVault.Vault__ExceededMaxWithdraw.selector, early, 1_000, 999));
        vault.withdraw(1_000, early, early);
    }

    function test_RevertWhen_Redeem_MoreThanMax() public {
        _scenario();
        vm.prank(early);
        vm.expectRevert(abi.encodeWithSelector(SimpleVault.Vault__ExceededMaxRedeem.selector, early, 801, 800));
        vault.redeem(801, early, early);
    }

    function test_Withdraw_TheWholeMax_LeavesTheOwnerWithNothing() public {
        _deposit(alice, 1_000);
        vm.prank(alice);
        vault.withdraw(1_000, alice, alice);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(alice), START);
    }

    // ------------------------------------------------------------------ withdraw and redeem: who may act

    function test_Withdraw_ByTheOwner_NeedsNoAllowance() public {
        _deposit(alice, 500);
        vm.prank(alice);
        vault.withdraw(100, alice, alice);
        assertEq(vault.balanceOf(alice), 400);
        assertEq(vault.allowance(alice, alice), 0);
    }

    function test_Redeem_ByTheOwner_NeedsNoAllowance() public {
        _deposit(alice, 500);
        vm.prank(alice);
        vault.redeem(100, alice, alice);
        assertEq(vault.balanceOf(alice), 400);
    }

    function test_Withdraw_ByAnApprovedOperator_SpendsTheAllowanceInShares() public {
        _scenario();
        vm.prank(early);
        vault.approve(bob, 100);

        vm.expectEmit(true, true, true, true, address(vault));
        emit Withdraw(bob, carol, early, 100, 81);
        vm.prank(bob);
        vault.withdraw(100, carol, early);

        assertEq(vault.allowance(early, bob), 19); // 100 shares approved, 81 burned
        assertEq(vault.balanceOf(early), 719);
        assertEq(usdc.balanceOf(carol), START + 100); // assets go to the receiver
        assertEq(usdc.balanceOf(bob), START);
    }

    function test_Redeem_ByAnApprovedOperator_SpendsTheAllowance() public {
        _scenario();
        vm.prank(early);
        vault.approve(bob, 100);

        vm.expectEmit(true, true, true, true, address(vault));
        emit Withdraw(bob, carol, early, 99, 80);
        vm.prank(bob);
        vault.redeem(80, carol, early);

        assertEq(vault.allowance(early, bob), 20);
        assertEq(usdc.balanceOf(carol), START + 99);
    }

    function test_Operator_WithUnlimitedAllowance_IsNotReduced() public {
        _deposit(alice, 500);
        vm.prank(alice);
        vault.approve(bob, type(uint256).max);
        vm.prank(bob);
        vault.redeem(100, bob, alice);
        assertEq(vault.allowance(alice, bob), type(uint256).max);
    }

    function test_RevertWhen_Withdraw_ByAStranger() public {
        _deposit(alice, 500);
        vm.prank(bob);
        vm.expectRevert(_insufficientAllowance(bob, 0, 100));
        vault.withdraw(100, bob, alice);
    }

    function test_RevertWhen_Redeem_ByAnOperatorBeyondTheAllowance() public {
        _deposit(alice, 500);
        vm.prank(alice);
        vault.approve(bob, 99);
        vm.prank(bob);
        vm.expectRevert(_insufficientAllowance(bob, 99, 100));
        vault.redeem(100, bob, alice);
    }

    function test_Withdraw_ToAnotherReceiver() public {
        _deposit(alice, 500);
        vm.prank(alice);
        vault.withdraw(200, carol, alice);
        assertEq(usdc.balanceOf(carol), START + 200);
        assertEq(usdc.balanceOf(alice), START - 500);
    }

    // ------------------------------------------------------------------ the inflation (donation) attack

    function test_InflationAttack_HurtsTheVictim_ButCostsTheAttackerMore() public {
        address attacker = makeAddr("attacker");
        usdc.mint(attacker, 5_001);
        vm.startPrank(attacker);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(1, attacker);
        usdc.transfer(address(vault), 5_000); // the donation
        vm.stopPrank();

        uint256 victimShares = _deposit(alice, 5_000);

        assertEq(victimShares, 1);
        assertEq(vault.maxWithdraw(alice), 3_334); // the victim loses 1,666
        assertEq(vault.maxWithdraw(attacker), 3_334); // the attacker paid 5,001 and loses 1,667
        assertLt(vault.maxWithdraw(attacker), 5_001);
    }

    // ------------------------------------------------------------------ rounding always favours the vault

    /// Builds a random vault state: some shares outstanding, some yield (or none).
    function _randomState(uint256 deposited, uint256 yield_) internal {
        deposited = bound(deposited, 1, 1e12);
        yield_ = bound(yield_, 0, 1e12);
        _deposit(early, deposited);
        usdc.mint(address(vault), yield_);
        usdc.mint(alice, 1e30); // enough to pay for any mint at any price
    }

    function testFuzz_Rounding_PreviewsNeverFavourTheUser(uint256 deposited, uint256 yield_, uint256 x) public {
        _randomState(deposited, yield_);
        x = bound(x, 0, 1e12);

        // what you get rounds down, what you pay rounds up
        assertLe(vault.previewDeposit(x), vault.previewWithdraw(x));
        assertLe(vault.previewRedeem(x), vault.previewMint(x));
        assertEq(vault.previewDeposit(x), vault.convertToShares(x));
        assertEq(vault.previewRedeem(x), vault.convertToAssets(x));
        // a round trip never creates value
        assertLe(vault.previewRedeem(vault.previewDeposit(x)), x);
        assertGe(vault.previewMint(vault.previewWithdraw(x)), x);
    }

    function testFuzz_DepositThenRedeem_NeverReturnsMoreThanPaid(uint256 deposited, uint256 yield_, uint256 x) public {
        _randomState(deposited, yield_);
        x = bound(x, 0, 1e12);
        uint256 before = usdc.balanceOf(alice);

        vm.startPrank(alice);
        uint256 shares = vault.deposit(x, alice);
        vault.redeem(shares, alice, alice);
        vm.stopPrank();

        assertLe(usdc.balanceOf(alice), before);
    }

    function testFuzz_MintThenWithdraw_CannotTakeMoreThanPaid(uint256 deposited, uint256 yield_, uint256 s) public {
        _randomState(deposited, yield_);
        s = bound(s, 0, 1e12);

        vm.startPrank(alice);
        uint256 paid = vault.mint(s, alice);
        uint256 max = vault.maxWithdraw(alice);
        vm.stopPrank();

        assertLe(max, paid);
    }

    function testFuzz_ReturnValuesMatchThePreviews(uint256 deposited, uint256 yield_, uint256 x) public {
        _randomState(deposited, yield_);
        x = bound(x, 1, 1e10);

        uint256 expectShares = vault.previewDeposit(x);
        vm.prank(alice);
        assertEq(vault.deposit(x, alice), expectShares);

        uint256 expectAssets = vault.previewMint(x);
        vm.prank(alice);
        assertEq(vault.mint(x, alice), expectAssets);

        uint256 w = vault.maxWithdraw(alice) / 2;
        uint256 expectBurn = vault.previewWithdraw(w);
        vm.prank(alice);
        assertEq(vault.withdraw(w, alice, alice), expectBurn);

        uint256 r = vault.balanceOf(alice) / 2;
        uint256 expectOut = vault.previewRedeem(r);
        vm.prank(alice);
        assertEq(vault.redeem(r, alice, alice), expectOut);
    }

    // ------------------------------------------------------------------ differential: same results as OpenZeppelin's vault

    function _mapError(bytes memory err) internal pure returns (bytes memory) {
        if (err.length < 4) return err;
        bytes4 sel = bytes4(err);
        bytes4 mapped = sel;
        if (sel == SimpleVault.Vault__ExceededMaxDeposit.selector) {
            mapped = ERC4626.ERC4626ExceededMaxDeposit.selector;
        } else if (sel == SimpleVault.Vault__ExceededMaxMint.selector) {
            mapped = ERC4626.ERC4626ExceededMaxMint.selector;
        } else if (sel == SimpleVault.Vault__ExceededMaxWithdraw.selector) {
            mapped = ERC4626.ERC4626ExceededMaxWithdraw.selector;
        } else if (sel == SimpleVault.Vault__ExceededMaxRedeem.selector) {
            mapped = ERC4626.ERC4626ExceededMaxRedeem.selector;
        }
        bytes memory out = err;
        assembly {
            mstore(add(out, 0x20), or(and(mload(add(out, 0x20)), not(shl(224, 0xffffffff))), mapped))
        }
        return out;
    }

    function testFuzz_Differential_BehavesExactlyLikeOpenZeppelin(uint8[16] memory ops, uint64[16] memory amounts)
        public
    {
        MockERC20 ozAsset = new MockERC20(6);
        OZVault oz = new OZVault(IERC20(address(ozAsset)));
        address[3] memory users = [alice, bob, carol];
        for (uint256 i = 0; i < users.length; i++) {
            ozAsset.mint(users[i], START);
            vm.startPrank(users[i]);
            ozAsset.approve(address(oz), type(uint256).max);
            // bob may act for alice in both vaults
            if (users[i] == alice) {
                vault.approve(bob, 1e15);
                oz.approve(bob, 1e15);
            }
            vm.stopPrank();
        }

        for (uint256 i = 0; i < ops.length; i++) {
            address who = users[ops[i] % 3];
            uint256 x = uint256(amounts[i]) % 1e13;
            uint256 op = (ops[i] / 3) % 7;

            if (op == 6) {
                usdc.mint(address(vault), x % 1e9); // same donation to both
                ozAsset.mint(address(oz), x % 1e9);
            } else {
                // op 4 and 5: bob withdraws / redeems on alice's behalf
                address owner = op >= 4 ? alice : who;
                address caller = op >= 4 ? bob : who;
                bytes memory call;
                if (op == 0) call = abi.encodeCall(IERC4626.deposit, (x, who));
                else if (op == 1) call = abi.encodeCall(IERC4626.mint, (x, who));
                else if (op == 2 || op == 4) call = abi.encodeCall(IERC4626.withdraw, (x, caller, owner));
                else call = abi.encodeCall(IERC4626.redeem, (x, caller, owner));

                vm.prank(caller);
                (bool okMine, bytes memory outMine) = address(vault).call(call);
                vm.prank(caller);
                (bool okOz, bytes memory outOz) = address(oz).call(call);

                assertEq(okMine, okOz, "one vault reverted and the other did not");
                if (okMine) assertEq(outMine, outOz, "different return value");
                else assertEq(_mapError(outMine), outOz, "different error");
            }

            assertEq(vault.totalAssets(), oz.totalAssets());
            assertEq(vault.totalSupply(), oz.totalSupply());
            for (uint256 j = 0; j < users.length; j++) {
                assertEq(vault.balanceOf(users[j]), oz.balanceOf(users[j]));
                assertEq(usdc.balanceOf(users[j]), ozAsset.balanceOf(users[j]));
                assertEq(vault.maxWithdraw(users[j]), oz.maxWithdraw(users[j]));
            }
            assertEq(vault.allowance(alice, bob), oz.allowance(alice, bob));
            assertEq(vault.previewMint(x), oz.previewMint(x));
            assertEq(vault.previewWithdraw(x), oz.previewWithdraw(x));
        }
    }

    // ------------------------------------------------------------------ order of operations (seen from a token with hooks)

    function test_Order_AssetsArePulledInBeforeSharesAreMinted() public {
        SnoopingToken snoop = new SnoopingToken();
        SimpleVault v = new SimpleVault(IERC20(address(snoop)), "V", "V");
        snoop.setVault(address(v));
        snoop.mint(alice, 1_000);
        vm.startPrank(alice);
        snoop.approve(address(v), type(uint256).max);
        v.deposit(1_000, alice);
        vm.stopPrank();
        assertEq(snoop.supplyWhenPulledIn(), 0); // no shares existed yet while the assets moved
    }

    function test_Order_SharesAreBurnedBeforeAssetsArePaidOut() public {
        SnoopingToken snoop = new SnoopingToken();
        SimpleVault v = new SimpleVault(IERC20(address(snoop)), "V", "V");
        snoop.setVault(address(v));
        snoop.mint(alice, 1_000);
        vm.startPrank(alice);
        snoop.approve(address(v), type(uint256).max);
        v.deposit(1_000, alice);
        v.withdraw(400, alice, alice);
        vm.stopPrank();
        assertEq(snoop.supplyWhenPaidOut(), 600); // the 400 shares were already gone while the assets moved
    }
}
