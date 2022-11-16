// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './helper/BluntSetup.sol';
import 'contracts/BluntDelegateProjectDeployer.sol';

contract BluntDelegateProjectDeployerTest is BluntSetup {
  BluntDelegateProjectDeployer public bluntDeployer;

  function setUp() public virtual override {
    BluntSetup.setUp();

    bluntDeployer = new BluntDelegateProjectDeployer(_jbController, _jbOperatorStore);
  }

  function testLaunchProject() public {
    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    uint256 projectId = bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData);

    assertEq(projectId, 1);
  }

  function testDelegateAddressIsProjectOwner() public {
    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    uint256 projectId = bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData);
    address owner = _jbProjects.ownerOf(projectId);
    (, JBFundingCycleMetadata memory metadata) = _jbController.currentFundingCycleOf(projectId);

    assertEq(owner, metadata.dataSource);
  }

  function testMetadataOverwrite() public {
    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    // Set wrong metadata
    launchProjectData.metadata.dataSource = address(2);
    launchProjectData.metadata.useDataSourceForPay = false;
    launchProjectData.metadata.useDataSourceForRedeem = false;
    launchProjectData.metadata.redemptionRate = 2;
    launchProjectData.metadata.global.pauseTransfers = false;

    uint256 projectId = bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData);
    (, JBFundingCycleMetadata memory metadata) = _jbController.currentFundingCycleOf(projectId);

    assertFalse(metadata.dataSource == address(2));
    assertBoolEq(metadata.useDataSourceForPay, true);
    assertBoolEq(metadata.useDataSourceForRedeem, true);
    assertEq(metadata.redemptionRate, JBConstants.MAX_REDEMPTION_RATE);
    assertBoolEq(metadata.global.pauseTransfers, true);
  }

  ///////////////////////////////////////
  /////////////// REVERTS ///////////////
  ///////////////////////////////////////
  function testRevertInvalidWeight() public {
    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    launchProjectData.data.weight = 0;

    hevm.expectRevert(bytes4(keccak256('INVALID_TOKEN_ISSUANCE()')));
    bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData);

    launchProjectData.data.weight = 1e14;

    hevm.expectRevert(bytes4(keccak256('INVALID_TOKEN_ISSUANCE()')));
    bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData);
  }
}
