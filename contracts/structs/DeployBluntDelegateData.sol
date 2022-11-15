// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '../interfaces/ISliceCore.sol';
import '@jbx-protocol/contracts-v2/contracts/interfaces/IJBDirectory.sol';
import '@jbx-protocol/contracts-v2/contracts/interfaces/IJBTokenStore.sol';
import '@jbx-protocol/contracts-v2/contracts/interfaces/IJBFundingCycleStore.sol';

/**
  @member directory The directory of terminals and controllers for projects.
  @member tokenStore The token store.
  @memver hardCap The hard cap of project tokens that can be issued.
*/
struct DeployBluntDelegateData {
  IJBDirectory directory;
  IJBTokenStore tokenStore;
  IJBFundingCycleStore fundingCycleStore;
  ISliceCore sliceCore;
  address projectOwner;
  uint88 hardCap;
  uint88 target;
  uint40 releaseTimelock;
  uint40 transferTimelock;
}
