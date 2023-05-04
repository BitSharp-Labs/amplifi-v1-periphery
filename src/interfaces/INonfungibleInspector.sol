// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >0.7.0;
pragma abicoder v2;

interface INonfungibleInspector {
    function inspectPosition(uint256 positionId)
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts);
}
