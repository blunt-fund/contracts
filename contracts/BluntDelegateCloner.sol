// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@openzeppelin/contracts/proxy/Clones.sol';
import './BluntDelegateClone.sol';
import './interfaces/IBluntDelegateCloner.sol';

contract BluntDelegateCloner is IBluntDelegateCloner {
  //*********************************************************************//
  // ------------------------ immutable storage ------------------------ //
  //*********************************************************************//

  address public immutable implementation;

  //*********************************************************************//
  // --------------------------- constructor --------------------------- //
  //*********************************************************************//

  /**
   * @notice Initializes the contract and deploys the clone implementation.
   */
  constructor() {
    implementation = address(new BluntDelegateClone());
  }

  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /** 
    @notice
    Deploys a BluntDelegate data source as immutable clone.

    @param _deployBluntDelegateDeployerData Data sent from the BluntDelegateProjectDeployer contract
    @param _deployBluntDelegateData Data necessary to fulfill the transaction to deploy a BluntDelegate data source.

    @return newDelegate The address of the newly deployed data source.
  */
  function deployDelegateFor(
    DeployBluntDelegateDeployerData memory _deployBluntDelegateDeployerData,
    DeployBluntDelegateData memory _deployBluntDelegateData
  ) external returns (address newDelegate) {
    // Deploys proxy clone
    newDelegate = Clones.clone(implementation);

    // Initialize proxy
    BluntDelegateClone(newDelegate).initialize(
      _deployBluntDelegateDeployerData,
      _deployBluntDelegateData
    );

    emit DelegateDeployed(_deployBluntDelegateDeployerData.projectId, newDelegate);
  }
}
