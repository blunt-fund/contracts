// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@jbx-protocol/juice-contracts-v3/contracts/abstract/JBOperatable.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBConstants.sol';
import './interfaces/IBluntDelegateProjectDeployer.sol';

contract BluntDelegateProjectDeployer is IBluntDelegateProjectDeployer, JBOperatable {
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//
  error INVALID_TOKEN_ISSUANCE();

  //*********************************************************************//
  // --------------- public immutable stored properties ---------------- //
  //************************************* ********************************//

  /**
    @notice
    Ratio between amount of eth contributed and tokens minted
  */
  uint64 public constant TOKENS_PER_ETH = 1e15;

  /**
    @notice
    WETH address on Uniswap
  */
  address public immutable ethAddress;

  /**
    @notice
    USDC address on Uniswap 
  */
  address public immutable usdcAddress;

  /** 
    @notice
    The controller with which new projects should be deployed. 
  */
  IJBController public immutable override controller;

  /** 
    @notice
    The contract responsible for deploying the delegate.
  */
  IBluntDelegateDeployer public immutable override delegateDeployer;

  /** 
    @notice
    The contract responsible for deploying the delegate as immutable clones.
  */
  IBluntDelegateCloner public immutable override delegateCloner;

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  constructor(
    IBluntDelegateDeployer _delegateDeployer,
    IBluntDelegateCloner _delegateCloner,
    IJBController _controller,
    IJBOperatorStore _operatorStore,
    address _ethAddress,
    address _usdcAddress
  ) JBOperatable(_operatorStore) {
    delegateDeployer = _delegateDeployer;
    delegateCloner = _delegateCloner;
    controller = _controller;
    ethAddress = _ethAddress;
    usdcAddress = _usdcAddress;
  }

  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /** 
    @notice 
    Launches a new project with a blunt round data source attached.

    @param _deployBluntDelegateData Data necessary to fulfill the transaction to deploy a blunt round data source.
    @param _launchProjectData Data necessary to fulfill the transaction to launch a project.
    @param _clone True if BluntDelegate is to be an immutable clone

    @return projectId The ID of the newly configured project.
  */
  function launchProjectFor(
    DeployBluntDelegateData memory _deployBluntDelegateData,
    JBLaunchProjectData memory _launchProjectData,
    bool _clone
  ) external override returns (uint256 projectId) {
    // Get the project ID, optimistically knowing it will be one greater than the current count.
    projectId = controller.projects().count() + 1;
    address _delegateAddress;
    if (_clone) {
      // Deploy the data source contract as immutable clone
      _delegateAddress = delegateCloner.deployDelegateFor(
        controller,
        projectId,
        _launchProjectData.data.duration,
        ethAddress,
        usdcAddress,
        _deployBluntDelegateData
      );
    } else {
      // Deploy the data source contract.
      _delegateAddress = delegateDeployer.deployDelegateFor(
        controller,
        projectId,
        _launchProjectData.data.duration,
        ethAddress,
        usdcAddress,
        _deployBluntDelegateData
      );
    }

    // Set the data source address as the data source of the provided metadata.
    _launchProjectData.metadata.dataSource = _delegateAddress;
    // Set the project to use the data source for its pay and redeem functions.
    _launchProjectData.metadata.useDataSourceForPay = true;
    _launchProjectData.metadata.useDataSourceForRedeem = true;
    // Enable full redemptions
    _launchProjectData.metadata.redemptionRate = JBConstants.MAX_REDEMPTION_RATE;
    // Disable token transfers
    _launchProjectData.metadata.global.pauseTransfers = true;

    // Require weight to be non zero to allow for redemptions, and a multiple of `TOKENS_PER_ETH`
    if (_launchProjectData.data.weight == 0 || _launchProjectData.data.weight % TOKENS_PER_ETH != 0)
      revert INVALID_TOKEN_ISSUANCE();

    // Launch the project.
    _launchProjectFor(_delegateAddress, _launchProjectData);
  }

  //*********************************************************************//
  // ------------------------ internal functions ----------------------- //
  //*********************************************************************//

  /** 
    @notice
    Launches a project.

    @param _owner The address to set as the owner of the project. The project ERC-721 will be owned by this address.
    @param _launchProjectData Data necessary to fulfill the transaction to launch the project.
  */
  function _launchProjectFor(
    address _owner,
    JBLaunchProjectData memory _launchProjectData
  ) internal {
    controller.launchProjectFor(
      _owner,
      _launchProjectData.projectMetadata,
      _launchProjectData.data,
      _launchProjectData.metadata,
      _launchProjectData.mustStartAtOrAfter,
      _launchProjectData.groupedSplits,
      _launchProjectData.fundAccessConstraints,
      _launchProjectData.terminals,
      _launchProjectData.memo
    );
  }
}
