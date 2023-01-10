// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleDataSource.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol';
import '../structs/DeployBluntDelegateDeployerData.sol';
import '../structs/DeployBluntDelegateData.sol';
import '../structs/RoundInfo.sol';

interface IBluntDelegate is
  IJBFundingCycleDataSource,
  IJBPayDelegate,
  IJBRedemptionDelegate,
  IERC1155Receiver,
  IERC721Receiver
{
  function getRoundInfo() external view returns (RoundInfo memory roundInfo);

  function transferUnclaimedSlicesTo(address[] calldata beneficiaries) external;

  function claimSlices() external;

  function setTokenMetadata(string memory tokenName_, string memory tokenSymbol_) external;

  function transferToken(IERC20 token) external;

  function closeRound() external;

  function isTargetReached() external view returns (bool);
}
