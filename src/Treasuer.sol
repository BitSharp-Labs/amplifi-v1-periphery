// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.19;

import {ITreasurer} from "amplifi-v1-common/interfaces/ITreasurer.sol";

contract Treasurer is ITreasurer {
    function rescue(uint256 positionId) external override {}
}
