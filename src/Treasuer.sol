// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.19;

import {mulDiv18} from "prb-math/Common.sol";

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

    function getAppraisalOfFungibleToken(address token, uint256 amount)
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

    function getAppraisalOfFungibleTokens(address[] calldata tokens, uint256[] calldata amounts)
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

    function valueOfPancakeNFT(uint256 tokenId) internal view virtual returns (TokenValue[] memory) {
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

        return appraiseFungibleTokens(tokens, amounts);
    }

    function appraiseNonFungibleToken(address token, uint256 tokenId)
        internal
        view
        virtual
        returns (TokenValue[] memory)
    {
        TokenInfo memory inf = REGISTRAR.getTokenInfoOf(token);
        require(inf.type_ == TokenType.NonFungible, "require non-fungible token");

        // only support pancake like NFT now
        return valueOfPancakeNFT(tokenId);
    }

    function getAppraisalOfNonFungibleToken(address token, uint256 tokenId)
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

    function getAppraisalOfNonFungibleTokens(address[] calldata tokens, uint256[] calldata tokenIds)
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
