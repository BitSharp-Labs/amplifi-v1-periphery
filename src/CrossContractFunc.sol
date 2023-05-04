// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.19;

contract CrossContractFunc {
    enum Function {
        None,
        Mint,
        Collect,
        ExactInputSingle
    }

    Function private _runningFunc;

    modifier runFunc(Function func) {
        require(_runningFunc == Function.None, "other function is running");
        _runningFunc = func;
        _;
        _runningFunc = Function.None;
    }

    function runningFunc() internal view returns (Function) {
        return _runningFunc;
    }
}
