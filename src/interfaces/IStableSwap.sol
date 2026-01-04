// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStableSwap {
    event Swap(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut, uint256 fee);

    function swap(uint256 amountIn, address tokenIn, address tokenOut, uint256 minAmountOut) external returns (uint256 amountOut);

    function getSwapQuote(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256 amountOut, uint256 fee, uint256 totalUserPays);
    function reserves(address token) external view returns (uint256);
}