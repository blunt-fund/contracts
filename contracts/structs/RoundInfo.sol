// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol';

struct RoundInfo {
  uint256 totalContributions;
  uint256 target;
  uint256 hardcap;
  uint40 releaseTimelock;
  uint40 transferTimelock;
  address projectOwner;
  uint40 fundingCycleRound;
  uint16 afterRoundReservedRate;
  JBSplit[] afterRoundSplits;
  string tokenName;
  string tokenSymbol;
  bool isRoundClosed;
  bool isQueued;
  bool isSlicerToBeCreated;
  uint256 slicerId;
}
