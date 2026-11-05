// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";


contract SimpleVault is ERC20, IERC4626 {
    IERC20 private immutable i_asset;
    uint8 private immutable i_underlyingDecimals;

    error ZeroAddress();
    error Vault__ExceededMaxDeposit(address receiver, uint256 assets, uint256 maxDeposit);
    error Vault__ExceededMaxMint(address receiver, uint256 shares, uint256 maxMint);
    error Vault__ExceededMaxWithdraw(address owner, uint256 assets, uint256 maxWithdraw);
    error Vault__ExceededMaxRedeem(address owner, uint256 shares, uint256 maxRedeem);
    
    constructor (IERC20 asset_, string memory name, string memory symbol) ERC20(name, symbol) {
        if (address(asset_) == address(0)) revert ZeroAddress();
        i_asset = asset_;
        (bool success, uint8 assetDecimals) = SafeERC20.tryGetDecimals(asset_);
        i_underlyingDecimals = success ? assetDecimals : 18;
    }

    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return i_underlyingDecimals;
    }

    function asset() external view returns (address assetTokenAddress) {
        return address(i_asset);
    }
    function totalAssets() public view returns (uint256 totalManagedAssets) {
        return i_asset.balanceOf(address(this));
    }

    // Rounding: always favour the vault
    // Function	                            Computes	            Rounds
    // previewDeposit / deposit	            shares you get	        down
    // previewMint / mint	                assets you pay	        up
    // previewWithdraw / withdraw	        shares you burn	        up
    // previewRedeem / redeem	            assets you get	        down
    // convertToShares / convertToAssets	the average rate	    always down (spec rule)

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
    
    function maxDeposit(address /* receiver */) public pure returns (uint256 maxAssets) {
        return type(uint256).max;
    }

    function maxMint(address /* receiver */) public pure returns (uint256 maxShares) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view returns (uint256 maxAssets) {
        return _toAssets(balanceOf(owner), Math.Rounding.Floor);
    }

    function maxRedeem(address owner) public view returns (uint256 maxShares) {
        return balanceOf(owner);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        uint256 _maxDeposit = maxDeposit(receiver);
        if (assets > _maxDeposit) revert Vault__ExceededMaxDeposit(receiver, assets, _maxDeposit);
        shares = previewDeposit(assets);
        SafeERC20.safeTransferFrom(i_asset, msg.sender, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        uint256 _maxMint = maxMint(receiver);
        if (shares > _maxMint) revert Vault__ExceededMaxMint(receiver, shares, _maxMint);
        assets = previewMint(shares);
        SafeERC20.safeTransferFrom(i_asset, msg.sender, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        uint256 _maxWithdraw = maxWithdraw(owner);
        if (assets > _maxWithdraw) revert Vault__ExceededMaxWithdraw(owner, assets, _maxWithdraw);
        shares = previewWithdraw(assets);
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        SafeERC20.safeTransfer(i_asset, receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        uint256 _maxRedeem = maxRedeem(owner);
        if (shares > _maxRedeem) revert Vault__ExceededMaxRedeem(owner, shares, _maxRedeem);
        assets = previewRedeem(shares);
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        SafeERC20.safeTransfer(i_asset, receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }
    
    
    function _toShares(uint256 assets, Math.Rounding rounding) private view returns (uint256) {
        return Math.mulDiv(assets, totalSupply() + 1, totalAssets() + 1, rounding);
    }

    function _toAssets(uint256 shares, Math.Rounding rounding) private view returns (uint256) {
        return Math.mulDiv(shares, totalAssets() + 1, totalSupply() + 1, rounding);
    }
}