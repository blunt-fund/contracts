// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './BluntDelegate.t.sol';

contract BluntDelegateCloneTest is BluntDelegateTest {
  //*********************************************************************//
  // ------------------------------ setup ------------------------------ //
  //*********************************************************************//

  function setUp() public virtual override {
    _clone = true;
    BluntDelegateTest.setUp();
  }
}
