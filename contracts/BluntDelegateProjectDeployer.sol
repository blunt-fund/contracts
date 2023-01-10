// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@jbx-protocol/juice-contracts-v3/contracts/abstract/JBOperatable.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBConstants.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './interfaces/IBluntDelegateProjectDeployer.sol';

contract BluntDelegateProjectDeployer is IBluntDelegateProjectDeployer, JBOperatable, Ownable {
  //*********************************************************************//
  // ------------------------- custom errors --------------------------- //
  //*********************************************************************//
  error EXCEEDED_MAX_FEE();
  error INVALID_INPUTS();
  error INVALID_TOKEN_ISSUANCE();

  //*********************************************************************//
  // ----------------------- immutable storage ------------------------- //
  //*********************************************************************//

  /**
    @notice
    Ratio between amount of eth contributed and tokens minted
  */
  uint256 public constant TOKENS_PER_ETH = 1e15;

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
    The ID of the Blunt Finance project.
  */
  uint256 public immutable bluntProjectId;

  /** 
    @notice
    JB controller address
  */
  IJBController public immutable override controller;

  //*********************************************************************//
  // ------------------------ mutable storage -------------------------- //
  //*********************************************************************//

  /**
    @notice
    Parameters used to calculate Blunt Finance round fees
  */
  uint16 public maxK;
  uint16 public minK;
  uint56 public upperFundraiseBoundary;
  uint56 public lowerFundraiseBoundary;

  /** 
    @notice
    The contract responsible for deploying the delegate.
  */
  IBluntDelegateDeployer public override delegateDeployer;

  /** 
    @notice
    The contract responsible for deploying the delegate as immutable clones.
  */
  IBluntDelegateCloner public override delegateCloner;

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  constructor(
    IBluntDelegateDeployer _delegateDeployer,
    IBluntDelegateCloner _delegateCloner,
    IJBController _controller,
    IJBOperatorStore _operatorStore,
    uint256 _bluntProjectId,
    address _ethAddress,
    address _usdcAddress,
    uint16 _maxK,
    uint16 _minK,
    uint56 _upperFundraiseBoundary,
    uint56 _lowerFundraiseBoundary
  ) JBOperatable(_operatorStore) {
    delegateDeployer = _delegateDeployer;
    delegateCloner = _delegateCloner;
    controller = _controller;
    bluntProjectId = _bluntProjectId;
    ethAddress = _ethAddress;
    usdcAddress = _usdcAddress;
    maxK = _maxK;
    minK = _minK;
    upperFundraiseBoundary = _upperFundraiseBoundary;
    lowerFundraiseBoundary = _lowerFundraiseBoundary;
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

    DeployBluntDelegateDeployerData memory _deployerData = DeployBluntDelegateDeployerData(
      controller,
      bluntProjectId,
      projectId,
      _launchProjectData.data.duration,
      ethAddress,
      usdcAddress,
      maxK,
      minK,
      upperFundraiseBoundary,
      lowerFundraiseBoundary
    );

    address _delegateAddress;
    if (_clone) {
      // Deploy the data source contract as immutable clone
      _delegateAddress = delegateCloner.deployDelegateFor(_deployerData, _deployBluntDelegateData);
    } else {
      // Deploy the data source contract.
      _delegateAddress = delegateDeployer.deployDelegateFor(
        _deployerData,
        _deployBluntDelegateData
      );
    }

    _launchProjectData = _formatLaunchData(_launchProjectData, _delegateAddress);

    // Launch the project.
    _launchProjectFor(_delegateAddress, _launchProjectData);
  }

  /** 
    @notice
    Update delegate addresses. Can only be called by contract owner.

    @param newDelegateDeployer_ New delegateDeployer address
    @param newDelegateCloner_ new delegateCloner address
  */
  function _setDelegates(
    IBluntDelegateDeployer newDelegateDeployer_,
    IBluntDelegateCloner newDelegateCloner_
  ) external override onlyOwner {
    delegateDeployer = newDelegateDeployer_;
    delegateCloner = newDelegateCloner_;
  }

  /** 
    @notice
    Update blunt fees. Can only be called by contract owner.

    @param maxK_ Max K value for _calculateFee
    @param minK_ Min K value for _calculateFee
    @param upperFundraiseBoundary_ Upper foundraise boundary value for _calculateFee
    @param lowerFundraiseBoundary_ Lower foundraise boundary value for _calculateFee
  */
  function _setFees(
    uint16 maxK_,
    uint16 minK_,
    uint56 upperFundraiseBoundary_,
    uint56 lowerFundraiseBoundary_
  ) external override onlyOwner {
    if (maxK_ > 500) revert EXCEEDED_MAX_FEE();
    if (minK_ > maxK_ || lowerFundraiseBoundary_ > upperFundraiseBoundary_) revert INVALID_INPUTS();

    maxK = maxK_;
    minK = minK_;
    upperFundraiseBoundary = upperFundraiseBoundary_;
    lowerFundraiseBoundary = lowerFundraiseBoundary_;
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

  /** 
    @notice
    Format launch data for a project.

    @param launchData Data necessary to fulfill the transaction to launch the project.
    @param delegateAddress The address of the delegate contract.

    TODO: Check all settings necessary to guarantee round functionality are correctly defined here.
  */
  function _formatLaunchData(
    JBLaunchProjectData memory launchData,
    address delegateAddress
  ) private pure returns (JBLaunchProjectData memory) {
    // Require weight to be non zero to allow for redemptions, and a multiple of `TOKENS_PER_ETH`
    if (launchData.data.weight == 0 || launchData.data.weight % TOKENS_PER_ETH != 0)
      revert INVALID_TOKEN_ISSUANCE();

    // Set the data source address as the data source of the provided metadata.
    launchData.metadata.dataSource = delegateAddress;
    // Set the project to use the data source for its pay and redeem functions.
    launchData.metadata.useDataSourceForPay = true;
    launchData.metadata.useDataSourceForRedeem = true;
    // Enable full redemptions
    launchData.metadata.pauseRedeem = false;
    launchData.metadata.redemptionRate = JBConstants.MAX_REDEMPTION_RATE;
    // Disable token transfers
    launchData.metadata.global.pauseTransfers = true;
    // Enforce empty ballot
    launchData.data.ballot = IJBFundingCycleBallot(address(0));

    // Duration param is passed to the delegate contract to calculate the end time of the round,
    // and then set to 0 prior to launch project to avoid the need to queue a FC.
    launchData.data.duration = 0;

    return launchData;
  }
}
