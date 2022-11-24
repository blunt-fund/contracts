// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './BluntDelegateProjectDeployer.t.sol';

contract BluntDelegateProjectClonerTest is BluntDelegateProjectDeployerTest {
  //*********************************************************************//
  // ------------------------------ setup ------------------------------ //
  //*********************************************************************//

  function setUp() public virtual override {
    _clone = true;
    BluntDelegateProjectDeployerTest.setUp();
  }
}
