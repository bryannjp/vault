// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract SimpleVault is ERC20, IERC4626, Ownable2Step, Pausable {
    uint256 public depositCap;
    uint256 public dailyLimit;
    uint256 public currentDay; // today’s day number
    uint256 public claimedToday; // today’s usage
    uint256 public totalPending; // all reserved, unclaimed assets
    uint256 public immutable withdrawalDelay;

    struct WithdrawalRequest {
        uint256 assets;
        uint256 claimableAt;
    }
    mapping(address => WithdrawalRequest) public requests;

    uint256 public constant MAX_WITHDRAWAL_DELAY = 30 days;

    IERC20 private immutable i_asset;
    uint8 private immutable i_underlyingDecimals;

    event DepositCapChanged(uint256 oldCap, uint256 newCap);
    event DailyLimitChanged(uint256 oldLimit, uint256 newLimit);
    event WithdrawalRequested(address indexed owner, uint256 shares, uint256 assets, uint256 claimableAt);
    event WithdrawalClaimed(address indexed owner, address indexed receiver, uint256 assets);

    error ZeroAddress();
    error Vault__ExceededMaxDeposit(address receiver, uint256 assets, uint256 maxDeposit);
    error Vault__ExceededMaxMint(address receiver, uint256 shares, uint256 maxMint);
    error Vault__RenounceDisabled();
    error Vault__DelayTooLong(uint256 delay, uint256 max);
    error Vault__ZeroAssets();
    error Vault__RequestPending();
    error Vault__NoRequest();
    error Vault__NotClaimableYet(uint256 claimableAt);
    error Vault__ExceedsRequest(uint256 assets, uint256 requested);
    error Vault__DailyLimitExceeded(uint256 assets, uint256 remaining);
    error Vault__UseRequestRedeem();

    constructor(
        IERC20 asset_,
        string memory name,
        string memory symbol,
        address initialOwner,
        uint256 initialCap,
        uint256 delay
    ) ERC20(name, symbol) Ownable(initialOwner) {
        if (address(asset_) == address(0)) revert ZeroAddress();
        if (delay > MAX_WITHDRAWAL_DELAY) revert Vault__DelayTooLong(delay, MAX_WITHDRAWAL_DELAY);
        i_asset = asset_;
        (bool success, uint8 assetDecimals) = SafeERC20.tryGetDecimals(asset_);
        i_underlyingDecimals = success ? assetDecimals : 18;
        depositCap = initialCap;
        withdrawalDelay = delay;
        dailyLimit = type(uint256).max;
        emit DepositCapChanged(0, initialCap);
    }

    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return i_underlyingDecimals;
    }

    function setDepositCap(uint256 newCap) external onlyOwner {
        uint256 oldCap = depositCap;
        depositCap = newCap;
        emit DepositCapChanged(oldCap, newCap);
    }

    function setDailyLimit(uint256 newLimit) external onlyOwner {
        uint256 oldLimit = dailyLimit;
        dailyLimit = newLimit;
        emit DailyLimitChanged(oldLimit, newLimit);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function asset() external view returns (address assetTokenAddress) {
        return address(i_asset);
    }

    function totalAssets() public view returns (uint256 totalManagedAssets) {
        return i_asset.balanceOf(address(this)) - totalPending;
    }

    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        return _toShares(assets, Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        return _toAssets(shares, Math.Rounding.Floor);
    }

    function previewDeposit(uint256 assets) public view returns (uint256 shares) {
        return _toShares(assets, Math.Rounding.Floor);
    }

    function previewMint(uint256 shares) public view returns (uint256 assets) {
        return _toAssets(shares, Math.Rounding.Ceil);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256 shares) {
        return _toShares(assets, Math.Rounding.Ceil);
    }

    function previewRedeem(uint256 shares) public view returns (uint256 assets) {
        return _toAssets(shares, Math.Rounding.Floor);
    }

    function maxDeposit(address) public view returns (uint256 maxAssets) {
        if (paused()) return 0;
        if (depositCap == type(uint256).max) return type(uint256).max;
        if (totalAssets() > depositCap) return 0;
        return depositCap - totalAssets();
    }

    function maxMint(address receiver) public view returns (uint256 maxShares) {
        uint256 room = maxDeposit(receiver);
        if (room == type(uint256).max) return type(uint256).max;
        return _toShares(room, Math.Rounding.Floor);
    }

    function maxWithdraw(address) public pure returns (uint256 maxAssets) {
        return 0;
    }

    function maxRedeem(address) public pure returns (uint256 maxShares) {
        return 0;
    }

    function deposit(uint256 assets, address receiver) external whenNotPaused returns (uint256 shares) {
        uint256 _maxDeposit = maxDeposit(receiver);
        if (assets > _maxDeposit) revert Vault__ExceededMaxDeposit(receiver, assets, _maxDeposit);
        shares = previewDeposit(assets);
        SafeERC20.safeTransferFrom(i_asset, msg.sender, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) external whenNotPaused returns (uint256 assets) {
        uint256 _maxMint = maxMint(receiver);
        if (shares > _maxMint) revert Vault__ExceededMaxMint(receiver, shares, _maxMint);
        assets = previewMint(shares);
        SafeERC20.safeTransferFrom(i_asset, msg.sender, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256, address, address) external pure returns (uint256) {
        revert Vault__UseRequestRedeem();
    }

    function redeem(uint256, address, address) external pure returns (uint256) {
        revert Vault__UseRequestRedeem();
    }

    function requestRedeem(uint256 shares) external whenNotPaused returns (uint256 assets) {
        if (requests[msg.sender].assets != 0) revert Vault__RequestPending();
        assets = previewRedeem(shares);
        if (assets == 0) revert Vault__ZeroAssets();
        _burn(msg.sender, shares);
        totalPending += assets;
        uint256 claimableAt = block.timestamp + withdrawalDelay;
        requests[msg.sender] = WithdrawalRequest(assets, claimableAt);
        emit WithdrawalRequested(msg.sender, shares, assets, claimableAt);
    }

    function claim(uint256 assets, address receiver) external whenNotPaused {
        WithdrawalRequest storage request = requests[msg.sender];
        if (request.assets == 0) revert Vault__NoRequest();
        if (block.timestamp < request.claimableAt) revert Vault__NotClaimableYet(request.claimableAt);
        if (assets == 0) revert Vault__ZeroAssets();
        if (assets > request.assets) revert Vault__ExceedsRequest(assets, request.assets);
        uint256 today = block.timestamp / 1 days;
        if (today != currentDay) {
            currentDay = today;
            claimedToday = 0;
        }
        uint256 remaining = remainingToday();
        if (assets > remaining) revert Vault__DailyLimitExceeded(assets, remaining);

        claimedToday += assets;
        request.assets -= assets;
        totalPending -= assets;
        SafeERC20.safeTransfer(i_asset, receiver, assets);
        emit WithdrawalClaimed(msg.sender, receiver, assets);
    }

    function remainingToday() public view returns (uint256) {
        uint256 today = block.timestamp / 1 days;
        uint256 used = today == currentDay ? claimedToday : 0;
        if (used > dailyLimit) return 0;
        return dailyLimit - used;
    }

    // Override it to always revert. If the owner renounced while the vault was paused,
    // nobody could ever unpause it, and every user’s funds would be locked forever.
    function renounceOwnership() public view override onlyOwner {
        revert Vault__RenounceDisabled();
    }

    function _toShares(uint256 assets, Math.Rounding rounding) private view returns (uint256) {
        return Math.mulDiv(assets, totalSupply() + 1, totalAssets() + 1, rounding);
    }

    function _toAssets(uint256 shares, Math.Rounding rounding) private view returns (uint256) {
        return Math.mulDiv(shares, totalAssets() + 1, totalSupply() + 1, rounding);
    }
}
