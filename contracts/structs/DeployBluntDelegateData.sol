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
  uint88 hardcap;
  uint88 target;
  uint40 releaseTimelock;
  uint40 transferTimelock;
  uint16 afterRoundReservedRate;
  JBSplit[] afterRoundSplits;
  string tokenName;
  string tokenSymbol;
  bool enforceSlicerCreation;
  bool isTargetUsd;
  bool isHardcapUsd;
  uint256 maxK;
  uint256 minK;
  uint256 upperBoundary;
  uint256 lowerBoundary;
}
