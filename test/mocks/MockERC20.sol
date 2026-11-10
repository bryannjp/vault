// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// Plain mintable ERC-20 with configurable decimals, for tests only.
contract MockERC20 is ERC20 {
    uint8 private immutable i_decimals;

    constructor(uint8 decimals_) ERC20("Mock USD", "mUSD") {
        i_decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return i_decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// Has no decimals() at all.
contract NoDecimalsToken {}

/// decimals() returns a value that does not fit in uint8.
contract HugeDecimalsToken {
    function decimals() external pure returns (uint256) {
        return 300;
    }
}

/// An asset that looks at the vault in the middle of every transfer, like an ERC-777 hook would.
/// It records the vault's share supply at the moment its own balances move.
contract SnoopingToken is ERC20 {
    address public vault;
    uint256 public supplyWhenPulledIn = type(uint256).max;
    uint256 public supplyWhenPaidOut = type(uint256).max;
    uint256 public pendingWhenPaidOut = type(uint256).max;

    constructor() ERC20("Snoop", "SNP") {}

    function setVault(address vault_) external {
        vault = vault_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (vault == address(0) || from == address(0)) return;
        if (to == vault) supplyWhenPulledIn = ERC20(vault).totalSupply();
        if (from == vault) {
            supplyWhenPaidOut = ERC20(vault).totalSupply();
            (bool ok, bytes memory data) = vault.staticcall(abi.encodeWithSignature("totalPending()"));
            if (ok && data.length == 32) pendingWhenPaidOut = abi.decode(data, (uint256));
        }
    }
}
