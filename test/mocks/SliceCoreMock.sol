// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import 'contracts/interfaces/ISliceCore.sol';

contract SliceCoreMock is ERC1155 {
  constructor() ERC1155('') {}

  uint256 public tokenId;

  function slice(
    SliceParams calldata params
  ) external returns (uint256 slicerId, address slicerAddress) {
    tokenId++;
    slicerId = tokenId;
    _mint(params.payees[0].account, slicerId, params.payees[0].shares, '');
    slicerAddress = address(uint160(slicerId));
  }

  function slicerBatchTransfer(
    address from,
    address[] memory recipients,
    uint256 id,
    uint256[] memory amounts,
    bool
  ) external {
    for (uint256 i; i < recipients.length; i++) {
      _safeTransferFrom(from, recipients[i], id, amounts[i], '');
    }
  }

  function safeTransferFromUnreleased(
    address from,
    address to,
    uint256 id,
    uint256 amount,
    bytes memory data
  ) external {
    _safeTransferFrom(from, to, id, amount, data);
  }
}
