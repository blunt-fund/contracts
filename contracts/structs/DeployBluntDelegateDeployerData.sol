// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol';

struct DeployBluntDelegateDeployerData {
  IJBController controller;
  uint256 bluntProjectId;
  uint256 projectId;
  uint256 duration;
  address ethAddress;
  address usdcAddress;
  uint256 maxK;
  uint256 minK;
  uint256 upperFundraiseBoundary;
  uint256 lowerFundraiseBoundary;
}
