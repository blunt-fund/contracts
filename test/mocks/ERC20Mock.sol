// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract ERC20Mock is ERC20 {
  constructor(address receiver) ERC20('test', 'TEST') {
    _mint(receiver, 1e18);
  }
}
