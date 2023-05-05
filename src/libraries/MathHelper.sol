// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.19;

import {mulDiv} from "prb-math/Common.sol";

library MathHelper {
    function mulDivRoundingUp(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        result = mulDiv(a, b, denominator);
        if (mulmod(a, b, denominator) > 0) {
            require(result < type(uint256).max);
            result++;
        }
    }

    function divRoundingUp(uint256 numerator, uint256 denominator) internal pure returns (uint256 result) {
        assembly {
            result := add(div(numerator, denominator), gt(mod(numerator, denominator), 0))
        }
    }
}
