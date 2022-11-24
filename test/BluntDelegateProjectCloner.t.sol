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

  function testRevert_implementationNotInitializable() public {
    (DeployBluntDelegateData memory deployBluntDelegateData, ) = _formatDeployData();
    IBluntDelegateClone implementation = IBluntDelegateClone(delegateCloner.implementation());

    hevm.expectRevert('Initializable: contract is already initialized');
    implementation.initialize(_jbController, 1, 0, address(0), address(0), deployBluntDelegateData);
  }
}
