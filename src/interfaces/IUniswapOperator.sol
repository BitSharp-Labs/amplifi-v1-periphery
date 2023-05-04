// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >0.7.0;
pragma abicoder v2;

import {INPMOperator} from "./INPMOperator.sol";

interface IUniswapOperator is INPMOperator {
    struct ExactInputSingleParams {
        uint256 positionId;
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external returns (uint256 amountOut);

    struct ExactOutputSingleParams {
        uint256 positionId;
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    /* function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn); */
}
