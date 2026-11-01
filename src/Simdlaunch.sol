// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Simdlaunch (SIMD)
/// @notice A fixed supply of one billion tokens, with 18 decimals, minted to the deployer.
/// @dev The constructor caller receives the entire supply. There are no administrative powers
/// or external mint/burn functions. Transfers use the unmodified OpenZeppelin ERC-20 behavior.
contract Simdlaunch is ERC20 {
    /// @notice The entire supply in the token's smallest units (10^27).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Simdlaunch", "SIMD") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
