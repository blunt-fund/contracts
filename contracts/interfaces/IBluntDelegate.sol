// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleDataSource.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol';
import '../structs/DeployBluntDelegateDeployerData.sol';
import '../structs/DeployBluntDelegateData.sol';
import '../structs/RoundInfo.sol';

interface IBluntDelegate is
  IJBFundingCycleDataSource,
  IJBPayDelegate,
  IJBRedemptionDelegate,
  IERC721Receiver
{
  function getRoundInfo() external view returns (RoundInfo memory roundInfo);

  function closeRound() external;

  function setDeadline(uint256 deadline_) external;

  function isTargetReached() external view returns (bool);
}
