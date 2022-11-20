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
    Deploys a BluntDelegate data source.

    @param _projectId The ID of the project for which the data source should apply.
    @param _duration Blunt round duration
    @param _ethAddress WETH address on Uniswap
    @param _usdcAddress USDC address on Uniswap
    @param _deployBluntDelegateData Data necessary to fulfill the transaction to deploy a BluntDelegate data source.

    @return newDelegate The address of the newly deployed data source.
  */
  function deployDelegateFor(
    uint256 _projectId,
    uint256 _duration,
    address _ethAddress,
    address _usdcAddress,
    DeployBluntDelegateData memory _deployBluntDelegateData
  ) internal returns (address newDelegate) {
    newDelegate = address(
      new BluntDelegate(_projectId, _duration, _ethAddress, _usdcAddress, _deployBluntDelegateData)
    );

    emit DelegateDeployed(_projectId, newDelegate);

    return newDelegate;
  }
}
