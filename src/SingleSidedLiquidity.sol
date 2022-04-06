// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "v3-periphery/interfaces/IQuoterV2.sol";
import "v3-core/libraries/TickMath.sol";
import "v3-core/interfaces/IUniswapV3Pool.sol";
import "v3-periphery/libraries/LiquidityAmounts.sol";

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/// @title Univ3SingleSidedLiquidity
/// @author libevm.eth
/// @notice Given X amount of tokenA, how can we optimally add liquidity to a Univ3Pool
///         that consists of tokenA/tokenB, where the range we want to add is within range of
///         the current sqrtRatioX96
/// @dev Should be called off-chain, very gas intensive
contract Univ3SingleSidedLiquidity {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using TickMath for int24;

    // Uniswap QuoterV2
    // We need the v2 quoter as it provides us with more information post swap
    // e.g. post-swap sqrtRatioX96
    IQuoterV2 internal quoter =
        IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);

    // Min / Max Sqrt ratios
    uint160 internal constant MIN_SQRT_RATIO = 4295128740;
    uint160 internal constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970341;

    // Binary search params
    uint256 internal BINARY_SERACH_MAX_ITERATIONS = 128;
    uint256 internal MAX_ERROR_THRESHOLD = 1e6;

    // Stack too deep errors reeee
    struct Cache {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        int24 tickSpacing;
        uint128 liquidity;
        uint160 sqrtRatioX96; // current market price
        uint160 lowerSqrtRatioX96; // lower range
        uint160 upperSqrtRatioX96; // upper range
        uint256 leftoverAmount0;
        uint256 leftoverAmount1;
        uint256 amountOutRecv;
    }

    /// @notice Given a uniswap v3 pool, the liquidity range to provide, and amountIn
    ///         while specifying if its token0 or token1. Find the optimal number of
    ///         tokens to swap from token0/token -> token1/token0 to LP the univ3 pool
    ///         liquidity range with minimal leftovers.
    /// @param pool - UniswapV3 pool address
    /// @param lowerTick - Liquidity lower range
    /// @param upperTick - Liquidity upper range
    /// @param amountIn - Amount of tokens to swap
    /// @param isAmountInToken0 - Are we supplying token0 or token1
    function getParamsForSingleSidedAmount(
        address pool,
        int24 lowerTick,
        int24 upperTick,
        uint256 amountIn,
        bool isAmountInToken0
    ) public returns (uint256 liquidity, uint256 amountToSwap) {
        // Stack too deep errors reee
        Cache memory cache;

        // Getting pool info
        cache.fee = IUniswapV3Pool(pool).fee();
        cache.tickSpacing = IUniswapV3Pool(pool).tickSpacing();

        // Make sure valid ticks
        lowerTick = lowerTick - (lowerTick % cache.tickSpacing);
        upperTick =
            upperTick -
            (upperTick % cache.tickSpacing) +
            (upperTick % cache.tickSpacing);
        cache.lowerSqrtRatioX96 = lowerTick.getSqrtRatioAtTick();
        cache.upperSqrtRatioX96 = upperTick.getSqrtRatioAtTick();

        // Convinience
        if (isAmountInToken0) {
            cache.tokenIn = IUniswapV3Pool(pool).token0();
            cache.tokenOut = IUniswapV3Pool(pool).token1();
        } else {
            cache.tokenIn = IUniswapV3Pool(pool).token1();
            cache.tokenOut = IUniswapV3Pool(pool).token0();
        }

        // Sqrt price limit
        uint160 swapSqrtPriceLimit = isAmountInToken0
            ? MIN_SQRT_RATIO
            : MAX_SQRT_RATIO;

        // Binary search params
        // Start with swapping half - very naive but binary search lets go
        amountToSwap = amountIn.div(2);
        uint256 i; // Cur binary search iteration
        (uint256 low, uint256 high) = (0, amountIn);

        // Use binary search to get the optimal swap amount, i.e. one with the least leftover
        while (i < BINARY_SERACH_MAX_ITERATIONS) {
            // Swapping tokenIn -> tokenOut
            // Have endSqrtRatio here so we know the price point to
            // calculate the ratio to LP within a certain range
            (cache.amountOutRecv, cache.sqrtRatioX96, , ) = quoter
                .quoteExactInputSingle(
                    IQuoterV2.QuoteExactInputSingleParams({
                        tokenIn: cache.tokenIn,
                        tokenOut: cache.tokenOut,
                        amountIn: amountToSwap,
                        fee: cache.fee,
                        sqrtPriceLimitX96: swapSqrtPriceLimit
                    })
                );

            // Stack too deep reee
            {
                // How many tokens will we have post swap?
                uint256 amountInPostSwap = amountIn.sub(amountToSwap);

                // Calculate liquidity received
                // with: backingTokens we will have post swap
                //       amount of protocol tokens recv
                cache.liquidity = LiquidityAmounts.getLiquidityForAmounts(
                    cache.sqrtRatioX96,
                    cache.lowerSqrtRatioX96,
                    cache.upperSqrtRatioX96,
                    isAmountInToken0 ? amountInPostSwap : cache.amountOutRecv,
                    !isAmountInToken0 ? amountInPostSwap : cache.amountOutRecv
                );

                // Get the amounts needed for post swap end sqrt ratio end state
                (uint256 lpAmount0, uint256 lpAmount1) = LiquidityAmounts
                    .getAmountsForLiquidity(
                        cache.sqrtRatioX96,
                        cache.lowerSqrtRatioX96,
                        cache.upperSqrtRatioX96,
                        cache.liquidity
                    );

                // Calculate leftover amounts
                if (isAmountInToken0) {
                    cache.leftoverAmount0 = amountInPostSwap.sub(lpAmount0);
                    cache.leftoverAmount1 = cache.amountOutRecv.sub(lpAmount1);
                } else {
                    cache.leftoverAmount0 = cache.amountOutRecv.sub(lpAmount0);
                    cache.leftoverAmount1 = amountInPostSwap.sub(lpAmount1);
                }

                // Trim some dust
                cache.leftoverAmount0 = cache.leftoverAmount0.div(100).mul(100);
                cache.leftoverAmount1 = cache.leftoverAmount1.div(100).mul(100);
            }

            if (isAmountInToken0) {
                // If amountIn = token0 AND we have too much leftover token0
                // we are not swapping enough
                if (cache.leftoverAmount0 > 0) {
                    (low, amountToSwap, high) = (
                        amountToSwap,
                        high.add(amountToSwap).div(2),
                        high
                    );
                }
                // If amountIn = token0 AND we have too much leftover token1
                // we swapped to much
                else if (cache.leftoverAmount1 > 0) {
                    (low, amountToSwap, high) = (
                        low,
                        low.add(amountToSwap).div(2),
                        amountToSwap
                    );
                }
                // Very optimal
                else {
                    break;
                }
            } else if (!isAmountInToken0) {
                // If amountIn = token1 AND we have too much leftover token1
                // we are not swapping enough
                if (cache.leftoverAmount1 > 0) {
                    (low, amountToSwap, high) = (
                        amountToSwap,
                        high.add(amountToSwap).div(2),
                        high
                    );
                }
                // If amountIn = token1 AND we have too much leftover token0
                // we swapped to much
                else if (cache.leftoverAmount0 > 0) {
                    (low, amountToSwap, high) = (
                        low,
                        low.add(amountToSwap).div(2),
                        amountToSwap
                    );
                }
                // Very optimal
                else {
                    break;
                }
            }

            ++i; // gas optimizoooor
        }

        return (cache.liquidity, amountToSwap);
    }
}
