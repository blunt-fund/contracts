// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '../structs/DeployBluntDelegateData.sol';

interface IBluntDelegateDeployer {
  event DelegateDeployed(uint256 indexed projectId, address newDelegate);
}
