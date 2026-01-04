// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IStableSwap.sol";
import "../interfaces/IStablecoinRegistry.sol";


contract StableSwap is IStableSwap, Ownable {
    IStablecoinRegistry public registry;

    mapping(address => uint256) public collectedFees;
    mapping(address => uint256) public reserves;

    uint256 public constant SWAP_FEE = 10;

    event Deposit(address indexed token, uint256 amount);
    event Withdraw(address indexed token, uint256 amount);
    event FeesWithdrawn(address indexed token, uint256 amount);

    error InvalidRegistry();
    error InvalidSwap();
    error InvalidAmount();
    error InsufficientBalance();
    error NoFeesToWithdraw();
    error TokenNotActive();
    error SlippageExceeded();

    constructor(address _registry) Ownable(msg.sender) {
        registry = IStablecoinRegistry(_registry);
    }

    function deposit(address token, uint256 amount) external onlyOwner {
        if(amount == 0) revert InvalidAmount();
        if(registry.isStablecoinActive(token) == false) revert InvalidRegistry();

        IERC20(token).transferFrom(msg.sender, address(this), amount);
        reserves[token] += amount;

        emit Deposit(token, amount);
    }

    function withdraw(address token, uint256 amount) external onlyOwner{
        if(amount == 0) revert InvalidAmount();
        if(!registry.isStablecoinActive(token)) revert InvalidRegistry();
        if(reserves[token] < amount) revert InsufficientBalance();

        reserves[token] -= amount;
        IERC20(token).transfer(msg.sender, amount);

        emit Withdraw(token, amount);
    }

    function withdrawFees(address token) external onlyOwner {
        uint256 fees = collectedFees[token];
        if(fees == 0) revert NoFeesToWithdraw();
        
        collectedFees[token] = 0;
        IERC20(token).transfer(msg.sender, fees);

        emit FeesWithdrawn(token, fees);

    }

    function getSwapQuote(address tokenIn, address tokenOut, uint256 amountIn) external view override returns(uint256 amountOut, uint256 fee, uint256 totalUserPays)  {
        fee = amountIn * SWAP_FEE / 10000;

        totalUserPays = amountIn + fee;

        amountOut = registry.convert(tokenIn, tokenOut, amountIn);
    }

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