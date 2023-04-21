// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.19;

import {IWithdrawFungibleTokenCallback} from "amplifi-v1-common/interfaces/callbacks/IWithdrawFungibleTokenCallback.sol";
import {IWithdrawFungibleTokensCallback} from
    "amplifi-v1-common/interfaces/callbacks/IWithdrawFungibleTokensCallback.sol";

import {IPancakeOperator} from "./interfaces/IPancakeOperator.sol";

contract PancakeOperator is IPancakeOperator, IWithdrawFungibleTokenCallback, IWithdrawFungibleTokensCallback {
    function addLiquidity(AddLiquidityParams calldata params)
        external
        override
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {}

    function swapExactInputSingle(SwapExactInputSingleParams calldata params)
        external
        override
        returns (uint256 amountOut)
    {}

    function withdrawFungibleTokenCallback(
        uint256 positionId,
        address token,
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external returns (bytes memory result) {}

    function withdrawFungibleTokensCallback(
        uint256 positionId,
        address[] calldata tokens,
        uint256[] calldata amounts,
        address recipient,
        bytes calldata data
    ) external returns (bytes memory result) {}
}
