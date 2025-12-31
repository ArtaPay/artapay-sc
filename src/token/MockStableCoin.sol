// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockStableCoin
 * @notice Mock stablecoin for testing with permit (ERC-2612) support
 * @dev Supports gasless approvals via permit
 */
contract MockStableCoin is ERC20, ERC20Permit, ERC20Burnable, Ownable {
    uint8 private _decimals;
    string public countryCode;

    /**
     * @notice Constructor
     * @param name Token name
     * @param symbol Token symbol
     * @param decimals_ Token decimals
     * @param _countryCode Country code (e.g., "US", "ID", "JP")
     */
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        string memory _countryCode
    ) 
        ERC20(name, symbol)
        ERC20Permit(name)
        Ownable(msg.sender)
    {
        _decimals = decimals_;
        countryCode = _countryCode;
    }

    /**
     * @notice Get token decimals
     * @return Token decimals
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Mint tokens (owner only in production, public for testing)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    /**
     * @notice Mint tokens to sender (convenience function for testing)
     * @param amount Amount to mint
     */
    function faucet(uint256 amount) external {
        _mint(msg.sender, amount* 10 ** _decimals);
    }
}