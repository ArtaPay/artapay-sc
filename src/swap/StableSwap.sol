// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IStableSwap.sol";
import "../interfaces/IStablecoinRegistry.sol";

/**
 * @title StableSwap
 * @notice Liquidity pool for swapping between stablecoins with minimal fees
 * @dev Owner-managed liquidity pool that uses StablecoinRegistry for conversion rates
 */
contract StableSwap is IStableSwap, Ownable {
    /// @notice Reference to the StablecoinRegistry contract for rate conversions
    IStablecoinRegistry public registry;

    /// @notice Mapping of collected swap fees per token
    mapping(address => uint256) public collectedFees;
    
    /// @notice Mapping of liquidity reserves per token
    mapping(address => uint256) public reserves;

    /// @notice Swap fee in basis points (10 = 0.1%)
    uint256 public constant SWAP_FEE = 10;

    /**
     * @notice Emitted when liquidity is deposited to the pool
     * @param token Address of the token deposited
     * @param amount Amount of tokens deposited
     */
    event Deposit(address indexed token, uint256 amount);
    
    /**
     * @notice Emitted when liquidity is withdrawn from the pool
     * @param token Address of the token withdrawn
     * @param amount Amount of tokens withdrawn
     */
    event Withdraw(address indexed token, uint256 amount);
    
    /**
     * @notice Emitted when collected fees are withdrawn
     * @param token Address of the token
     * @param amount Amount of fees withdrawn
     */
    event FeesWithdrawn(address indexed token, uint256 amount);

    /// @notice Thrown when registry address is invalid or token is not active
    error InvalidRegistry();
    
    /// @notice Thrown when attempting to swap same token or invalid swap parameters
    error InvalidSwap();
    
    /// @notice Thrown when amount is zero or invalid
    error InvalidAmount();
    
    /// @notice Thrown when pool has insufficient balance for swap
    error InsufficientBalance();
    
    /// @notice Thrown when there are no fees to withdraw
    error NoFeesToWithdraw();
    
    /// @notice Thrown when token is not active in registry
    error TokenNotActive();
    
    /// @notice Thrown when output amount is below minimum (slippage protection)
    error SlippageExceeded();

    /**
     * @notice Initialize the StableSwap contract
     * @param _registry Address of the StablecoinRegistry contract
     */
    constructor(address _registry) Ownable(msg.sender) {
        registry = IStablecoinRegistry(_registry);
    }

    /**
     * @notice Deposit liquidity to the pool (owner only)
     * @param token Address of the token to deposit
     * @param amount Amount of tokens to deposit
     */
    function deposit(address token, uint256 amount) external onlyOwner {
        if(amount == 0) revert InvalidAmount();
        if(registry.isStablecoinActive(token) == false) revert InvalidRegistry();

        IERC20(token).transferFrom(msg.sender, address(this), amount);
        reserves[token] += amount;

        emit Deposit(token, amount);
    }

    /**
     * @notice Withdraw liquidity from the pool (owner only)
     * @param token Address of the token to withdraw
     * @param amount Amount of tokens to withdraw
     */
    function withdraw(address token, uint256 amount) external onlyOwner{
        if(amount == 0) revert InvalidAmount();
        if(!registry.isStablecoinActive(token)) revert InvalidRegistry();
        if(reserves[token] < amount) revert InsufficientBalance();

        reserves[token] -= amount;
        IERC20(token).transfer(msg.sender, amount);

        emit Withdraw(token, amount);
    }

    /**
     * @notice Withdraw all collected fees for a token (owner only)
     * @param token Address of the token to withdraw fees for
     */
    function withdrawFees(address token) external onlyOwner {
        uint256 fees = collectedFees[token];
        if(fees == 0) revert NoFeesToWithdraw();
        
        collectedFees[token] = 0;
        IERC20(token).transfer(msg.sender, fees);

        emit FeesWithdrawn(token, fees);

    }

    /**
     * @notice Get a quote for a swap without executing it
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param amountIn Amount of input token to swap
     * @return amountOut Expected amount of output token to receive
     * @return fee Fee that will be charged for the swap
     * @return totalUserPays Total amount user needs to pay (amountIn + fee)
     */
    function getSwapQuote(address tokenIn, address tokenOut, uint256 amountIn) external view override returns(uint256 amountOut, uint256 fee, uint256 totalUserPays)  {
        fee = amountIn * SWAP_FEE / 10000;

        totalUserPays = amountIn + fee;

        amountOut = registry.convert(tokenIn, tokenOut, amountIn);
    }

    /**
     * @notice Execute a token swap
     * @dev User must approve this contract to spend tokenIn before calling
     * @param amountIn Amount of input token to swap
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param minAmountOut Minimum amount of output token to receive (slippage protection)
     * @return amountOut Actual amount of output token received
     */
    function swap(uint256 amountIn, address tokenIn, address tokenOut, uint256 minAmountOut) external returns (uint256 amountOut) {
        if(!registry.isStablecoinActive(tokenIn)) revert TokenNotActive();
        if(!registry.isStablecoinActive(tokenOut)) revert TokenNotActive();

        if(tokenIn == tokenOut) revert InvalidSwap();
        if(amountIn == 0) revert InvalidAmount(); 

        uint256 fee = amountIn * SWAP_FEE / 10000;
        amountOut = registry.convert(tokenIn, tokenOut, amountIn); 

        uint256 totalUserPays = amountIn + fee;

        if(amountOut < minAmountOut) revert SlippageExceeded();

        if(reserves[tokenOut] < amountOut) revert InsufficientBalance();

        reserves[tokenIn] += totalUserPays;
        reserves[tokenOut] -= amountOut;
        collectedFees[tokenIn] += fee;

        IERC20(tokenIn).transferFrom(msg.sender, address(this), totalUserPays);
        IERC20(tokenOut).transfer(msg.sender, amountOut);

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut, fee);
    }
}