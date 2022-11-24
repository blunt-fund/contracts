// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './IBluntDelegate.sol';

interface IBluntDelegateClone is IBluntDelegate {
  function initialize(
    IJBController _controller,
    uint256 _projectId,
    uint256 _duration,
    address _ethAddress,
    address _usdcAddress,
    DeployBluntDelegateData memory _deployBluntDelegateData
  ) external;
}
