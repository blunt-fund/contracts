// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '@jbx-protocol/contracts-v2/contracts/interfaces/IJBDirectory.sol';
import '@jbx-protocol/contracts-v2/contracts/interfaces/IJBTokenStore.sol';

/**
  @member directory The directory of terminals and controllers for projects.
  @member tokenStore The token store.
  @memver hardCap The hard cap of project tokens that can be issued.
*/
struct DeployBluntDelegateData {
  IJBDirectory directory;
  IJBTokenStore tokenStore;
  uint256 hardCap;
}
