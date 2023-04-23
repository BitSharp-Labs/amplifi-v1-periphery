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
import {TransferHelper} from "./utils/TransferHelper.sol";

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

    modifier requireAuthorizedMsgSender(uint256 positionId) {
        // only position owner and approved operator contract call will be allowed
        address owner = BOOKKEEPER.ownerOf(positionId);
        address sender = msg.sender;

        require(sender == owner || BOOKKEEPER.isApprovedForAll(owner, sender), "unauthorized message sender.");
        _;
    }

    modifier requireBookkeeper() {
        require(msg.sender == address(BOOKKEEPER), "only called by bookkeeper.");
        _;
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
        requireAuthorizedMsgSender(params.positionId)
        runFunc(Function.AddLiquidity)
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

    function execAddLiquidity(AddLiquidityParams memory params) internal returns (bytes memory) {
        TransferHelper.safeApprove(params.token0, address(NPM), params.amount0Desired);
        TransferHelper.safeApprove(params.token1, address(NPM), params.amount1Desired);

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
            TransferHelper.safeTransfer(params.token0, address(BOOKKEEPER), unspend);
            BOOKKEEPER.depositFungibleToken(params.positionId, params.token0);
        }

        if (amount1 < params.amount1Desired) {
            uint256 unspend = params.amount1Desired - amount1;
            TransferHelper.safeTransfer(params.token1, address(BOOKKEEPER), unspend);
            BOOKKEEPER.depositFungibleToken(params.positionId, params.token1);
        }

        return abi.encode(tokenId, liquidity, amount0, amount1);
    }

    function swapExactInputSingle(SwapExactInputSingleParams calldata params)
        external
        override
        requireAuthorizedMsgSender(params.positionId)
        runFunc(Function.SwapExactInputSingle)
        returns (uint256 amountOut)
    {
        bytes memory result = BOOKKEEPER.withdrawFungibleToken(
            params.positionId, params.tokenIn, params.amountIn, address(this), abi.encode(params)
        );

        (amountOut) = abi.decode(result, (uint256));
    }

    function execSwapExactInputSingle(SwapExactInputSingleParams memory params) internal returns (bytes memory) {
        TransferHelper.safeApprove(params.tokenIn, address(SWAPROUTER), params.amountIn);

        ISwapRouter.ExactInputSingleParams memory params1 = ISwapRouter.ExactInputSingleParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            fee: params.fee,
            recipient: address(BOOKKEEPER),
            deadline: block.timestamp,
            amountIn: params.amountIn,
            amountOutMinimum: params.amountOutMinimum,
            sqrtPriceLimitX96: params.sqrtPriceLimitX96
        });

        uint256 amountOut = SWAPROUTER.exactInputSingle(params1);
        BOOKKEEPER.depositFungibleToken(params.positionId, params.tokenOut);

        return abi.encode(amountOut);
    }

    function withdrawFungibleTokenCallback(
        uint256, /* positionId */
        address, /* token */
        uint256, /* amount */
        address, /* recipient */
        bytes calldata data
    ) external requireBookkeeper returns (bytes memory result) {
        Function func = runningFunc;

        if (func == Function.SwapExactInputSingle) {
            SwapExactInputSingleParams memory params;
            (params) = abi.decode(data, (SwapExactInputSingleParams));
            return execSwapExactInputSingle(params);
        } else {
            revert("unreachable code.");
        }
    }

    function withdrawFungibleTokensCallback(
        uint256, /* positionId */
        address[] calldata, /* tokens */
        uint256[] calldata, /* amounts */
        address, /* recipient */
        bytes calldata data
    ) external requireBookkeeper returns (bytes memory result) {
        Function func = runningFunc;

        if (func == Function.AddLiquidity) {
            AddLiquidityParams memory params;
            (params) = abi.decode(data, (AddLiquidityParams));
            return execAddLiquidity(params);
        } else {
            revert("unreachable code.");
        }
    }
}
