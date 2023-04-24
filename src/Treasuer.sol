// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.19;

import {IRegistrar} from "amplifi-v1-common/interfaces/IRegistrar.sol";
import {ITreasurer} from "amplifi-v1-common/interfaces/ITreasurer.sol";
import {TokenInfo, TokenType, TokenSubtype} from "amplifi-v1-common/models/TokenInfo.sol";

import {FixedPoint96} from "./utils/FixedPoint96.sol";
import {MathHelper} from "./utils/MathHelper.sol";
import {TickMath} from "./utils/TickMath.sol";
import {IPancakePool} from "./interfaces/pancake/IPancakePool.sol";
import {INonfungiblePositionManager} from "./interfaces/pancake/INonfungiblePositionManager.sol";
import {IPancakeFactory} from "./interfaces/pancake/IPancakeFactory.sol";

contract Treasurer is ITreasurer {
    IRegistrar public immutable REGISTRAR;

    INonfungiblePositionManager public immutable NPM;
    IPancakeFactory public immutable FACTORY;

    address public PUD;

    constructor(address registrar, address npm) {
	REGISTRAR = IRegistrar(registrar);
	REGISTRAR.setTreasurer(address(this));

	NPM = INonfungiblePositionManager(npm);
	FACTORY = IPancakeFactory(NPM.factory());
    }

    function initialize() external {
	PUD = REGISTRAR.getPUD();
    }

    function priceBx96FromSwapPool(address poolAddr, address token0) internal view returns (uint256) {
	if (poolAddr == address(0)) return FixedPoint96.Q96;

	IPancakePool pool = IPancakePool(poolAddr);

	(uint160 sqrtPriceX96,,,,,,) = pool.slot0();

	uint256 priceBx96 = MathHelper.mulDivRoundingUp(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);

	if (token0 != pool.token0()) {
	    priceBx96 = MathHelper.mulDivRoundingUp(FixedPoint96.Q96, FixedPoint96.Q96, priceBx96);
	}

	return priceBx96;
    }

    function getValueOfFungibleToken(address token, uint256 amount) external view returns (uint256 value) {
	// value caculate with two step: token -> middle token -> pud

	TokenInfo memory tokenInf = REGISTRAR.getTokenInfoOf(token);
	TokenInfo memory pudInf = REGISTRAR.getTokenInfoOf(PUD);

	uint256 price1 = priceBx96FromSwapPool(tokenInf.priceOracle, token);
	uint256 price2 = priceBx96FromSwapPool(pudInf.priceOracle, PUD);

	return MathHelper.mulDivRoundingUp(price1, amount, price2);
    }

    function getValuesOfFungibleTokens(address[] calldata tokens, uint256[] calldata amounts)
	external
	view
	override
	returns (uint256[] memory values)
    {
	values = new uint256[](tokens.length);

	TokenInfo memory pudInfo = REGISTRAR.getTokenInfoOf(PUD);
	uint256 price2 = priceBx96FromSwapPool(pudInfo.priceOracle, PUD);

	for (uint256 i = 0; i < tokens.length; i++) {
	    if (tokens[i] == PUD) {
		values[i] = amounts[i];
		continue;
	    }

	    if (amounts[i] == 0) {
		continue;
	    }

	    TokenInfo memory tokenInf = REGISTRAR.getTokenInfoOf(tokens[i]);

	    uint256 price1 = priceBx96FromSwapPool(tokenInf.priceOracle, tokens[i]);
	    values[i] = MathHelper.mulDivRoundingUp(price1, amounts[i], price2);
	}
    }

    struct PancakePosition {
	address token0;
	address token1;
	uint24 fee;
	int24 tickLower;
	int24 tickUpper;
	uint128 liquidity;
	uint128 tokensOwed0;
	uint128 tokensOwed1;
    }

    function amountsOfPancakeNFT(PancakePosition memory pos)
	internal
	view
	virtual
	returns (uint256 amount0, uint256 amount1)
    {
	amount0 += uint256(pos.tokensOwed0);
	amount1 += uint256(pos.tokensOwed1);

	if (pos.liquidity == 0) {
	    return (amount0, amount1);
	}

	address pool = FACTORY.getPool(pos.token0, pos.token1, pos.fee);
	require(pool != address(0), "pool not found.");

	(uint160 sqrtPriceBx96Curr,,,,,,) = IPancakePool(pool).slot0();
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

    function valueOfPancakeNFT(uint256 tokenId)
	internal
	view
	returns (address token0, address token1, uint256 value0, uint256 value1)
    {
	PancakePosition memory pos;
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
	) = NPM.positions(tokenId);

	address[] memory tokens = new address[](2);
	uint256[] memory amounts = new uint[](2);

	tokens[0] = pos.token0;
	tokens[1] = pos.token1;

	(amounts[0], amounts[1]) = amountsOfPancakeNFT(pos);
	uint256[] memory values = this.getValuesOfFungibleTokens(tokens, amounts);

	(token0, token1) = (pos.token0, pos.token1);
	(value0, value1) = (values[0], values[1]);
    }

    function getValueOfNonFungibleToken(address token, uint256 tokenId) external view override returns (uint256) {
	TokenInfo memory inf = REGISTRAR.getTokenInfoOf(token);
	require(inf.type_ == TokenType.NonFungible, "require non-fungible token");

	// only support pancake like NFT now
	(,, uint256 value0, uint256 value1) = valueOfPancakeNFT(tokenId);

	return value0 + value1;
    }

    function getValuesOfNonFungibleTokens(address token, uint256[] calldata tokenIds)
	external
	view
	override
	returns (uint256[] memory values)
    {
	TokenInfo memory inf = REGISTRAR.getTokenInfoOf(token);
	require(inf.type_ == TokenType.NonFungible, "require non-fungible token");

	values = new uint256[](tokenIds.length);

	for (uint256 i = 0; i < tokenIds.length; i++) {
	    (,, uint256 value0, uint256 value1) = valueOfPancakeNFT(tokenIds[i]);
	    values[i] = value0 + value1;
	}
    }

    function getValuesOfNonFungibleTokens(address[] calldata tokens, uint256[] calldata tokenIds)
	external
	view
	returns (uint256[] memory values)
    {
	values = new uint256[](tokens.length);

	for (uint256 i = 0; i < tokenIds.length; i++) {
	    values[i] = this.getValueOfNonFungibleToken(tokens[i], tokenIds[i]);
	}
    }

    function rescue(uint256 positionId) external override {}
}
