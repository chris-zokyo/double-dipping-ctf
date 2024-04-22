// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GAVT is ERC20 {


    constructor(uint256 _totalSupply) ERC20("AVA Governance Token", "GAVT") {
        _mint(msg.sender, _totalSupply);
    }

}