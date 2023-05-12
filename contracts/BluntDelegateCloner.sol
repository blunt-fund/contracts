// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@openzeppelin/contracts/proxy/Clones.sol';
import './BluntDelegateClone.sol';
import './interfaces/IBluntDelegateCloner.sol';
import {IJBDelegatesRegistry} from './interfaces/IJBDelegatesRegistry.sol';

contract BluntDelegateCloner is IBluntDelegateCloner {
  //*********************************************************************//
  // ------------------------ immutable storage ------------------------ //
  //*********************************************************************//

  address public immutable implementation;

  /** 
    @notice
    JB delegates registry address
  */
  IJBDelegatesRegistry public immutable override delegatesRegistry;

  //*********************************************************************//
  // ------------------------  mutable storage  ------------------------ //
  //*********************************************************************//

  /** 
    @notice 
    This contract current nonce, used for the registry
  */
  uint256 private _nonce;

  //*********************************************************************//
  // --------------------------- constructor --------------------------- //
  //*********************************************************************//

  /**
   * @notice Initializes the contract and deploys the clone implementation.
   */
  constructor(IJBDelegatesRegistry _registry) {
    implementation = address(new BluntDelegateClone());
    delegatesRegistry = _registry;
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

    unchecked {
      // Add the delegate to the registry, contract nonce starts at 1
      delegatesRegistry.addDelegate(address(this), ++_nonce);
    }

    emit DelegateDeployed(_deployBluntDelegateDeployerData.projectId, newDelegate);
  }
}
