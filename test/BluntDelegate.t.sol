// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {DSTestPlus} from 'solmate/test/utils/DSTestPlus.sol';

import {BluntDelegate} from 'contracts/BluntDelegate.sol';

contract BluntDelegateTest is DSTestPlus {
  BluntDelegate delegate;

  function setUp() public {
    delegate = new BluntDelegate();
  }

  function testDoSomething() public {}

  receive() external payable {}
}
