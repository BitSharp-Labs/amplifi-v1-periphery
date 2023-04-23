// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.19;

import {IRegistrar} from "amplifi-v1-common/interfaces/IRegistrar.sol";
import {ITreasurer} from "amplifi-v1-common/interfaces/ITreasurer.sol";
import {TokenInfo, TokenType, TokenSubtype} from "amplifi-v1-common/models/TokenInfo.sol";

import {FixedPoint96} from "./utils/FixedPoint96.sol";
import {IPancakePool} from "./interfaces/pancake/IPancakePool.sol";

contract Treasurer is ITreasurer {
    IRegistrar public immutable REGISTRAR;

    address public PUD;

    constructor(address registrar) {
	REGISTRAR = IRegistrar(registrar);
	REGISTRAR.setTreasurer(address(this));
    }

    function initialize() external {
	PUD = REGISTRAR.getPUD();
    }

    function priceBx96FromSwapPool(address poolAddr, address token0) internal view returns (uint) {
	// TODO
	return FixedPoint96.Q96;
    }

    function getValueOfFungibleToken(address token, uint256 amount) external view returns (uint256 value) {
	// value caculate with two step: token -> middle token -> pud

	TokenInfo memory tokenInf = REGISTRAR.getTokenInfoOf(token);
	TokenInfo memory pudInf = REGISTRAR.getTokenInfoOf(PUD);

	uint price1 = priceBx96FromSwapPool(tokenInf.priceOracle, token);
	uint price2 = priceBx96FromSwapPool(pudInf.priceOracle, PUD);

	// TODO
	return price1 * amount / price2;
    }

    function getValuesOfFungibleTokens(address[] calldata tokens, uint256[] calldata amounts)
	external
	view
	override
	returns (uint256[] memory values)
    {}

    function getValueOfNonFungibleToken(address token, uint256 tokenId)
	external
	view
	override
	returns (uint256 value)
    {}

    function getValuesOfNonFungibleTokens(address token, uint256[] calldata tokenIds)
	external
	view
	override
	returns (uint256[] memory values)
    {}

    function getValuesOfNonFungibleTokens(address[] calldata tokens, uint256[] calldata tokenIds)
	external
	view
	returns (uint256[] memory values)
    {}

    function rescue(uint256 positionId) external override {}
}
