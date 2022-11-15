// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleDataSource.sol';

import '../structs/Contribution.sol';
import '../structs/DeployBluntDelegateData.sol';

interface IBluntDelegate is
  IJBFundingCycleDataSource,
  IJBPayDelegate,
  IJBRedemptionDelegate,
  IERC1155Receiver,
  IERC721Receiver
{
  function closeRound() external;

  function transferUnclaimedSlicesTo(address[] calldata beneficiaries) external;

  function claimSlices() external;
}
