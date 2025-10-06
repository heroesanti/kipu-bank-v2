// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockToken
/// @notice A mock ERC20 token for testing purposes
/// @dev This contract inherits from OpenZeppelin's ERC20, Ownable, ERC20Burnable, and ERC20Permit contracts
contract MockToken is ERC20, Ownable, ERC20Burnable, ERC20Permit {
    /// @notice Constructor function to initialize the contract
    /// @param initialOwner The address of the initial owner
    constructor(address initialOwner) ERC20("Mock Token", "MTK") Ownable(initialOwner) ERC20Permit("Mock Token") {
        _mint(msg.sender, 1000000 * 10**decimals());
    }

    /// @notice Mints new tokens and assigns them to the specified address
    /// @param to The address to receive the minted tokens
    /// @param amount The amount of tokens to mint
    /// @dev Only callable by the owner
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function getName() external view returns (string memory) {
        return name();
    }

    function getSymbol() external view returns (string memory) {
        return symbol();
    }

    function getDecimals() external view returns (uint8) {
        return decimals();
    }

    function getTotalSupply() external view returns (uint256) {
        return totalSupply();
    }

    function getBalanceOf(address account) external view returns (uint256) {
        return balanceOf(account);
    }

    function getAllowance(address owner, address spender) external view returns (uint256) {
        return allowance(owner, spender);
    }
}
