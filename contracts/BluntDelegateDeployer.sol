// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './BluntDelegate.sol';
import './interfaces/IBluntDelegateDeployer.sol';

contract BluntDelegateDeployer is IBluntDelegateDeployer {
  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /** 
    @notice
    Deploys a BluntDelegate data source.

    @param _deployBluntDelegateDeployerData Data sent from the BluntDelegateProjectDeployer contract
    @param _deployBluntDelegateData Data necessary to fulfill the transaction to deploy a BluntDelegate data source.
    
    @return newDelegate The address of the newly deployed data source.
  */
  function deployDelegateFor(
    DeployBluntDelegateDeployerData memory _deployBluntDelegateDeployerData,
    DeployBluntDelegateData memory _deployBluntDelegateData
  ) external returns (address newDelegate) {
    newDelegate = address(
      new BluntDelegate(_deployBluntDelegateDeployerData, _deployBluntDelegateData)
    );

    emit DelegateDeployed(_deployBluntDelegateDeployerData.projectId, newDelegate);
  }
}
