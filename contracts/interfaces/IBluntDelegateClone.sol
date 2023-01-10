// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './IBluntDelegate.sol';

interface IBluntDelegateClone is IBluntDelegate {
  function initialize(
    DeployBluntDelegateDeployerData memory _deployBluntDelegateDeployerData,
    DeployBluntDelegateData memory _deployBluntDelegateData
  ) external;
}
