// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '../interfaces/ISliceCore.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleStore.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol';

struct DeployBluntDelegateData {
  IJBDirectory directory;
  IJBFundingCycleStore fundingCycleStore;
  ISliceCore sliceCore;
  address projectOwner;
  uint256 hardcap;
  uint256 target;
  uint256 releaseTimelock;
  uint256 transferTimelock;
  uint256 afterRoundReservedRate;
  JBSplit[] afterRoundSplits;
  string tokenName;
  string tokenSymbol;
  bool enforceSlicerCreation;
  bool isTargetUsd;
  bool isHardcapUsd;
}
