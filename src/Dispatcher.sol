// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.19;

import {IBookkeeper} from "amplifi-v1-common/interfaces/IBookkeeper.sol";
import {IRegistrar} from "amplifi-v1-common/interfaces/IRegistrar.sol";

import {IDispatcher} from "./interfaces/IDispatcher.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";

contract Dispatcher is IDispatcher {
    IRegistrar public immutable REG;
    IBookkeeper public immutable BK;
    address public immutable PUD;

    constructor(address registrar) {
        REG = IRegistrar(registrar);
        BK = IBookkeeper(REG.getBookkeeper());
        PUD = REG.getPUD();
    }

    function mintWithFungible(address token, uint256 amount) external returns (uint256 positionId) {
        positionId = BK.mint(address(0), msg.sender);
        this.depositFungible(positionId, token, amount);
    }

    function depositFungible(uint256 positionId, address token, uint256 amount) external {
        TransferHelper.safeTransferFrom(token, msg.sender, address(BK), amount);
        BK.depositFungible(positionId, token);
    }

    function repay(uint256 positionId, uint256 amount) external {
        TransferHelper.safeTransferFrom(PUD, msg.sender, address(BK), amount);
        BK.repay(positionId, amount);
    }

    function repayAll(uint256 positionId) external {
        uint256 debt = BK.getDebtOf(positionId);
        uint256 pudExists = 0; // TODO get current PUD in position

        if (debt > pudExists) {
            uint256 pudNeeded = debt - pudExists;
            this.depositFungible(positionId, PUD, pudNeeded);
        }

        BK.repay(positionId, debt);
    }
}
