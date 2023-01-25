// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol';

/**
  @member projectMetadata Metadata to associate with the project within a particular domain. This can be updated any time by the owner of the project.
  @member duration A duration for the managed round. Send 0 for no duration.
  @member mustStartAtOrAfter The time before which the configured funding cycle cannot start.
  @member terminals Payment terminals to add for the project.
  @member memo A memo to pass along to the emitted event.
*/
struct JBLaunchProjectData {
  JBProjectMetadata projectMetadata;
  uint40 duration;
  uint256 mustStartAtOrAfter;
  IJBPaymentTerminal[] terminals;
  string memo;
}
