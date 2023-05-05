// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.19;

import {IWithdrawFungibleCallback} from "amplifi-v1-common/interfaces/callbacks/IWithdrawFungibleCallback.sol";
import {IWithdrawFungiblesCallback} from "amplifi-v1-common/interfaces/callbacks/IWithdrawFungiblesCallback.sol";
import {IBookkeeper} from "amplifi-v1-common/interfaces/IBookkeeper.sol";

import {INPMOperator} from "./interfaces/INPMOperator.sol";
import {INonfungibleInspector} from "./interfaces/INonfungibleInspector.sol";
import {IUniswapV3Factory as IFactory} from "./interfaces/uniswap/IUniswapV3Factory.sol";
import {IUniswapV3Pool as IPool} from "./interfaces/uniswap/IUniswapV3Pool.sol";
import {INonfungiblePositionManager as INPM} from "./interfaces/uniswap/INonfungiblePositionManager.sol";

import {TickMath} from "./libraries/TickMath.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";

import {CrossContractFunc} from "./CrossContractFunc.sol";

contract NPMOperator is
    CrossContractFunc,
    INonfungibleInspector,
    INPMOperator,
    IWithdrawFungibleCallback,
    IWithdrawFungiblesCallback
{
    INPM internal _npm;
    IFactory internal _factory;
    IBookkeeper internal _bookkeeper;

    struct Position {
	uint96 nonce;
	address operator;
	address token0;
	address token1;
	uint24 fee;
	int24 tickLower;
	int24 tickUpper;
	uint128 liquidity;
	uint256 feeGrowthInside0LastX128;
	uint256 feeGrowthInside1LastX128;
	uint128 tokensOwed0;
	uint128 tokensOwed1;
    }

    constructor(address npm, address bookkeeper) {
	_npm = INPM(npm);
	_factory = IFactory(_npm.factory());
	_bookkeeper = IBookkeeper(bookkeeper);
    }

    modifier requireAuthorizedMsgSender(uint256 positionId) {
	// only position owner and approved operator contract call will be allowed
	address owner = _bookkeeper.ownerOf(positionId);
	address sender = msg.sender;

	require(sender == owner || _bookkeeper.isApprovedForAll(owner, sender), "unauthorized message sender.");
	_;
    }

    modifier requireBookkeeper() {
	require(msg.sender == address(_bookkeeper), "only called by bookkeeper.");
	_;
    }

    function inspectPosition(uint256 tokenId)
	external
	view
	override
	returns (address[] memory tokens, uint256[] memory amounts)
    {
	Position memory pos;
	(
	    ,
	    ,
	    pos.token0,
	    pos.token1,
	    pos.fee,
	    pos.tickLower,
	    pos.tickUpper,
	    pos.liquidity,
	    ,
	    ,
	    pos.tokensOwed0,
	    pos.tokensOwed1
	) = _npm.positions(tokenId);

	tokens = new address[](2);
	amounts = new uint[](2);

	tokens[0] = pos.token0;
	tokens[1] = pos.token1;

	(uint256 amount0, uint256 amount1) = amountsWithLiquidity(pos);
	amounts[0] += amount0;
	amounts[1] += amount1;

	(amount0, amount1) = amountsWithLiquidityFee(pos);
	amounts[0] += amount0;
	amounts[1] += amount1;
    }

    function amountsWithLiquidity(Position memory pos)
	internal
	view
	virtual
	returns (uint256 amount0, uint256 amount1)
    {
	if (pos.liquidity == 0) {
	    return (amount0, amount1);
	}

	address pool = _factory.getPool(pos.token0, pos.token1, pos.fee);
	require(pool != address(0), "pool not found.");

	(uint160 sqrtPriceBx96Curr,,,,,,) = IPool(pool).slot0();
	uint160 sqrtPriceBx96Lower = TickMath.getSqrtRatioAtTick(pos.tickLower);
	uint160 sqrtPriceBx96Upper = TickMath.getSqrtRatioAtTick(pos.tickUpper);

	if (sqrtPriceBx96Curr >= sqrtPriceBx96Upper) {
	    // all asset converted to token1
	    amount1 += TickMath.getAmount1Delta(sqrtPriceBx96Upper, sqrtPriceBx96Lower, pos.liquidity);
	} else if (sqrtPriceBx96Curr <= sqrtPriceBx96Lower) {
	    // all asset converted to token0
	    amount0 += TickMath.getAmount0Delta(sqrtPriceBx96Lower, sqrtPriceBx96Upper, pos.liquidity);
	} else {
	    amount1 += TickMath.getAmount1Delta(sqrtPriceBx96Curr, sqrtPriceBx96Lower, pos.liquidity);
	    amount0 += TickMath.getAmount0Delta(sqrtPriceBx96Curr, sqrtPriceBx96Upper, pos.liquidity);
	}
    }

    function amountsWithLiquidityFee(Position memory pos)
	internal
	view
	virtual
	returns (uint256 amount0, uint256 amount1)
    {
	// This method should add the uncollected fee in pool
	amount0 = pos.tokensOwed0;
	amount1 = pos.tokensOwed1;
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

	callbackResult =
	    _bookkeeper.withdrawFungibles(params.positionId, tokens, amounts, address(this), callbackParams);

	(tokenId, liquidity, amount0, amount1) = abi.decode(callbackResult, (uint256, uint128, uint256, uint256));
    }

    function execMint(MintParams memory params) internal returns (bytes memory) {
	TransferHelper.safeApprove(params.token0, address(_npm), params.amount0Desired);
	TransferHelper.safeApprove(params.token1, address(_npm), params.amount1Desired);

	INPM.MintParams memory params1 = INPM.MintParams({
	    token0: params.token0,
	    token1: params.token1,
	    fee: params.fee,
	    tickLower: params.tickLower,
	    tickUpper: params.tickUpper,
	    amount0Desired: params.amount0Desired,
	    amount1Desired: params.amount1Desired,
	    amount0Min: params.amount0Min,
	    amount1Min: params.amount1Min,
	    recipient: address(_bookkeeper),
	    deadline: params.deadline
	});

	(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = _npm.mint(params1);

	_bookkeeper.depositNonFungible(params.positionId, address(_npm), tokenId);

	if (amount0 < params.amount0Desired) {
	    uint256 unspend = params.amount0Desired - amount0;
	    TransferHelper.safeTransfer(params.token0, address(_bookkeeper), unspend);
	    _bookkeeper.depositFungible(params.positionId, params.token0);
	}

	if (amount1 < params.amount1Desired) {
	    uint256 unspend = params.amount1Desired - amount1;
	    TransferHelper.safeTransfer(params.token1, address(_bookkeeper), unspend);
	    _bookkeeper.depositFungible(params.positionId, params.token1);
	}

	return abi.encode(tokenId, liquidity, amount0, amount1);
    }

    function collect(CollectParams memory params) external override returns (uint256 amount0, uint256 amount1) {
	(,, address token0, address token1,,,,,,,,) = _npm.positions(params.tokenId);

	INPM.CollectParams memory params1 = INPM.CollectParams({
	    tokenId: params.tokenId,
	    recipient: address(_bookkeeper),
	    amount0Max: params.amount0Max,
	    amount1Max: params.amount1Max
	});

	(amount0, amount1) = _npm.collect(params1);

	if (amount0 > 0) _bookkeeper.depositFungible(params.positionId, token0);
	if (amount1 > 0) _bookkeeper.depositFungible(params.positionId, token1);
    }

    function withdrawFungibleCallback(
	uint256, /* positionId */
	address, /* token */
	uint256, /* amount */
	address, /* recipient */
	bytes calldata data
    ) external virtual override returns (bytes memory result) {}

    function withdrawFungiblesCallback(
	uint256, /* positionId */
	address[] calldata, /* tokens */
	uint256[] calldata, /* amounts */
	address, /* recipient */
	bytes calldata data
    ) external virtual override requireBookkeeper returns (bytes memory result) {
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
