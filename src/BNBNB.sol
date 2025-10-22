// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BNBNB is ERC20 {
    constructor() ERC20("BNBNB", "BNBNB") {
        // 发行 1,000,000 BNBNB (含 18 位小数)
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }
}
