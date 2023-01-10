// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol';

struct DeployBluntDelegateDeployerData {
  IJBController controller;
  uint48 bluntProjectId;
  uint48 projectId;
  uint40 duration;
  address ethAddress;
  address usdcAddress;
  uint16 maxK;
  uint16 minK;
  uint56 upperFundraiseBoundary;
  uint56 lowerFundraiseBoundary;
}
