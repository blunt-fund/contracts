// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPrices.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol';
import './IBluntDelegateDeployer.sol';
import '../structs/DeployBluntDelegateData.sol';
import '../structs/JBLaunchProjectData.sol';

interface IBluntDelegateProjectDeployer {
  function directory() external view returns (IJBDirectory);

  function controller() external view returns (IJBController);

  function prices() external view returns (IJBPrices);

  function delegateDeployer() external view returns (IBluntDelegateDeployer);

  function launchProjectFor(
    DeployBluntDelegateData memory _deployBluntDelegateData,
    JBLaunchProjectData memory _launchProjectData
  ) external returns (uint256 projectId);

  function _setDelegates(IBluntDelegateDeployer newDelegateDeployer_) external;

  function _setFees(
    uint16 maxK_,
    uint16 minK_,
    uint56 upperFundraiseBoundary_,
    uint56 lowerFundraiseBoundary_
  ) external;
}
