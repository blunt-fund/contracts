// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol';
import '../structs/DeployBluntDelegateData.sol';

interface IBluntDelegateDeployer {
  event DelegateDeployed(uint256 indexed projectId, address newDelegate);

  function deployDelegateFor(
    IJBController _controller,
    uint256 _projectId,
    uint256 _duration,
    address _ethAddress,
    address _usdcAddress,
    DeployBluntDelegateData memory _deployBluntDelegateData
  ) external returns (address newDelegate);
}
