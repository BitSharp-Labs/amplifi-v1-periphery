// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >0.7.0;
pragma abicoder v2;

interface IDispatcher {
    function mintWithFungible(address token, uint256 amount) external returns (uint256 positionId);

    function depositFungible(uint256 positionId, address token, uint256 amount) external;

    function repay(uint256 positionId, uint256 amount) external;

    function repayAll(uint256 positionId) external;
}
