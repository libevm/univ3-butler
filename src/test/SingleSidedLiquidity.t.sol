// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "./lib/test2.sol";

import "./lib/MockToken.sol";
import "./lib/Constants.sol";

import "../Univ3ButlerLib.sol";
import "../SingleSidedLiquidity.sol";

import "@uniswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap-v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap-v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap-v3-periphery/contracts/interfaces/external/IWETH9.sol";

contract SingleSidedLiquidityTest is DSTest2 {
    using SafeMath for uint256;
    using TickMath for uint160;
    using TickMath for int24;

    Univ3SingleSidedLiquidity singleSidedLP;

    INonfungiblePositionManager nfpm =
        INonfungiblePositionManager(Constants.UNIV3_POS_MANAGER);
    ISwapRouter v3router = ISwapRouter(Constants.UNIV3_ROUTER);
    IUniswapV3Factory v3Factory = IUniswapV3Factory(Constants.UNIV3_FACTORY);
    IUniswapV3Pool pool;

    MockToken token0;
    MockToken token1;

    uint24 constant fee = 3000;
    int24 tickSpacing;

    function setUp() public {
        token0 = new MockToken();
        token1 = new MockToken();

        if (address(token0) > address(token1)) {
            address temp = address(token0);
            token0 = token1;
            token1 = MockToken(temp);
        }

        pool = IUniswapV3Pool(
            v3Factory.createPool(address(token0), address(token1), fee)
        );

        uint160 sqrtPriceX96 = Univ3ButlerLib.encodePriceSqrt(1, 1000);
        pool.initialize(sqrtPriceX96);
        tickSpacing = pool.tickSpacing();

        // Add liquidity to pool
        // Get tick spacing
        (, int24 curTick, , , , , ) = pool.slot0();
        curTick = curTick - (curTick % tickSpacing);

        int24 lowerTick = curTick - (tickSpacing * 2);
        int24 upperTick = curTick + (tickSpacing * 2);

        token0.mint(address(this), 1000e18);
        token0.approve(address(nfpm), uint256(-1));
        token0.approve(address(v3router), uint256(-1));
        token0.approve(address(pool), uint256(-1));

        token1.mint(address(this), 1e18);
        token1.approve(address(nfpm), uint256(-1));
        token1.approve(address(v3router), uint256(-1));
        token1.approve(address(pool), uint256(-1));

        nfpm.mint(
            INonfungiblePositionManager.MintParams({
                token0: pool.token0(),
                token1: pool.token1(),
                fee: fee,
                tickLower: lowerTick,
                tickUpper: upperTick,
                amount0Desired: 1000e18,
                amount1Desired: 1e18,
                amount0Min: 0e18,
                amount1Min: 0e18,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        singleSidedLP = new Univ3SingleSidedLiquidity();

        token0.burn(token0.balanceOf(address(this)));
        token1.burn(token1.balanceOf(address(this)));
    }

    function test_getParamsForSingleSidedAmount_0() public {
        int24 lowerTick = Univ3ButlerLib
            .encodePriceSqrt(address(token0), address(token1), 1, 950)
            .getTickAtSqrtRatio();
        lowerTick = lowerTick - (lowerTick % tickSpacing);
        int24 upperTick = Univ3ButlerLib
            .encodePriceSqrt(address(token0), address(token1), 1, 1050)
            .getTickAtSqrtRatio();
        upperTick = upperTick - (upperTick % tickSpacing) + tickSpacing;

        uint256 amountIn = 10e18;

        // Get optimal liquidity
        (uint256 liquidityProjected, uint256 token0ToSwap) = singleSidedLP
            .getParamsForSingleSidedAmount(
                address(pool),
                lowerTick,
                upperTick,
                amountIn,
                true
            );

        token0.mint(address(this), 10e18);
        uint256 token1Out = v3router.exactInput(
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(address(token0), fee, address(token1)),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: token0ToSwap,
                amountOutMinimum: 0
            })
        );

        // Lets gooo
        (, uint128 liquidityActual, , ) = nfpm.mint(
            INonfungiblePositionManager.MintParams({
                token0: pool.token0(),
                token1: pool.token1(),
                fee: fee,
                tickLower: lowerTick,
                tickUpper: upperTick,
                amount0Desired: amountIn.sub(token0ToSwap),
                amount1Desired: token1Out,
                amount0Min: 0e18,
                amount1Min: 0e18,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        // Calculate projected liquidity
        assertGt(liquidityProjected, 1e10);
        assertApproxEq(
            uint256(liquidityProjected),
            uint256(liquidityActual),
            1e6
        );
    }

     function test_getParamsForSingleSidedAmount_1() public {
        int24 lowerTick = Univ3ButlerLib
            .encodePriceSqrt(address(token0), address(token1), 1, 950)
            .getTickAtSqrtRatio();
        lowerTick = lowerTick - (lowerTick % tickSpacing);
        int24 upperTick = Univ3ButlerLib
            .encodePriceSqrt(address(token0), address(token1), 1, 1050)
            .getTickAtSqrtRatio();
        upperTick = upperTick - (upperTick % tickSpacing) + tickSpacing;

        uint256 amountIn = 10e18;

        // Get optimal liquidity
        (uint256 liquidityProjected, uint256 token1ToSwap) = singleSidedLP
            .getParamsForSingleSidedAmount(
                address(pool),
                lowerTick,
                upperTick,
                amountIn,
                false
            );

        token1.mint(address(this), 10e18);
        uint256 token1Out = v3router.exactInput(
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(address(token1), fee, address(token0)),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: token1ToSwap,
                amountOutMinimum: 0
            })
        );

        // Lets gooo
        (, uint128 liquidityActual, , ) = nfpm.mint(
            INonfungiblePositionManager.MintParams({
                token0: pool.token0(),
                token1: pool.token1(),
                fee: fee,
                tickLower: lowerTick,
                tickUpper: upperTick,
                amount0Desired: token1Out,
                amount1Desired: amountIn.sub(token1ToSwap),
                amount0Min: 0e18,
                amount1Min: 0e18,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        // Calculate projected liquidity
        assertGt(liquidityProjected, 1e10);
        assertApproxEq(
            uint256(liquidityProjected),
            uint256(liquidityActual),
            1e6
        );
    }
}
