// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IStableSwap
 * @notice Interface for StableSwap contract that handles stablecoin swaps
 * @dev Implements a simple swap mechanism with liquidity reserves and fees
 */
interface IStableSwap {
    /**
     * @notice Emitted when a swap is executed
     * @param user Address user performing the swap
     * @param tokenIn Address input token
     * @param tokenOut Address output token
     * @param amountIn Amount input token swapped
     * @param amountOut Amount output token received
     * @param fee Fee charged the swap
     */
    event Swap(
        address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut, uint256 fee
    );

    /**
     * @notice Execute token swap
     * @param amountIn Amount input token to swap
     * @param tokenIn Address the input token
     * @param tokenOut Address the output token
     * @param minAmountOut Minimum amount output token to receive (slippage protection)
     * @return amountOut Actual amount of output token received
     */
    function swap(uint256 amountIn, address tokenIn, address tokenOut, uint256 minAmountOut)
        external
        returns (uint256 amountOut);

    /**
     * @notice Get a quote for a swap without executing
     * @param tokenIn Address input token
     * @param tokenOut Address output token
     * @param amountIn Amount input token to swap
     * @return amountOut Expected amount output token to receive
     * @return fee Fee charged for swap
     * @return totalUserPays Total amount user needs to pay (amountIn + fee)
     */
    function getSwapQuote(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256 amountOut, uint256 fee, uint256 totalUserPays);

    /**
     * @notice Get the liquidity reserve for a specific token
     * @param token Address of the token to query
     * @return Reserve amount of the token in the pool
     */
    function reserves(address token) external view returns (uint256);
}
