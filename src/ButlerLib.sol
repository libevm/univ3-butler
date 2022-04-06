// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "v3-periphery/interfaces/IQuoterV2.sol";
import "v3-core/libraries/TickMath.sol";
import "v3-core/libraries/FullMath.sol";
import "v3-core/interfaces/IUniswapV3Pool.sol";

library Univ3ButlerLib {
    uint256 constant PRECISION = 2**96;

    /// @notice Validates ticks to be multiples of tickSpacing
    function validateTicks(
        int24 tickSpacing,
        int24 lowerTick,
        int24 upperTick
    ) public pure returns (int24, int24) {
        lowerTick = lowerTick - (lowerTick % tickSpacing);

        if (upperTick % tickSpacing != 0) {
            upperTick = upperTick - (upperTick % tickSpacing) + tickSpacing;
        }

        return (lowerTick, upperTick);
    }

    /// @notice Converts sqrtPriceX96/sqrtRatioX96 of a given pool to spot price (assuming `amount` is 1 baseToken)
    function decodePriceSqrt(
        uint256 amount,
        IUniswapV3Pool pool,
        address baseToken,
        address quoteToken
    ) public view returns (uint256 quoteAmount) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, amount, 1 << 192)
                : FullMath.mulDiv(1 << 192, amount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(
                sqrtRatioX96,
                sqrtRatioX96,
                1 << 64
            );
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, amount, 1 << 128)
                : FullMath.mulDiv(1 << 128, amount, ratioX128);
        }
    }

    /// @notice Converts sqrtPrice into (amount * token0) = X token1
    ///         Enter amount as 10**token0.decimals() to get spot price
    ///         of X token0 = 1 token1
    function decodePriceSqrt(uint256 amount, uint160 sqrtPriceX96)
        public
        pure
        returns (uint256)
    {
        uint256 priceX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
        return FullMath.mulDiv(priceX192, amount, 1 << 128);
    }

    /// @notice Encodes 1 token0 = X token1
    function encodePriceSqrt(uint256 reserve1, uint256 reserve0)
        public
        pure
        returns (uint160)
    {
        return uint160(sqrt((reserve1 * PRECISION * PRECISION) / reserve0));
    }

    /// @notice Encodes R0 A0 = R1 A1, e.g. encodePriceSqrt(WETH, DAI, 1, 1000)
    ///         Would mean 1 WETH = 1000 DAI
    function encodePriceSqrt(
        address a1,
        address a0,
        uint256 r1,
        uint256 r0
    ) public pure returns (uint160) {
        if (a1 > a0) {
            return encodePriceSqrt(r1, r0);
        }

        return encodePriceSqrt(r0, r1);
    }

    // Fast sqrt, taken from Solmate.
    function sqrt(uint256 x) public pure returns (uint256 z) {
        assembly {
            // Start off with z at 1.
            z := 1

            // Used below to help find a nearby power of 2.
            let y := x

            // Find the lowest power of 2 that is at least sqrt(x).
            if iszero(lt(y, 0x100000000000000000000000000000000)) {
                y := shr(128, y) // Like dividing by 2 ** 128.
                z := shl(64, z) // Like multiplying by 2 ** 64.
            }
            if iszero(lt(y, 0x10000000000000000)) {
                y := shr(64, y) // Like dividing by 2 ** 64.
                z := shl(32, z) // Like multiplying by 2 ** 32.
            }
            if iszero(lt(y, 0x100000000)) {
                y := shr(32, y) // Like dividing by 2 ** 32.
                z := shl(16, z) // Like multiplying by 2 ** 16.
            }
            if iszero(lt(y, 0x10000)) {
                y := shr(16, y) // Like dividing by 2 ** 16.
                z := shl(8, z) // Like multiplying by 2 ** 8.
            }
            if iszero(lt(y, 0x100)) {
                y := shr(8, y) // Like dividing by 2 ** 8.
                z := shl(4, z) // Like multiplying by 2 ** 4.
            }
            if iszero(lt(y, 0x10)) {
                y := shr(4, y) // Like dividing by 2 ** 4.
                z := shl(2, z) // Like multiplying by 2 ** 2.
            }
            if iszero(lt(y, 0x8)) {
                // Equivalent to 2 ** z.
                z := shl(1, z)
            }

            // Shifting right by 1 is like dividing by 2.
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))

            // Compute a rounded down version of z.
            let zRoundDown := div(x, z)

            // If zRoundDown is smaller, use it.
            if lt(zRoundDown, z) {
                z := zRoundDown
            }
        }
    }
}
