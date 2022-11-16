// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {DSTestPlus} from 'solmate/test/utils/DSTestPlus.sol';

import '@jbx-protocol/juice-721-delegate/contracts/forge-test/utils/TestBaseWorkflow.sol';
import {BluntDelegateProjectDeployer} from 'contracts/BluntDelegateProjectDeployer.sol';

contract BluntDelegateProjectDeployerTest is DSTestPlus {
  BluntDelegateProjectDeployer deployer;

  address projectOwner = address(bytes20(keccak256('projectOwner')));

  function setUp() public {
    TestBaseWorkflow.setUp();

    deployer = new BluntDelegateProjectDeployer(_jbController);
  }

  function testDoSomething() public {}

  receive() external payable {}
}
