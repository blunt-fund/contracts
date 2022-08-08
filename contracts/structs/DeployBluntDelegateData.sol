// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '@jbx-protocol/contracts-v2/contracts/interfaces/IJBDirectory.sol';

/**
  @member directory The directory of terminals and controllers for projects.
*/
struct DeployBluntDelegateData {
  IJBDirectory directory;
}
