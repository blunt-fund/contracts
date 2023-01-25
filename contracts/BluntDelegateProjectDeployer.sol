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
    The ID of the Blunt Finance project.
  */
  uint256 public immutable feeProjectId;

  /** 
    @notice
    JB directory address
  */
  IJBDirectory public immutable override directory;

  /** 
    @notice
    JB controller address
  */
  IJBController public immutable override controller;

  /** 
    @notice
    JB prices address
  */
  IJBPrices public immutable override prices;

  //*********************************************************************//
  // ------------------------ mutable storage -------------------------- //
  //*********************************************************************//

  /**
    @notice
    Parameters used to calculate Blunt Finance round fees
    @dev 
    uint56 is enough as allows for boundaries of up to 70B USD (7e16 with 6 decimals)
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
    address deployer,
    IBluntDelegateDeployer _delegateDeployer,
    IBluntDelegateCloner _delegateCloner,
    IJBDirectory _directory,
    IJBController _controller,
    IJBPrices _prices,
    IJBOperatorStore _operatorStore,
    uint256 _feeProjectId,
    uint16 _maxK,
    uint16 _minK,
    uint56 _upperFundraiseBoundary,
    uint56 _lowerFundraiseBoundary
  ) JBOperatable(_operatorStore) {
    // Override ownable's default owner due to CREATE3 deployment
    _transferOwnership(deployer);

    delegateDeployer = _delegateDeployer;
    delegateCloner = _delegateCloner;
    directory = _directory;
    controller = _controller;
    prices = _prices;
    feeProjectId = _feeProjectId;
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
    Launches a new project with a round data source attached.

    @param _deployBluntDelegateData Data necessary to fulfill the transaction to deploy a round data source.
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
      uint48(feeProjectId),
      uint48(projectId),
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
      // Deploy the data source contract as standard deployment.
      _delegateAddress = delegateDeployer.deployDelegateFor(
        _deployerData,
        _deployBluntDelegateData
      );
    }

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

    @param _delegate The address to set as the owner of the project. The project ERC-721 will be owned by this address.
    @param _launchProjectData Data necessary to fulfill the transaction to launch the project.
  */
  function _launchProjectFor(address _delegate, JBLaunchProjectData memory _launchProjectData)
    internal
  {
    controller.launchProjectFor(
      _delegate, // The delegate owns the project.
      _launchProjectData.projectMetadata,
      JBFundingCycleData ({
        duration: 0, 
        weight: 1000000E18, // 1m tokens per ETH contributed.
        discountRate: 0,
        ballot: IJBFundingCycleBallot(address(0))
      }),
      JBFundingCycleMetadata ({
        global: JBGlobalFundingCycleMetadata({
          allowSetTerminals: false,
          allowSetController: false,
          pauseTransfers: false
        }),
        reservedRate: 0,
        // Full refunds.
        redemptionRate: JBConstants.MAX_REDEMPTION_RATE,
        ballotRedemptionRate: JBConstants.MAX_REDEMPTION_RATE,
        pausePay: false,
        pauseDistributions: false,
        pauseRedeem: false,
        pauseBurn: false,
        allowMinting: false,
        allowTerminalMigration: false,
        allowControllerMigration: false,
        holdFees: false,
        preferClaimedTokenOverride: false,
        useTotalOverflowForRedemptions: false,
        useDataSourceForPay: true,
        useDataSourceForRedeem: false,
        dataSource: _delegate, // The delegate is the data source.
        metadata: 0 
      }),
      _launchProjectData.mustStartAtOrAfter,
      new JBGroupedSplits[](0),
      new JBFundAccessConstraints[](0),
      _launchProjectData.terminals,
      _launchProjectData.memo
    );
  }
}
