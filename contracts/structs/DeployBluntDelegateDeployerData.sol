// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPrices.sol';

struct DeployBluntDelegateDeployerData {
  IJBDirectory directory;
  IJBController controller;
  IJBPrices prices;
  uint48 feeProjectId;
  uint48 projectId;
  uint16 maxK;
  uint16 minK;
  uint56 upperFundraiseBoundary;
  uint56 lowerFundraiseBoundary;
}
