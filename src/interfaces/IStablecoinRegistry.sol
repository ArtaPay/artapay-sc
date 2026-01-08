// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IStablecoinRegistry
 * @notice Interface for Stablecoin Registry
 */
interface IStablecoinRegistry {
    /**
     * @notice Stablecoin information
     */
    struct StablecoinInfo {
        address tokenAddress;
        string symbol;
        uint8 decimals;
        string region;
        uint256 rateToUSD;
        bool isActive;
    }

    /**
     * @notice Emitted when a stablecoin is registered
     */
    event StablecoinRegistered(address indexed token, string symbol, uint8 decimals, string region, uint256 rateToUSD);

    /**
     * @notice Emitted when a stablecoin rate is updated
     */
    event RateUpdated(address indexed token, uint256 oldRate, uint256 newRate);

    /**
     * @notice Emitted when a stablecoin status is updated
     */
    event StablecoinStatusUpdated(address indexed token, bool isActive);

    /**
     * @notice Get stablecoin info
     * @param token Token address
     * @return info Stablecoin information
     */
    function getStablecoin(address token) external view returns (StablecoinInfo memory info);

    /**
     * @notice Check if a stablecoin is registered and active
     * @param token Token address
     * @return isActive Whether the stablecoin is active
     */
    function isStablecoinActive(address token) external view returns (bool isActive);

    /**
     * @notice Convert amount between two stablecoins
     * @param fromToken Source token
     * @param toToken Destination token
     * @param amount Amount to convert (in fromToken decimals)
     * @return convertedAmount Amount in destination token decimals
     */
    function convert(address fromToken, address toToken, uint256 amount) external view returns (uint256 convertedAmount);

    /**
     * @notice Convert ETH amount to stablecoin
     * @param token Stablecoin address
     * @param ethAmount Amount in wei
     * @return tokenAmount Amount in token decimals
     */
    function ethToToken(address token, uint256 ethAmount) external view returns (uint256 tokenAmount);

    /**
     * @notice Get all registered stablecoins
     * @return tokens Array of token addresses
     */
    function getAllStablecoins() external view returns (address[] memory tokens);
}
