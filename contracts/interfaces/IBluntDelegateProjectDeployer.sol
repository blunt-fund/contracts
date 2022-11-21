// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBProjects.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol';
import './IBluntDelegateDeployer.sol';
import '../structs/DeployBluntDelegateData.sol';
import '../structs/JBLaunchProjectData.sol';

interface IBluntDelegateProjectDeployer {
  function controller() external view returns (IJBController);

  function delegateDeployer() external view returns (IBluntDelegateDeployer);

  function launchProjectFor(
    DeployBluntDelegateData memory _deployBluntDelegateData,
    JBLaunchProjectData memory _launchProjectData
  ) external returns (uint256 projectId);
}
