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
    Deploys a BluntDelegate data source.

    @param _controller JBController address
    @param _projectId The ID of the project for which the data source should apply.
    @param _duration Blunt round duration
    @param _ethAddress WETH address on Uniswap
    @param _usdcAddress USDC address on Uniswap
    @param _deployBluntDelegateData Data necessary to fulfill the transaction to deploy a BluntDelegate data source.

    @return newDelegate The address of the newly deployed data source.
  */
  function deployDelegateFor(
    IJBController _controller,
    uint256 _projectId,
    uint256 _duration,
    address _ethAddress,
    address _usdcAddress,
    DeployBluntDelegateData memory _deployBluntDelegateData
  ) external returns (address newDelegate) {
    // Deploys proxy clone
    newDelegate = Clones.clone(implementation);

    // Initialize proxy
    BluntDelegateClone(newDelegate).initialize(
      _controller,
      _projectId,
      _duration,
      _ethAddress,
      _usdcAddress,
      _deployBluntDelegateData
    );

    emit DelegateDeployed(_projectId, newDelegate);
  }
}
