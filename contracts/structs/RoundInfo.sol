// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol';

struct RoundInfo {
  uint256 totalContributions;
  uint256 target;
  uint256 hardcap;
  uint256 releaseTimelock;
  uint256 transferTimelock;
  address projectOwner;
  uint256 afterRoundReservedRate;
  JBSplit[] afterRoundSplits;
  string tokenName;
  string tokenSymbol;
  bool isRoundClosed;
  uint256 deadline;
  bool isTargetUsd;
  bool isHardcapUsd;
  bool isSlicerToBeCreated;
  uint256 slicerId;
}
