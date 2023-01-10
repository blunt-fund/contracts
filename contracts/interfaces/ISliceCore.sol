// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './ISlicer.sol';
import './ISlicerManager.sol';
import '@openzeppelin/interfaces/IERC1155.sol';
import '@openzeppelin/interfaces/IERC2981.sol';

interface ISliceCore is IERC1155, IERC2981 {
  function slicerManager() external view returns (ISlicerManager slicerManagerAddress);

  function slice(
    SliceParams calldata params
  ) external returns (uint256 slicerId, address slicerAddress);

  function reslice(
    uint256 tokenId,
    address payable[] calldata accounts,
    int32[] calldata tokensDiffs
  ) external;

  function slicerBatchTransfer(
    address from,
    address[] memory recipients,
    uint256 id,
    uint256[] memory amounts,
    bool release
  ) external;

  function safeTransferFromUnreleased(
    address from,
    address to,
    uint256 id,
    uint256 amount,
    bytes memory data
  ) external;

  function setController(uint256 id, address newController) external;

  function setRoyalty(
    uint256 tokenId,
    bool isSlicer,
    bool isActive,
    uint256 royaltyPercentage
  ) external;

  function _slicers(
    uint256 id
  ) external view returns (ISlicer, address, uint40, uint32, uint8, uint8, uint8);

  function slicers(uint256 id) external view returns (address);

  function controller(uint256 id) external view returns (address);

  function totalSupply(uint256 id) external view returns (uint256);

  function supply() external view returns (uint256);

  function exists(uint256 id) external view returns (bool);

  function owner() external view returns (address owner);

  function _setBasePath(string calldata basePath_) external;

  function _togglePause() external;
}
