// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '../structs/Contribution.sol';

interface IBluntDelegate {
  function issueSlices() external;

  function transferUnclaimedSlicesTo(address[] calldata beneficiaries) external;

  function claimSlices() external;
}
