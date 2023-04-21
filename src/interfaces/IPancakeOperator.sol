// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >0.7.0;
pragma abicoder v2;

interface IPancakeOperator {
    struct AddLiquidityParams {
        uint256 positionId;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    struct SwapExactInputSingleParams {
        uint256 positionId;
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function addLiquidity(AddLiquidityParams calldata params)
        external
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function swapExactInputSingle(SwapExactInputSingleParams calldata params) external returns (uint256 amountOut);
}
