// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPrices.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol';

struct DeployBluntDelegateData {
  address projectOwner;
  uint88 hardcap;
  uint88 target;
  uint40 duration;
  bool isTargetUsd;
  bool isHardcapUsd;
}
