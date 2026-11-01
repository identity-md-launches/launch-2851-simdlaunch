// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Simdlaunch} from "../../src/Simdlaunch.sol";

/// @dev Local fixture only: demonstrates that CREATE/CREATE2 mint to the immediate deployer.
contract TokenFactory {
    function deploy() external returns (Simdlaunch) {
        return new Simdlaunch();
    }

    function deployDeterministic(bytes32 salt) external returns (Simdlaunch) {
        return new Simdlaunch{salt: salt}();
    }

    function distribute(Simdlaunch token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "fixture transfer failed");
    }
}
