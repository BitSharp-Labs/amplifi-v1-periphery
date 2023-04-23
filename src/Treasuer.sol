// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.19;

import {IRegistrar} from "amplifi-v1-common/interfaces/IRegistrar.sol";
import {ITreasurer} from "amplifi-v1-common/interfaces/ITreasurer.sol";
import {TokenInfo, TokenType, TokenSubtype} from "amplifi-v1-common/models/TokenInfo.sol";

import {FixedPoint96} from "./utils/FixedPoint96.sol";
import {MathHelper} from "./utils/MathHelper.sol";
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
        values = new uint[](tokens.length);

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
