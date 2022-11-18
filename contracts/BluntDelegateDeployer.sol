// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './BluntDelegate.sol';
import './interfaces/IBluntDelegateDeployer.sol';

abstract contract BluntDelegateDeployer is IBluntDelegateDeployer {
  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /** 
    @notice
    Deploys a Tiered limited NFT reward data source.

    @param _projectId The ID of the project for which the data source should apply.
    @param _duration Blunt round duration
    @param _deployBluntDelegateData Data necessary to fulfill the transaction to deploy a tiered limited NFT rewward data source.

    @return newDelegate The address of the newly deployed data source.
  */
  function deployDelegateFor(
    uint256 _projectId,
    uint256 _duration,
    DeployBluntDelegateData memory _deployBluntDelegateData
  ) internal returns (address newDelegate) {
    newDelegate = address(new BluntDelegate(_projectId, _duration, _deployBluntDelegateData));

    emit DelegateDeployed(_projectId, newDelegate);

    return newDelegate;
  }
}
