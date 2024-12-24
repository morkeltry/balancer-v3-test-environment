// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../interfaces/contracts/futarchy/IERC20Extended.sol";

contract ERC20Extended is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {

    }
}
