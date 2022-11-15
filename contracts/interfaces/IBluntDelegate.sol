// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '../structs/Contribution.sol';
import '../structs/DeployBluntDelegateData.sol';

interface IBluntDelegate {
  function issueSlices() external;

  function transferUnclaimedSlicesTo(address[] calldata beneficiaries) external;

  function claimSlices() external;
}
