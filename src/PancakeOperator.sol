// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.19;

import {IWithdrawFungibleTokenCallback} from "amplifi-v1-common/interfaces/callbacks/IWithdrawFungibleTokenCallback.sol";
import {IWithdrawFungibleTokensCallback} from
    "amplifi-v1-common/interfaces/callbacks/IWithdrawFungibleTokensCallback.sol";
import {IBookkeeper} from "amplifi-v1-common/interfaces/IBookkeeper.sol";
import {IRegistrar} from "amplifi-v1-common/interfaces/IRegistrar.sol";

import {IPancakeOperator} from "./interfaces/IPancakeOperator.sol";
import {INonfungiblePositionManager} from "./interfaces/pancake/INonfungiblePositionManager.sol";
import {ISwapRouter} from "./interfaces/pancake/ISwapRouter.sol";

contract PancakeOperator is IPancakeOperator, IWithdrawFungibleTokenCallback, IWithdrawFungibleTokensCallback {
    enum Function {
	None,
	AddLiquidity,
	SwapExactInputSingle
    }

    INonfungiblePositionManager public immutable NPM;
    ISwapRouter public immutable SWAPROUTER;

    IBookkeeper public immutable BOOKKEEPER;
    IRegistrar public immutable REGISTRAR;

    Function private runningFunc;

    constructor(address registrar, address bookkeeper, address npm, address swapRouter) {
	NPM = INonfungiblePositionManager(npm);
	SWAPROUTER = ISwapRouter(swapRouter);

	REGISTRAR = IRegistrar(registrar);
	BOOKKEEPER = IBookkeeper(bookkeeper);
    }

    modifier runFunc(Function func) {
	require(func != Function.None, "empty function.");
	require(runningFunc == Function.None, "other function is running");
	runningFunc = func;
	_;
	runningFunc = Function.None;
    }

    function addLiquidity(AddLiquidityParams calldata params)
	external
	override
	runFunc(Fuction.AddLiquidity)
	returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
	bytes memory callbackParams = abi.encode(params);
	bytes memory callbackResult;

	address[] memory tokens = new address[](2);
	uint256[] memory amounts = new uint[](2);

	tokens[0] = params.token0;
	tokens[1] = params.token1;

	amounts[0] = params.amount0Desired;
	amounts[1] = params.amount1Desired;

	callbackResult =
	    BOOKKEEPER.withdrawFungibleTokens(params.positionId, tokens, amounts, address(this), callbackParams);

	(tokenId, liquidity, amount0, amount1) = abi.decode(callbackResult, (uint256, uint128, uint256, uint256));
    }

    function execAddLiquidity(AddLiquidityParams memory params) private returns (bytes memory) {
	// TODO approve token for npm

	INonfungiblePositionManager.MintParams memory params1 = INonfungiblePositionManager.MintParams({
	    token0: params.token0,
	    token1: params.token1,
	    fee: params.fee,
	    tickLower: params.tickLower,
	    tickUpper: params.tickUpper,
	    amount0Desired: params.amount0Desired,
	    amount1Desired: params.amount1Desired,
	    amount0Min: params.amount0Min,
	    amount1Min: params.amount1Min,
	    recipient: address(BOOKKEEPER),
	    deadline: block.timestamp
	});

	(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = NPM.mint(params1);

	BOOKKEEPER.depositNonFungibleToken(params.positionId, address(NPM), tokenId);

	if (amount0 < params.amount0Desired) {
	    uint256 unspend = params.amount0Desired - amount0;
	    BOOKKEEPER.depositFungibleToken(params.positionId, params.token0, unspend);
	}

	if (amount1 < params.amount1Desired) {
	    uint256 unspend = params.amount1Desired - amount1;
	    BOOKKEEPER.depositFungibleToken(params.positionId, params.token1, unspend);
	}

	return abi.encode(tokenId, liquidity, amount0, amount1);
    }

    function swapExactInputSingle(SwapExactInputSingleParams calldata params)
	external
	override
	runFunc(Function.SwapExactInputSingle)
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
	uint256, /* positionId */
	address[] calldata, /* tokens */
	uint256[] calldata, /* amounts */
	address, /* recipient */
	bytes calldata data
    ) external returns (bytes memory result) {
	Function func = runningFunc;

	if (func == Function.AddLiquidity) {
	    AddLiquidityParams memory params;
	    (params) = abi.decode(data, (AddLiquidityParams));
	    return execAddLiquidity(params);
	}
    }
}
