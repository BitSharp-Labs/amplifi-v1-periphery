// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.19;

import {IPancakeOperator} from "./interfaces/IPancakeOperator.sol";
import {ISwapRouter} from "./interfaces/pancake/ISwapRouter.sol";

import {NPMOperator} from "./NPMOperator.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";

contract PancakeOperator is NPMOperator, IPancakeOperator {
    ISwapRouter private _swapRouter;

    constructor(address bookkeeper, address npm, address swapRouter) NPMOperator(npm, bookkeeper) {
	_swapRouter = ISwapRouter(swapRouter);
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
	external
	override
	requireAuthorizedMsgSender(params.positionId)
	runFunc(Function.ExactInputSingle)
	returns (uint256 amountOut)
    {
	bytes memory result = _bookkeeper.withdrawFungible(
	    params.positionId, params.tokenIn, params.amountIn, address(this), abi.encode(params)
	);

	(amountOut) = abi.decode(result, (uint256));
    }

    function execExactInputSingle(ExactInputSingleParams memory params) internal virtual returns (bytes memory) {
	TransferHelper.safeApprove(params.tokenIn, address(_swapRouter), params.amountIn);

	ISwapRouter.ExactInputSingleParams memory params1 = ISwapRouter.ExactInputSingleParams({
	    tokenIn: params.tokenIn,
	    tokenOut: params.tokenOut,
	    fee: params.fee,
	    recipient: address(_bookkeeper),
	    amountIn: params.amountIn,
	    amountOutMinimum: params.amountOutMinimum,
	    sqrtPriceLimitX96: params.sqrtPriceLimitX96
	});

	uint256 amountOut = _swapRouter.exactInputSingle(params1);
	_bookkeeper.depositFungible(params.positionId, params.tokenOut);

	return abi.encode(amountOut);
    }

    function withdrawFungibleCallback(
	uint256, /* positionId */
	address, /* token */
	uint256, /* amount */
	address, /* recipient */
	bytes calldata data
    ) external override requireBookkeeper returns (bytes memory result) {
	Function func = runningFunc();

	if (func == Function.ExactInputSingle) {
	    ExactInputSingleParams memory params;
	    (params) = abi.decode(data, (ExactInputSingleParams));
	    return execExactInputSingle(params);
	} else {
	    revert("unreachable code.");
	}
    }
}
