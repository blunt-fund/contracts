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

    DeployBluntDelegateDeployerData memory _deployerData = DeployBluntDelegateDeployerData(
      _jbController,
      uint48(_bluntProjectId),
      2,
      0,
      address(1),
      address(2),
      uint16(_maxK),
      uint16(_minK),
      uint56(_upperFundraiseBoundary),
      uint56(_lowerFundraiseBoundary)
    );

    hevm.expectRevert('Initializable: contract is already initialized');
    implementation.initialize(_deployerData, deployBluntDelegateData);
  }
}
