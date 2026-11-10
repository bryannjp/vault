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

    function setUp() public {
        usdc = new MockERC20(6);
        vault =
            new SimpleVault(IERC20(address(usdc)), "Simple Vault USDC", "svUSDC", address(this), type(uint256).max, 0);
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

    /// Exits through the v3 flow. The delay is 0 in this file, so the claim works at once.
    function _exit(address who, uint256 shares) internal returns (uint256 assets) {
        vm.startPrank(who);
        assets = vault.requestRedeem(shares);
        vault.claim(assets, who);
        vm.stopPrank();
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
        new SimpleVault(IERC20(address(0)), "V", "V", address(this), type(uint256).max, 0);
    }

    function testFuzz_Decimals_FollowTheAsset(uint8 assetDecimals) public {
        MockERC20 token = new MockERC20(assetDecimals);
        SimpleVault v = new SimpleVault(IERC20(address(token)), "V", "V", address(this), type(uint256).max, 0);
        assertEq(v.decimals(), assetDecimals);
    }

    function test_Decimals_FallBackTo18_WhenTheAssetHasNoCode() public {
        SimpleVault v =
            new SimpleVault(IERC20(makeAddr("not a contract")), "V", "V", address(this), type(uint256).max, 0);
        assertEq(v.decimals(), 18);
    }

    function test_Decimals_FallBackTo18_WhenTheAssetHasNoDecimalsFunction() public {
        SimpleVault v =
            new SimpleVault(IERC20(address(new NoDecimalsToken())), "V", "V", address(this), type(uint256).max, 0);
        assertEq(v.decimals(), 18);
    }

    function test_Decimals_FallBackTo18_WhenTheAssetsDecimalsDoNotFitInUint8() public {
        SimpleVault v =
            new SimpleVault(IERC20(address(new HugeDecimalsToken())), "V", "V", address(this), type(uint256).max, 0);
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

    function test_Scenario_PreviewWithdraw100_Burns81() public {
        _scenario();
        assertEq(vault.previewWithdraw(100), 81); // 80.02 shares, rounded up
    }

    function test_Scenario_Request80Shares_Reserves99_ThenPays99() public {
        _scenario();
        vm.prank(early);
        uint256 assets = vault.requestRedeem(80);
        assertEq(assets, 99); // 99.98, rounded down
        assertEq(vault.balanceOf(early), 720);

        vm.prank(early);
        vault.claim(99, early);
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

    function testFuzz_MaxWithdrawAndMaxRedeem_AreAlwaysZero(address anyone) public {
        _scenario();
        assertEq(vault.maxWithdraw(anyone), 0);
        assertEq(vault.maxRedeem(anyone), 0);
        assertEq(vault.maxWithdraw(early), 0); // even for someone holding shares
    }

    function test_RevertWhen_SyncWithdrawOrRedeem_AnyCallerAnyAmount() public {
        _scenario();
        vm.startPrank(early);
        vm.expectRevert(SimpleVault.Vault__UseRequestRedeem.selector);
        vault.withdraw(1, early, early);
        vm.expectRevert(SimpleVault.Vault__UseRequestRedeem.selector);
        vault.redeem(1, early, early);
        vm.expectRevert(SimpleVault.Vault__UseRequestRedeem.selector);
        vault.withdraw(0, early, early);
        vm.stopPrank();
    }

    function test_FullExit_ReturnsEverything() public {
        uint256 shares = _deposit(alice, 1_000);
        _exit(alice, shares);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(alice), START);
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
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 3_334); // the victim loses 1,666
        assertEq(vault.convertToAssets(vault.balanceOf(attacker)), 3_334); // the attacker paid 5,001 and loses 1,667
        assertLt(vault.convertToAssets(vault.balanceOf(attacker)), 5_001);
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

    function testFuzz_DepositThenExit_NeverReturnsMoreThanPaid(uint256 deposited, uint256 yield_, uint256 x) public {
        _randomState(deposited, yield_);
        x = bound(x, 0, 1e12);
        uint256 before = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 shares = vault.deposit(x, alice);
        if (vault.previewRedeem(shares) > 0) _exit(alice, shares);

        assertLe(usdc.balanceOf(alice), before);
    }

    function testFuzz_MintThenExit_CannotTakeMoreThanPaid(uint256 deposited, uint256 yield_, uint256 s) public {
        _randomState(deposited, yield_);
        s = bound(s, 0, 1e12);

        vm.prank(alice);
        uint256 paid = vault.mint(s, alice);

        assertLe(vault.previewRedeem(s), paid);
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

        uint256 r = vault.balanceOf(alice) / 2;
        uint256 expectOut = vault.previewRedeem(r);
        if (expectOut > 0) {
            vm.prank(alice);
            assertEq(vault.requestRedeem(r), expectOut);
        }
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
            vm.stopPrank();
        }

        for (uint256 i = 0; i < ops.length; i++) {
            address who = users[ops[i] % 3];
            uint256 x = uint256(amounts[i]) % 1e13;
            uint256 op = (ops[i] / 3) % 3;

            if (op == 2) {
                usdc.mint(address(vault), x % 1e9); // same donation to both
                ozAsset.mint(address(oz), x % 1e9);
            } else {
                // exits work differently by design in v3, so only the entry paths are compared
                bytes memory call =
                    op == 0 ? abi.encodeCall(IERC4626.deposit, (x, who)) : abi.encodeCall(IERC4626.mint, (x, who));

                vm.prank(who);
                (bool okMine, bytes memory outMine) = address(vault).call(call);
                vm.prank(who);
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
                assertEq(vault.convertToAssets(vault.balanceOf(users[j])), oz.convertToAssets(oz.balanceOf(users[j])));
            }
            assertEq(vault.previewRedeem(x), oz.previewRedeem(x));
            assertEq(vault.previewMint(x), oz.previewMint(x));
            assertEq(vault.previewWithdraw(x), oz.previewWithdraw(x));
        }
    }

    // ------------------------------------------------------------------ order of operations (seen from a token with hooks)

    function test_Order_AssetsArePulledInBeforeSharesAreMinted() public {
        SnoopingToken snoop = new SnoopingToken();
        SimpleVault v = new SimpleVault(IERC20(address(snoop)), "V", "V", address(this), type(uint256).max, 0);
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
        SimpleVault v = new SimpleVault(IERC20(address(snoop)), "V", "V", address(this), type(uint256).max, 0);
        snoop.setVault(address(v));
        snoop.mint(alice, 1_000);
        vm.startPrank(alice);
        snoop.approve(address(v), type(uint256).max);
        v.deposit(1_000, alice);
        v.requestRedeem(400);
        v.claim(400, alice);
        vm.stopPrank();
        assertEq(snoop.supplyWhenPaidOut(), 600); // the 400 shares were already gone while the assets moved
        assertEq(snoop.pendingWhenPaidOut(), 0); // and the request was already settled (no double claim)
    }
}
