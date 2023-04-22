// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.19;

import {PancakeOperator} from "./PancakeOperator.sol";

contract UniswapV3Operator is PancakeOperator {
    // Pancake use the same contracts as Uniswap v3, so the implemention of operator is the same too.

    constructor(address registrar, address bookkeeper, address npm, address swapRouter)
        PancakeOperator(registrar, bookkeeper, npm, swapRouter)
    {}
}
