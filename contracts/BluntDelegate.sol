// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './interfaces/IBluntDelegate.sol';
import '@paulrberg/contracts/math/PRBMath.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutTerminal.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutRedemptionPaymentTerminal.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPrices.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBCurrencies.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBConstants.sol';

/// @title Base Blunt Finance data source for Juicebox projects.
/// @author jacopo <jacopo@slice.so>
/// @author jango
/// @notice Permissionless funding rounds with target, hardcap, deadline and a set of pre-defined rules.
contract BluntDelegate is IBluntDelegate {
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//

  error INVALID_PAYMENT_EVENT();
  error CAP_REACHED();
  error ROUND_ENDED();
  error ROUND_NOT_ENDED();
  error ROUND_CLOSED();
  error DEADLINE_SET();
  error INVALID_DEADLINE();
  error NOT_PROJECT_OWNER();
  error TARGET_NOT_REACHED();

  //*********************************************************************//
  // ------------------------------ events ----------------------------- //
  //*********************************************************************//

  event RoundCreated(
    DeployBluntDelegateData deployBluntDelegateData,
    uint256 projectId,
    uint256 duration
  );
  event RoundClosed();
  event DeadlineSet(uint256 deadline);

  //*********************************************************************//
  // ------------------------ immutable storage ------------------------ //
  //*********************************************************************//

  /**
    @notice
    The directory of terminals and controllers for projects.
  */
  IJBDirectory private immutable directory;

  /**
    @notice
    The controller with which new projects should be deployed.
  */
  IJBController private immutable controller;

  /**
    @notice
    The contract that exposes price feeds.
  */
  IJBPrices public immutable override prices;

  /**
    @notice
    The ID of the JB project that collects fees.
  */
  uint256 public immutable feeProjectId;

  /**
    @notice
    The ID of the project conducting a round.
  */
  uint256 public immutable projectId;

  /**
    @notice
    Constants used to calculate fee.

    TODO: describe these plz jacopo.
  */
  uint256 public immutable MAX_K;
  uint256 public immutable MIN_K;
  uint256 public immutable UPPER_FUNDRAISE_BOUNDARY_USD;
  uint256 public immutable LOWER_FUNDRAISE_BOUNDARY_USD;

  /** 
    @notice
    The owner of the project if the round is concluded successfully.
  */
  address private immutable projectOwner;

  /** 
    @notice
    The minimum amount of contributions to deem the round successful. Fixed point number using the same amount of decimals as the payment terminal being used.
  */
  uint256 private immutable target;

  /** 
    @notice
    The maximum amount of contributions possible while the round is in effect. Fixed point number using the same amount of decimals as the payment terminal being used.
  */
  uint256 private immutable hardcap;

  /** 
    @notice
    True if the target is expressed in USD. False if ETH.
  */
  bool private immutable isTargetUsd;

  /** 
    @notice
    True if the hardcap is expressed in USD. False if ETH.
  */
  bool private immutable isHardcapUsd;

  //*********************************************************************//
  // ------------------------- mutable storage ------------------------- //
  //*********************************************************************//

  /**
    @notice
    The timestamp after which the round can be closed. If zero, the round can be closed anytime after the target is met.
  */
  uint40 private deadline;

  /**
    @notice
    If the round has been closed.
  */
  bool private isRoundClosed;

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  /**
    @param _deployBluntDelegateDeployerData Deployment data sent by deployer contract
    @param _deployBluntDelegateData Deployment data sent by user
  */
  constructor(
    DeployBluntDelegateDeployerData memory _deployBluntDelegateDeployerData,
    DeployBluntDelegateData memory _deployBluntDelegateData
  ) {
    feeProjectId = _deployBluntDelegateDeployerData.feeProjectId;
    directory = _deployBluntDelegateDeployerData.directory;
    controller = _deployBluntDelegateDeployerData.controller;
    prices = _deployBluntDelegateDeployerData.prices;
    MAX_K = _deployBluntDelegateDeployerData.maxK;
    MIN_K = _deployBluntDelegateDeployerData.minK;
    UPPER_FUNDRAISE_BOUNDARY_USD = _deployBluntDelegateDeployerData.upperFundraiseBoundary;
    LOWER_FUNDRAISE_BOUNDARY_USD = _deployBluntDelegateDeployerData.lowerFundraiseBoundary;

    projectId = _deployBluntDelegateData.projectId;
    projectOwner = _deployBluntDelegateData.projectOwner;
    target = _deployBluntDelegateData.target;
    isTargetUsd = _deployBluntDelegateData.isTargetUsd;
    hardcap = _deployBluntDelegateData.hardcap;
    isHardcapUsd = _deployBluntDelegateData.isHardcapUsd;

    /// Set deadline based on round duration
    if (_deployBluntDelegateDeployerData.duration != 0)
      deadline = uint40(block.timestamp + _deployBluntDelegateData.duration);

    emit RoundCreated(
      _deployBluntDelegateData,
      _deployBluntDelegateDeployerData.projectId,
      _deployBluntDelegateDeployerData.duration
    );
  }

  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /**
    @notice 
    Part of IJBPayDelegate, this function gets called when the project receives a payment. 
    It checks if blunt round hasn't been closed and hasn't reached the deadline.

    @dev 
    This function will revert if the contract calling is not one of the project's terminals. 

    @param _data The Juicebox standard project payment data.
  */
  function didPay(JBDidPayData calldata _data) external payable virtual override {
    /// Require that
    /// - The caller is a terminal of the project
    /// - The call is being made on behalf of an interaction with the correct project
    if (
      !directory.isTerminalOf(projectId, IJBPaymentTerminal(msg.sender)) ||
      _data.projectId != projectId
    ) revert INVALID_PAYMENT_EVENT();

    /// Make sure the round hasn't ended.
    if (isRoundClosed || (deadline != 0 && block.timestamp > deadline)) revert ROUND_ENDED();

    /// Get a reference to the terminal.
    IJBPayoutRedemptionPaymentTerminal _terminal = IJBPayoutRedemptionPaymentTerminal(msg.sender);

    /// Make sure the hardhat hasn't been reached.
    if (hardcap != 0) {
      if (isHardcapUsd) {
        // Convert the hardcap to ETH.
        hardcap = PRBMath.muldiv(
          hardcap,
          _terminal.decimals,
          prices.priceFor(JBCurrencies.USD, JBCurrencies.ETH, _terminal.decimals)
        );
      }
      if (_terminal.store().balanceOf(msg.sender, _data.projectId) > hardcap) revert CAP_REACHED();
    }
  }

  /**
    @notice 
    Close round if target has been reached.

    @dev 
    Can only be called once.
  */
  function closeRound() external override {
    /// Make sure the round isn't already closed.
    if (isRoundClosed) revert ROUND_CLOSED();

    // Make sure the deadline has passed if one was set.
    if (deadline != 0 && block.timestamp < deadline) revert ROUND_NOT_ENDED();

    // Make sure the target has been reached.
    if (!isTargetReached()) revert TARGET_NOT_REACHED();

    /// Get reconfigure data.
    (
      IJBPayoutTerminal payoutTerminal,
      uint256 fee,
      JBFundingCycleData memory data,
      JBFundingCycleMetadata memory metadata,
      JBGroupedSplits[] memory splits,
      JBFundAccessConstraints[] memory fundAccessConstraints
    ) = _formatReconfigData();

    /// Reconfigure the funding cycle.
    controller.reconfigureFundingCyclesOf(
      projectId,
      data,
      metadata,
      0,
      splits,
      fundAccessConstraints,
      'Blunt round completed'
    );

    // Distribute payout fee to the fee project.
    payoutTerminal.distributePayoutsOf({
      _projectId: projectId,
      _amount: fee,
      _currency: JBCurrencies.ETH,
      _token: JBTokens.ETH,
      _minReturnedTokens: 0,
      _memo: ''
    });

    /// Transfer project ownership to projectOwner
    directory.projects().safeTransferFrom(address(this), projectOwner, projectId);

    /// Set the round as closed.
    isRoundClosed = true;

    emit RoundClosed();
  }

  /**
    @notice 
    Set a deadline for rounds with no duration set.

    @param deadline_ The new deadline for the round.

    @dev 
    Can only be called once by the appointed project owner.
  */
  function setDeadline(uint256 deadline_) external override {
    /// Make sure the appointed project owner is making the change.
    if (msg.sender != projectOwner) revert NOT_PROJECT_OWNER();

    /// Make sure the round isn't closed.
    if (isRoundClosed) revert ROUND_CLOSED();

    /// Make sure the deadline isn't already set.
    if (deadline != 0) revert DEADLINE_SET();

    /// Make sure the deadline being set is in the future.
    if (uint40(deadline_) < block.timestamp) revert INVALID_DEADLINE();

    /// Set the deadline.
    deadline = uint40(deadline_);

    emit DeadlineSet(deadline_);
  }

  //*********************************************************************//
  // ------------------------- external views -------------------------- //
  //*********************************************************************//

  /**
    @notice 
    Part of IJBFundingCycleDataSource, this function gets called when the project receives a payment. It will set itself as the delegate to get a callback from the terminal.

    @param _data The Juicebox standard project payment data.

    @return weight The weight that tokens should get minted in accordance with. 
    @return memo The memo that should be forwarded to the event.
    @return delegateAllocations The amount to send to delegates instead of adding to the local balance.
  */
  function payParams(JBPayParamsData calldata _data)
    external
    view
    override
    returns (
      uint256 weight,
      string memory memo,
      JBPayDelegateAllocation[] memory delegateAllocations
    )
  {
    JBPayDelegateAllocation[] memory allocations = new JBPayDelegateAllocation[](1);
    allocations[0] = JBPayDelegateAllocation(IJBPayDelegate(address(this)), 0);

    /// Forward the recieved weight and memo, and use this contract as a pay delegate.
    return (_data.weight, _data.memo, allocations);
  }

  /**
    @notice
    Returns info related to the round.
  */
  function getRoundInfo() external view override returns (RoundInfo memory) {
    /// Get a reference to the terminal.
    IJBPaymentTerminal _terminal = directory.primaryTerminalOf(projectId, JBTokens.ETH);

    return
      RoundInfo(
        IJBPayoutRedemptionPaymentTerminal(_terminal).store().balanceOf(_terminal, projectId),
        target,
        hardcap,
        projectOwner,
        isRoundClosed,
        deadline,
        isTargetUsd,
        isHardcapUsd
      );
  }

  /**
    @notice
    Returns true if total contributions received surpass the round target.
  */
  function isTargetReached() public view override returns (bool) {
    /// Get a reference to the terminal.
    IJBPaymentTerminal _terminal = directory.primaryTerminalOf(projectId, JBTokens.ETH);

    uint256 target_ = target;
    if (target_ != 0) {
      if (isTargetUsd) {
        target_ = PRBMath.muldiv(
          target_,
          _terminal.decimals,
          prices.priceFor(JBCurrencies.USD, JBCurrencies.ETH, _terminal.decimals)
        );
      }
    }
    return
      IJBPayoutRedemptionPaymentTerminal(_terminal).store().balanceOf(_terminal, projectId) >
      target_;
  }

  //*********************************************************************//
  // ----------------------- private functions ------------------------- //
  //*********************************************************************//

  /**
    @notice
    Format data to reconfig project and pay Blunt Finance fee
  */
  function _formatReconfigData()
    private
    view
    returns (
      IJBPayoutTerminal terminal,
      uint256 fee,
      JBFundingCycleData memory data,
      JBFundingCycleMetadata memory metadata,
      JBGroupedSplits[] memory splits,
      JBFundAccessConstraints[] memory fundAccessConstraints
    )
  {
    /// Set funding cycle data
    data = JBFundingCycleData({
      duration: 0,
      weight: 0, /// Inherit from funding cycle 1.
      discountRate: 0,
      ballot: IJBFundingCycleBallot(address(0))
    });

    /// Get current funding cycle metadata
    (, metadata) = controller.currentFundingCycleOf(projectId);

    /// Remove redemption rates.
    delete metadata.redemptionRate;
    delete metadata.ballotRedemptionRate;

    /// Pause pay to allow projectOwner to reconfig as needed before re-enabling.
    metadata.pausePay = true;

    /// Detach data source.
    delete metadata.useDataSourceForPay;
    delete metadata.dataSource;

    // Get project's ETH terminal.
    terminal = IJBPayoutRedemptionPaymentTerminal(
      directory.primaryTerminalOf(projectId, JBTokens.ETH)
    );

    // Calculate the fee to take.
    fee = _calculateFee(terminal.store().balanceOf(terminal, projectId), terminal.decimals());

    /// Format fee split.
    JBSplit[] memory feeSplits = new JBSplit[](1);
    feeSplits[0] = JBSplit({
      preferClaimed: false,
      preferAddToBalance: false,
      percent: JBConstants.SPLITS_TOTAL_PERCENT,
      projectId: feeProjectId,
      beneficiary: payable(projectOwner),
      lockedUntil: 0,
      allocator: IJBSplitAllocator(address(0))
    });

    // Format split groups.
    splits = new JBGroupedSplits[](1);
    splits[0] = JBGroupedSplits(1, feeSplits); // Payout distribution

    // Format the fund access constraints.
    fundAccessConstraints = new JBFundAccessConstraints[](1);
    fundAccessConstraints[0] = JBFundAccessConstraints({
      terminal: terminal,
      token: JBTokens.ETH,
      distributionLimit: fee,
      distributionLimitCurrency: JBCurrencies.ETH,
      overflowAllowance: 0,
      overflowAllowanceCurrency: 0
    });
  }

  /**
    @notice
    Calculate fee for successful rounds. Used in `_formatReconfigData`
  */
  function _calculateFee(uint256 raised, uint256 decimals) private view returns (uint256 fee) {
    unchecked {
      uint256 raisedUsd = PRBMath.muldiv(
        raised,
        prices.priceFor(JBCurrencies.USD, JBCurrencies.ETH, decimals),
        decimals
      );

      uint256 k;
      if (raisedUsd < LOWER_FUNDRAISE_BOUNDARY_USD) {
        k = MAX_K;
      } else if (raisedUsd > UPPER_FUNDRAISE_BOUNDARY_USD) {
        k = MIN_K;
      } else {
        /** @dev 
          - [(MAX_K - MIN_K) * (raisedUsd - LOWER_FUNDRAISE_BOUNDARY_USD)] cannot overflow since raisedUsd < UPPER_FUNDRAISE_BOUNDARY_USD
          - k cannot underflow since MAX_K > (MAX_K - MIN_K)
        */
        // prettier-ignore
        k = MAX_K - (
          ((MAX_K - MIN_K) * (raisedUsd - LOWER_FUNDRAISE_BOUNDARY_USD)) /
          (UPPER_FUNDRAISE_BOUNDARY_USD - LOWER_FUNDRAISE_BOUNDARY_USD)
        );
      }

      /// @dev overflows for [raised > 2^256 / MIN_K], which practically cannot be reached
      fee = (k * raised) / 10000;
    }
  }

  //*********************************************************************//
  // ------------------------ hooks and others ------------------------- //
  //*********************************************************************//

  /**
   * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
   * by `operator` from `from`, this function is called.
   *
   * It must return its Solidity selector to confirm the token transfer.
   * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
   *
   * The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
   */
  function onERC721Received(
    address,
    address,
    uint256,
    bytes calldata
  ) external pure override returns (bytes4) {
    return this.onERC721Received.selector;
  }

  /**
    @notice
    Indicates if this contract adheres to the specified interface.

    @dev
    See {IERC165-supportsInterface}.

    @param _interfaceId The ID of the interface to check for adherance to.
  */
  function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
    return
      _interfaceId == type(IERC165).interfaceId ||
      _interfaceId == type(IJBFundingCycleDataSource).interfaceId ||
      _interfaceId == type(IJBPayDelegate).interfaceId ||
      _interfaceId == type(IJBRedemptionDelegate).interfaceId;
  }
}
