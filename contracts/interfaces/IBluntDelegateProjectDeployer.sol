// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBProjects.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol';
import './IBluntDelegateDeployer.sol';
import './IBluntDelegateCloner.sol';
import '../structs/DeployBluntDelegateData.sol';
import '../structs/JBLaunchProjectData.sol';

interface IBluntDelegateProjectDeployer {
  function controller() external view returns (IJBController3_1);

  function delegateDeployer() external view returns (IBluntDelegateDeployer);

  function delegateCloner() external view returns (IBluntDelegateCloner);

  function launchProjectFor(
    DeployBluntDelegateData memory _deployBluntDelegateData,
    JBLaunchProjectData memory _launchProjectData,
    bool _clone
  ) external returns (uint256 projectId);

  function _setDelegates(
    IBluntDelegateDeployer newDelegateDeployer_,
    IBluntDelegateCloner newDelegateCloner_
  ) external;

  function _setFees(
    uint16 maxK_,
    uint16 minK_,
    uint56 upperFundraiseBoundary_,
    uint56 lowerFundraiseBoundary_
  ) external;
}
