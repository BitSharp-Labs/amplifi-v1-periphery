// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.19;

import {mulDiv18} from "prb-math/Common.sol";

import {IRegistrar} from "amplifi-v1-common/interfaces/IRegistrar.sol";
import {ITreasurer} from "amplifi-v1-common/interfaces/ITreasurer.sol";
import {TokenInfo, TokenType, TokenSubtype} from "amplifi-v1-common/models/TokenInfo.sol";

import {FixedPoint96} from "./libraries/FixedPoint96.sol";
import {MathHelper} from "./libraries/MathHelper.sol";
import {IUniswapV3Pool} from "./interfaces/uniswap/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "./interfaces/uniswap/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "./interfaces/uniswap/IUniswapV3Factory.sol";
import {INonfungibleInspector} from "./interfaces/INonfungibleInspector.sol";

contract Treasurer is ITreasurer {
    IRegistrar public immutable REGISTRAR;

    INonfungiblePositionManager public immutable NPM;
    IUniswapV3Factory public immutable FACTORY;

    address public PUD;

    constructor(address registrar, address npm) {
	REGISTRAR = IRegistrar(registrar);
	REGISTRAR.setTreasurer(address(this));

	NPM = INonfungiblePositionManager(npm);
	FACTORY = IUniswapV3Factory(NPM.factory());
    }

    function initialize() external {
	PUD = REGISTRAR.getPUD();
    }

    function priceBx96FromSwapPool(address poolAddr, address token0) internal view returns (uint256) {
	if (poolAddr == address(0)) return FixedPoint96.Q96;

	IUniswapV3Pool pool = IUniswapV3Pool(poolAddr);

	(uint160 sqrtPriceX96,,,,,,) = pool.slot0();

	uint256 priceBx96 = MathHelper.mulDivRoundingUp(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);

	if (token0 != pool.token0()) {
	    priceBx96 = MathHelper.mulDivRoundingUp(FixedPoint96.Q96, FixedPoint96.Q96, priceBx96);
	}

	return priceBx96;
    }

    function getAppraisalOfFungible(address token, uint256 amount)
	external
	view
	returns (uint256 value, uint256 margin)
    {
	// value caculate with two step: token -> middle token -> pud

	TokenInfo memory tokenInf = REGISTRAR.getTokenInfoOf(token);
	TokenInfo memory pudInf = REGISTRAR.getTokenInfoOf(PUD);

	uint256 price1 = priceBx96FromSwapPool(tokenInf.priceOracle, token);
	uint256 price2 = priceBx96FromSwapPool(pudInf.priceOracle, PUD);

	value = MathHelper.mulDivRoundingUp(price1, amount, price2);
	margin = mulDiv18(tokenInf.marginRatioUDx18, value);
    }

    struct TokenValue {
	address token;
	uint256 value;
	uint256 margin;
    }

    function appraiseFungibleTokens(address[] memory tokens, uint256[] memory amounts)
	internal
	view
	virtual
	returns (TokenValue[] memory values)
    {
	values = new TokenValue[](tokens.length);

	TokenInfo memory pudInfo = REGISTRAR.getTokenInfoOf(PUD);
	uint256 price2 = priceBx96FromSwapPool(pudInfo.priceOracle, PUD);

	for (uint256 i = 0; i < tokens.length; i++) {
	    values[i].token = tokens[i];
	    if (amounts[i] == 0) {
		continue;
	    }

	    if (tokens[i] == PUD) {
		values[i].value = amounts[i];
		values[i].margin = mulDiv18(pudInfo.marginRatioUDx18, amounts[i]);
		continue;
	    }

	    TokenInfo memory tokenInf = REGISTRAR.getTokenInfoOf(tokens[i]);

	    uint256 price1 = priceBx96FromSwapPool(tokenInf.priceOracle, tokens[i]);
	    uint256 value = MathHelper.mulDivRoundingUp(price1, amounts[i], price2);

	    values[i].value = value;
	    values[i].margin = mulDiv18(tokenInf.marginRatioUDx18, value);
	}
    }

    function getAppraisalOfFungibles(address[] calldata tokens, uint256[] calldata amounts)
	external
	view
	override
	returns (uint256 value, uint256 margin)
    {
	TokenValue[] memory tokenValues = appraiseFungibleTokens(tokens, amounts);

	for (uint256 i = 0; i < tokenValues.length; i++) {
	    value += tokenValues[i].value;
	    margin += tokenValues[i].margin;
	}
    }

    function appraiseNonFungibleToken(address token, uint256 tokenId)
	internal
	view
	virtual
	returns (TokenValue[] memory)
    {
	TokenInfo memory inf = REGISTRAR.getTokenInfoOf(token);
	require(inf.type_ == TokenType.NonFungible, "require non-fungible token");

	INonfungibleInspector inspector = INonfungibleInspector(inf.priceOracle);

	address[] memory tokens;
	uint256[] memory amounts;

	(tokens, amounts) = inspector.inspectPosition(tokenId);

	return appraiseFungibleTokens(tokens, amounts);
    }

    function getAppraisalsOfNonFungible(address token, uint256 tokenId)
	external
	view
	override
	returns (address[] memory tokens, uint256[] memory values, uint256[] memory margins)
    {
	TokenValue[] memory tokenValues = appraiseNonFungibleToken(token, tokenId);
	uint256 length = tokenValues.length;

	tokens = new address[](length);
	values = new uint256[](length);
	margins = new uint256[](length);

	for (uint256 i = 0; i < length; i++) {
	    tokens[i] = tokenValues[i].token;
	    values[i] = tokenValues[i].value;
	    margins[i] = tokenValues[i].margin;
	}
    }

    function getAppraisalOfNonFungibles(address[] calldata tokens, uint256[] calldata tokenIds)
	external
	view
	returns (uint256 value, uint256 margin)
    {
	for (uint256 i = 0; i < tokenIds.length; i++) {
	    TokenValue[] memory tokenValues = appraiseNonFungibleToken(tokens[i], tokenIds[i]);

	    for (uint256 j = 0; j < tokenValues.length; j++) {
		value += tokenValues[j].value;
		margin += tokenValues[j].margin;
	    }
	}
    }

    function rescue(uint256 positionId) external override {}
}
