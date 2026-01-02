// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IStablecoinRegistry.sol";

/**
 * @title StablecoinRegistry
 * @notice Registry for supported stablecoins with hardcoded exchange rates
 * @dev Manages 7 stablecoins: USDC, USDT, IDRX, JPYC, EUROC, MXNT, CNHT
 * 
 * Exchange Rate Format:
 * - All rates are stored with 8 decimals precision
 * - Use USD as base curency for convert
 * - Rate represents how many units of the stablecoin equal 1 USD
 * - Examples:
 *   - USDC: 1e8 (1 USDC = 1 USD)
 *   - IDRX: 16000e8 (16,000 IDRX = 1 USD)
 *   - JPYC: 150e8 (150 JPYC = 1 USD)
 */
contract StablecoinRegistry is IStablecoinRegistry, Ownable, Pausable {
    uint256 public constant RATE_PRECISION = 1e8; // 8 decimal
    uint256 public constant MIN_RATE_TO_USD = 1e4; // 0.0001 USD minimum
    uint256 public constant MAX_RATE_TO_USD = 1e16; // 100,000,000 units per USD max
    uint256 public constant MAX_RATE_CHANGE_BPS = 5000;
    uint256 public constant BPS_DENOMINATOR = 10000; // basis point denominator
    uint256 public constant MIN_ETH_USD_RATE = 1000e8;
    uint256 public constant MAX_ETH_USD_RATE = 100000e8;

    /// @notice rate eth ke usd -> $3000 - manual update
    uint256 public ethUsdRate = 3000e8;

    mapping(address => StablecoinInfo) private stablecoins;
    mapping(address => bool) private isRegistered;
    address[] private registeredTokens;

    event EthUsdRateUpdated(uint256 oldRate, uint256 newRate);

    /**
    * @notice Initialize the registry
    */
    constructor() Ownable(msg.sender) {}

    function registerStablecoin (
        address token,
        string calldata symbol,
        string calldata region,
        uint256 rateToUSD
    ) external onlyOwner {
        require(token != address(0), "Registry: invalid token address");
        require(rateToUSD >= MIN_RATE_TO_USD, "Registry: rate too low");
        require(rateToUSD <= MAX_RATE_TO_USD, "Registry: rate too high");
        require(!isRegistered[token], "Registry: token already registered");

        uint8 tokenDecimals = IERC20Metadata(token).decimals();

        string memory contractSymbol = IERC20Metadata(token).symbol();
        require(bytes(contractSymbol).length > 0, "Registry: invalid token contract");

        stablecoins[token] = StablecoinInfo({
            tokenAddress: token,
            symbol: symbol,
            decimals: tokenDecimals,
            region: region,
            rateToUSD: rateToUSD,
            isActive: true
        });
        
        registeredTokens.push(token);
        isRegistered[token] = true;
        
        emit StablecoinRegistered(token, symbol, tokenDecimals, region, rateToUSD);
    }

    /**
     * @notice Batch register multiple stablecoins
     * @param tokens Array token address
     * @param symbols Array symbol
     * @param regions Array region
     * @param rates Array rates to USD
     */
    function batchRegisterStablecoins(
        address[] calldata tokens,
        string[] calldata symbols,
        string[] calldata regions,
        uint256[] calldata rates
    ) external onlyOwner {
        require(
            tokens.length == symbols.length &&
            tokens.length == regions.length &&
            tokens.length == rates.length,
            "Registry: array length mismatch"
        );
        for (uint256 i = 0; i < tokens.length; i++) {
            require(tokens[i] != address(0), "Registry: invalid token address");
            require(rates[i] >= MIN_RATE_TO_USD, "Registry: rate too low");
            require(rates[i] <= MAX_RATE_TO_USD, "Registry: rate too high");
            require(!isRegistered[tokens[i]], "Registry: token already registered");
            
            // Auto-detect decimals from token contract
            uint8 tokenDecimals = IERC20Metadata(tokens[i]).decimals();
            
            stablecoins[tokens[i]] = StablecoinInfo({
                tokenAddress: tokens[i],
                symbol: symbols[i],
                decimals: tokenDecimals,
                region: regions[i],
                rateToUSD: rates[i],
                isActive: true
            });
            
            registeredTokens.push(tokens[i]);
            isRegistered[tokens[i]] = true;
            
            emit StablecoinRegistered(
                tokens[i], 
                symbols[i], 
                tokenDecimals, 
                regions[i], 
                rates[i]
            );
        }
    }

    /**
     * @notice Update exchange rate for a stablecoin to USD
     * @param token Token address
     * @param newRate New exchange rate (with 8 decimals)
     */
    function updateRate(address token, uint256 newRate) external onlyOwner {
        require(isRegistered[token], "Registry: token not registered");
        require(newRate >= MIN_RATE_TO_USD, "Registry: rate too low");
        require(newRate <= MAX_RATE_TO_USD, "Registry: rate too high");
        
        uint256 oldRate = stablecoins[token].rateToUSD;
        
        // Check rate change limit 
        uint256 maxChange = oldRate * MAX_RATE_CHANGE_BPS / BPS_DENOMINATOR;
        uint256 diff = newRate > oldRate ? newRate - oldRate : oldRate - newRate;
        require(diff <= maxChange, "Registry: rate change too large");
        
        stablecoins[token].rateToUSD = newRate;
        
        emit RateUpdated(token, oldRate, newRate);
    }

    /**
     * @notice Batch update rates for multiple stablecoins
     * @param tokens Array token addresse
     * @param newRates Array new rates
     */
    function batchUpdateRates(
        address[] calldata tokens,
        uint256[] calldata newRates
    ) external onlyOwner {
        require(tokens.length == newRates.length, "Registry: array length mismatch");
        
        for (uint256 i = 0; i < tokens.length; i++) {
            require(isRegistered[tokens[i]], "Registry: token not registered");
            require(newRates[i] >= MIN_RATE_TO_USD, "Registry: rate too low");
            require(newRates[i] <= MAX_RATE_TO_USD, "Registry: rate too high");
            
            uint256 oldRate = stablecoins[tokens[i]].rateToUSD;
            
            // Check rate change limit
            uint256 maxChange = oldRate * MAX_RATE_CHANGE_BPS / BPS_DENOMINATOR;
            uint256 diff = newRates[i] > oldRate ? newRates[i] - oldRate : oldRate - newRates[i];
            require(diff <= maxChange, "Registry: rate change too large");
            
            stablecoins[tokens[i]].rateToUSD = newRates[i];
            
            emit RateUpdated(tokens[i], oldRate, newRates[i]);
        }
    }

    /**
     * @notice Set stablecoin active status
     * @param token Token address
     * @param isActive status
     */
    function setStablecoinStatus(address token, bool isActive) external onlyOwner {
        require(isRegistered[token], "Registry: token not registered");
        
        stablecoins[token].isActive = isActive;
        
        emit StablecoinStatusUpdated(token, isActive);
    }

    /**
     * @notice Update ETH/USD rate
     * @param newRate New ETH/USD rate (with 8 decimals)
     */
    function setEthUsdRate(uint256 newRate) external onlyOwner {
        require(newRate >= MIN_ETH_USD_RATE, "Registry: rate too low");
        require(newRate <= MAX_ETH_USD_RATE, "Registry: rate too high");
        
        uint256 oldRate = ethUsdRate;
        ethUsdRate = newRate;
        
        emit EthUsdRateUpdated(oldRate, newRate);
    }

    /**
     * @notice Convert amount between two stablecoins
     * @dev Uses USD as intermediate for conversion. Pausable for emergency.
     * @param fromToken Source token
     * @param toToken Destination token
     * @param amount Amount to convert (in fromToken decimals)
     * @return convertedAmount Amount in destination token decimals
     */
    function convert(
        address fromToken,
        address toToken,
        uint256 amount
    ) external view override whenNotPaused returns (uint256 convertedAmount) {
        require(isRegistered[fromToken], "Registry: fromToken not registered");
        require(isRegistered[toToken], "Registry: toToken not registered");
        
        if (fromToken == toToken) {
            return amount;
        }
        
        StablecoinInfo memory fromInfo = stablecoins[fromToken];
        StablecoinInfo memory toInfo = stablecoins[toToken];
        
        // Convert to USD value (with maximum precision)
        // To avoid precision loss, we use a high precision intermediate
        uint256 usdValue18 = amount * 1e18 * RATE_PRECISION / fromInfo.rateToUSD;
        usdValue18 = usdValue18 * 1e18 / (10 ** fromInfo.decimals) / 1e18;
        
        // Convert USD to toToken
        convertedAmount = usdValue18 * toInfo.rateToUSD * (10 ** toInfo.decimals) / RATE_PRECISION / 1e18;
        
        return convertedAmount;
    }

    /**
     * @notice Convert ETH amount to stablecoin
     * @dev Pausable for emergency
     * @param token Stablecoin address
     * @param ethAmount Amount in wei (18 decimals)
     * @return tokenAmount Amount in token decimals
     */
    function ethToToken(
        address token,
        uint256 ethAmount
    ) external view override whenNotPaused returns (uint256 tokenAmount) {
        require(isRegistered[token], "Registry: token not registered");
        
        StablecoinInfo memory info = stablecoins[token];
        
        // ETH to USD value (8 decimals precision)
        uint256 usdValue = ethAmount * ethUsdRate / 1e18;
        
        // USD to token amount
        tokenAmount = usdValue * info.rateToUSD * (10 ** info.decimals) / RATE_PRECISION / RATE_PRECISION;
        
        return tokenAmount;
    }

    /**
     * @notice Convert stablecoin amount to ETH
     * @param token Stablecoin address
     * @param tokenAmount Amount in token decimals
     * @return ethAmount Amount in wei
     */
    function tokenToEth(
        address token,
        uint256 tokenAmount
    ) external view whenNotPaused returns (uint256 ethAmount) {
        require(isRegistered[token], "Registry: token not registered");
        
        StablecoinInfo memory info = stablecoins[token];
        
        // Token to USD value
        uint256 usdValue = tokenAmount * RATE_PRECISION * RATE_PRECISION / info.rateToUSD / (10 ** info.decimals);
        
        // USD to ETH
        ethAmount = usdValue * 1e18 / ethUsdRate;
        
        return ethAmount;
    }

    /**
     * @notice Get stablecoin info
     * @param token Token address
     * @return info Stablecoin information
     */
    function getStablecoin(address token) external view override returns (StablecoinInfo memory info) {
        require(isRegistered[token], "Registry: token not registered");
        return stablecoins[token];
    }

    /**
     * @notice Get all registered stablecoins
     * @return tokens Array of token addresses
     */
    function getAllStablecoins() external view override returns (address[] memory tokens) {
        return registeredTokens;
    }

    /**
     * @notice Get all active stablecoins
     * @return tokens Array of active token addresses
     */
    function getActiveStablecoins() external view returns (address[] memory tokens) {
        uint256 activeCount = 0;
        
        // Count active tokens
        for (uint256 i = 0; i < registeredTokens.length; i++) {
            if (stablecoins[registeredTokens[i]].isActive) {
                activeCount++;
            }
        }
        
        // Build active tokens array
        tokens = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < registeredTokens.length; i++) {
            if (stablecoins[registeredTokens[i]].isActive) {
                tokens[index] = registeredTokens[i];
                index++;
            }
        }
        
        return tokens;
    }

    /**
     * @notice Get number of registered stablecoins
     * @return count Number of registered tokens
     */
    function getStablecoinCount() external view returns (uint256 count) {
        return registeredTokens.length;
    }

    /**
     * @notice Get stablecoin info by index
     * @param index Index in the registered tokens array
     * @return info Stablecoin information
     */
    function getStablecoinByIndex(uint256 index) external view returns (StablecoinInfo memory info) {
        require(index < registeredTokens.length, "Registry: index out of bounds");
        return stablecoins[registeredTokens[index]];
    }

    /**
     * @notice Get conversion quote with details
     * @param fromToken Source token
     * @param toToken Destination token
     * @param amount Amount to convert
     * @return toAmount Converted amount
     * @return fromRate Source token rate to USD
     * @return toRate Destination token rate to USD
     */
    function getConversionQuote(
        address fromToken,
        address toToken,
        uint256 amount
    ) external view returns (
        uint256 toAmount,
        uint256 fromRate,
        uint256 toRate
    ) {
        require(isRegistered[fromToken], "Registry: fromToken not registered");
        require(isRegistered[toToken], "Registry: toToken not registered");
        
        fromRate = stablecoins[fromToken].rateToUSD;
        toRate = stablecoins[toToken].rateToUSD;
        toAmount = this.convert(fromToken, toToken, amount);
        
        return (toAmount, fromRate, toRate);
    }

    /**
     * @notice Get stablecoins by region
     * @param region Region code (e.g., "US", "ID")
     * @return tokens Array of token addresses in that region
     */
    function getStablecoinsByRegion(string calldata region) external view returns (address[] memory tokens) {
        uint256 count = 0;
        
        // Count tokens in region
        for (uint256 i = 0; i < registeredTokens.length; i++) {
            if (keccak256(bytes(stablecoins[registeredTokens[i]].region)) == keccak256(bytes(region))) {
                count++;
            }
        }
        
        // Build tokens array
        tokens = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < registeredTokens.length; i++) {
            if (keccak256(bytes(stablecoins[registeredTokens[i]].region)) == keccak256(bytes(region))) {
                tokens[index] = registeredTokens[i];
                index++;
            }
        }
        
        return tokens;
    }

    /**
     * @notice Get rate bounds for transparency
     */
    function getRateBounds() external pure returns (
        uint256 minRateToUsd,
        uint256 maxRateToUsd,
        uint256 maxChangeBps,
        uint256 minEthRate,
        uint256 maxEthRate
    ) {
        return (MIN_RATE_TO_USD, MAX_RATE_TO_USD, MAX_RATE_CHANGE_BPS, MIN_ETH_USD_RATE, MAX_ETH_USD_RATE);
    }

    /**
     * @notice Check if a stablecoin is registered and active
     * @param token Token address
     * @return Whether the stablecoin is active
     */
    function isStablecoinActive(address token) external view override returns (bool) {
        return isRegistered[token] && stablecoins[token].isActive;
    }

    /**
     * @notice Check if a stablecoin is registered (regardless of active status)
     * @param token Token address
     * @return Whether the stablecoin is registered
     */
    function isStablecoinRegistered(address token) external view returns (bool) {
        return isRegistered[token];
    }

    /**
     * @notice Pause contract in case of emergency
     * @dev Stops convert and ethToToken functions
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
