// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './setup/TestBaseWorkflow.sol';
import {BluntDelegateProjectDeployer} from 'contracts/BluntDelegateProjectDeployer.sol';

contract BluntDelegateProjectDeployerTest is TestBaseWorkflow {
  BluntDelegateProjectDeployer deployer;

  address projectOwner = address(bytes20(keccak256('projectOwner')));

  function setUp() public virtual override {
    TestBaseWorkflow.setUp();

    deployer = new BluntDelegateProjectDeployer(_jbController, _jbOperatorStore);
  }

  function testDoSomething() public {}

  receive() external payable {}
}
