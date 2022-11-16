// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './helper/BluntSetup.sol';
import 'contracts/BluntDelegate.sol';
import 'contracts/BluntDelegateProjectDeployer.sol';

contract BluntDelegateTest is BluntSetup {
  BluntDelegateProjectDeployer public bluntDeployer;
  BluntDelegate public bluntDelegate;

  function setUp() public virtual override {
    BluntSetup.setUp();

    bluntDeployer = new BluntDelegateProjectDeployer(_jbController, _jbOperatorStore);

    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    uint256 projectId = bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData);

    bluntDelegate = BluntDelegate(_jbProjects.ownerOf(projectId));
  }

  function testSomething() public {}
}
