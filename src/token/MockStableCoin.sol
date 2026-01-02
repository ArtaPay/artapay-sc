// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockStableCoin
 * @notice Mock stablecoin for testing with permit (ERC-2612) support and faucet rate limiting
 * @dev Supports gasless approvals via permit and includes anti-abuse faucet mechanism
 */
contract MockStableCoin is ERC20, ERC20Permit, ERC20Burnable, Ownable {
    uint8 private _decimals;
    string public countryCode;
    
    // Faucet rate limiting
    uint256 public constant FAUCET_COOLDOWN = 1 days;
    uint256 public constant MAX_FAUCET_AMOUNT = 10000; // Maximum amount per claim
    
    mapping(address => uint256) public lastFaucetClaim;
    
    // Events
    event FaucetClaimed(address indexed user, uint256 amount);
    
    // Errors
    error FaucetCooldownActive(uint256 remainingTime);
    error FaucetAmountExceeded(uint256 requested, uint256 maximum);

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
     * @notice Mint tokens (public for testing, can be restricted to owner if needed)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    /**
     * @notice Mint tokens to sender with rate limiting (convenience function for testing)
     * @param amount Amount to mint (in token units, will be multiplied by decimals)
     */
    function faucet(uint256 amount) external {
        // Check cooldown period
        uint256 timeSinceLastClaim = block.timestamp - lastFaucetClaim[msg.sender];
        if (lastFaucetClaim[msg.sender] != 0 && timeSinceLastClaim < FAUCET_COOLDOWN) {
            revert FaucetCooldownActive(FAUCET_COOLDOWN - timeSinceLastClaim);
        }
        
        // Check maximum amount
        if (amount > MAX_FAUCET_AMOUNT) {
            revert FaucetAmountExceeded(amount, MAX_FAUCET_AMOUNT);
        }
        
        // Update last claim time
        lastFaucetClaim[msg.sender] = block.timestamp;
        
        // Mint tokens
        uint256 mintAmount = amount * 10 ** _decimals;
        _mint(msg.sender, mintAmount);
        
        emit FaucetClaimed(msg.sender, mintAmount);
    }
    
    /**
     * @notice Get remaining cooldown time for an address
     * @param user Address to check
     * @return remainingTime Time remaining until next faucet claim (0 if can claim now)
     */
    function getFaucetCooldown(address user) external view returns (uint256 remainingTime) {
        if (lastFaucetClaim[user] == 0) {
            return 0;
        }
        
        uint256 timeSinceLastClaim = block.timestamp - lastFaucetClaim[user];
        if (timeSinceLastClaim >= FAUCET_COOLDOWN) {
            return 0;
        }
        
        return FAUCET_COOLDOWN - timeSinceLastClaim;
    }
    
    /**
     * @notice Check if an address can claim from faucet
     * @param user Address to check
     * @return canClaim True if user can claim, false otherwise
     */
    function canClaimFaucet(address user) external view returns (bool canClaim) {
        if (lastFaucetClaim[user] == 0) {
            return true;
        }
        
        uint256 timeSinceLastClaim = block.timestamp - lastFaucetClaim[user];
        return timeSinceLastClaim >= FAUCET_COOLDOWN;
    }
}
