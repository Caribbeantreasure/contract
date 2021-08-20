// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract simpleToken is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimal,
        uint256 amount
    ) public ERC20(name_, symbol_) {
        _setupDecimals(decimal);
        _mint(msg.sender, amount);
    }
}
