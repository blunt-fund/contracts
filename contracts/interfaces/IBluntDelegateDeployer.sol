// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '@jbx-protocol/contracts-v2/contracts/interfaces/IJBController.sol';
import '@jbx-protocol/contracts-v2/contracts/interfaces/IJBProjects.sol';
import '@jbx-protocol/contracts-v2/contracts/structs/JBProjectMetadata.sol';
import '../structs/DeployBluntDelegateData.sol';

interface IBluntDelegateDeployer {
  event DelegateDeployed(uint256 indexed projectId, address newDelegate);

  function deployDelegateFor(
    uint256 _projectId,
    DeployBluntDelegateData memory _deployBluntDelegateData
  ) external returns (address delegate);
}
