// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.19;

import {IWithdrawFungibleCallback} from "amplifi-v1-common/interfaces/callbacks/IWithdrawFungibleCallback.sol";
import {IWithdrawFungiblesCallback} from "amplifi-v1-common/interfaces/callbacks/IWithdrawFungiblesCallback.sol";
import {IBookkeeper} from "amplifi-v1-common/interfaces/IBookkeeper.sol";
import {IRegistrar} from "amplifi-v1-common/interfaces/IRegistrar.sol";

import {IPancakeOperator} from "./interfaces/IPancakeOperator.sol";
import {INonfungiblePositionManager} from "./interfaces/uniswap/INonfungiblePositionManager.sol";
import {ISwapRouter} from "./interfaces/pancake/ISwapRouter.sol";

import {CrossContractFunc} from "./CrossContractFunc.sol";
import {TransferHelper} from "./utils/TransferHelper.sol";

contract PancakeOperator is
    CrossContractFunc,
    IPancakeOperator,
    IWithdrawFungibleCallback,
    IWithdrawFungiblesCallback
{
    INonfungiblePositionManager internal immutable NPM;
    ISwapRouter internal immutable SR;
    IBookkeeper internal immutable BK;

    constructor(address bookkeeper, address npm, address swapRouter) {
        NPM = INonfungiblePositionManager(npm);
        SR = ISwapRouter(swapRouter);
        BK = IBookkeeper(bookkeeper);
    }

    modifier requireAuthorizedMsgSender(uint256 positionId) {
        // only position owner and approved operator contract call will be allowed
        address owner = BK.ownerOf(positionId);
        address sender = msg.sender;

        require(sender == owner || BK.isApprovedForAll(owner, sender), "unauthorized message sender.");
        _;
    }

    modifier requireBookkeeper() {
        require(msg.sender == address(BK), "only called by bookkeeper.");
        _;
    }

    function mint(MintParams calldata params)
        external
        override
        requireAuthorizedMsgSender(params.positionId)
        runFunc(Function.Mint)
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

        callbackResult = BK.withdrawFungibles(params.positionId, tokens, amounts, address(this), callbackParams);

        (tokenId, liquidity, amount0, amount1) = abi.decode(callbackResult, (uint256, uint128, uint256, uint256));
    }

    function execMint(MintParams memory params) internal virtual returns (bytes memory) {
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
            recipient: address(BK),
            deadline: params.deadline
        });

        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = NPM.mint(params1);

        BK.depositNonFungible(params.positionId, address(NPM), tokenId);

        if (amount0 < params.amount0Desired) {
            uint256 unspend = params.amount0Desired - amount0;
            TransferHelper.safeTransfer(params.token0, address(BK), unspend);
            BK.depositFungible(params.positionId, params.token0);
        }

        if (amount1 < params.amount1Desired) {
            uint256 unspend = params.amount1Desired - amount1;
            TransferHelper.safeTransfer(params.token1, address(BK), unspend);
            BK.depositFungible(params.positionId, params.token1);
        }

        return abi.encode(tokenId, liquidity, amount0, amount1);
    }

    function collect(CollectParams calldata params)
        external
        override
        requireAuthorizedMsgSender(params.positionId)
        returns (uint256 amount0, uint256 amount1)
    {
        (,, address token0, address token1,,,,,,,,) = NPM.positions(params.positionId);
        INonfungiblePositionManager.CollectParams memory params1 = INonfungiblePositionManager.CollectParams({
            tokenId: params.tokenId,
            recipient: address(BK),
            amount0Max: params.amount0Max,
            amount1Max: params.amount1Max
        });

        (amount0, amount1) = NPM.collect(params1);

        if (amount0 > 0) BK.depositFungible(params.positionId, token0);
        if (amount1 > 0) BK.depositFungible(params.positionId, token1);
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        override
        requireAuthorizedMsgSender(params.positionId)
        runFunc(Function.ExactInputSingle)
        returns (uint256 amountOut)
    {
        bytes memory result =
            BK.withdrawFungible(params.positionId, params.tokenIn, params.amountIn, address(this), abi.encode(params));

        (amountOut) = abi.decode(result, (uint256));
    }

    function execExactInputSingle(ExactInputSingleParams memory params) internal virtual returns (bytes memory) {
        TransferHelper.safeApprove(params.tokenIn, address(SR), params.amountIn);

        ISwapRouter.ExactInputSingleParams memory params1 = ISwapRouter.ExactInputSingleParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            fee: params.fee,
            recipient: address(BK),
            amountIn: params.amountIn,
            amountOutMinimum: params.amountOutMinimum,
            sqrtPriceLimitX96: params.sqrtPriceLimitX96
        });

        uint256 amountOut = SR.exactInputSingle(params1);
        BK.depositFungible(params.positionId, params.tokenOut);

        return abi.encode(amountOut);
    }

    function withdrawFungibleCallback(
        uint256, /* positionId */
        address, /* token */
        uint256, /* amount */
        address, /* recipient */
        bytes calldata data
    ) external virtual requireBookkeeper returns (bytes memory result) {
        Function func = runningFunc();

        if (func == Function.ExactInputSingle) {
            ExactInputSingleParams memory params;
            (params) = abi.decode(data, (ExactInputSingleParams));
            return execExactInputSingle(params);
        } else {
            revert("unreachable code.");
        }
    }

    function withdrawFungiblesCallback(
        uint256, /* positionId */
        address[] calldata, /* tokens */
        uint256[] calldata, /* amounts */
        address, /* recipient */
        bytes calldata data
    ) external virtual requireBookkeeper returns (bytes memory result) {
        Function func = runningFunc();

        if (func == Function.Mint) {
            MintParams memory params;
            (params) = abi.decode(data, (MintParams));
            return execMint(params);
        } else {
            revert("unreachable code.");
        }
    }
}
