// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './interfaces/IBluntDelegateClone.sol';
import './interfaces/IPriceFeed.sol';
import '@openzeppelin-upgradeable/proxy/utils/Initializable.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutTerminal.sol';

/// @title Base Blunt Finance data source for Juicebox projects.
/// @author jacopo <jacopo@slice.so>
/// @notice Permissionless funding rounds with target, hardcap, deadline and a set of pre-defined rules.
contract BluntDelegateClone is IBluntDelegateClone, Initializable {
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//
  error INVALID_PAYMENT_EVENT();
  error CAP_REACHED();
  error ROUND_ENDED();
  error ROUND_NOT_ENDED();
  error ROUND_CLOSED();
  error ROUND_NOT_CLOSED();
  error NOT_PROJECT_OWNER();

  //*********************************************************************//
  // ------------------------------ events ----------------------------- //
  //*********************************************************************//
  event RoundCreated(
    DeployBluntDelegateData deployBluntDelegateData,
    uint256 projectId,
    uint256 duration
  );
  event RoundClosed();

  //*********************************************************************//
  // ------------------------ immutable storage ------------------------ //
  //*********************************************************************//

  /** 
    @notice 
    The ETH token address in Juicebox
  */
  address private constant ETH = address(0x000000000000000000000000000000000000EEEe);

  /**
    @notice
    Price feed instance
  */
  IPriceFeed private constant priceFeed = IPriceFeed(0xf2E8176c0b67232b20205f4dfbCeC3e74bca471F);

  /**
    @notice
    The directory of terminals and controllers for projects.
  */
  IJBDirectory private directory;

  IJBController private controller;

  /**
    @notice
    The ID of the Blunt Finance project.
  */
  uint48 public bluntProjectId;

  /**
    @notice
    The ID of the project.
  */
  uint48 public projectId;

  /**
    @notice
    Constants used to calculate Blunt Finance fee
  */
  uint16 public MAX_K;
  uint16 public MIN_K;
  uint56 public UPPER_FUNDRAISE_BOUNDARY_USD;
  uint56 public LOWER_FUNDRAISE_BOUNDARY_USD;

  /**
    @notice
    WETH address on Uniswap
  */
  address private ethAddress;

  /**
    @notice
    USDC address on Uniswap
  */
  address private usdcAddress;

  /** 
    @notice
    The owner of the project once the blunt round is concluded successfully.
  */
  address private projectOwner;

  /** 
    @notice
    The minimum amount of contributions while this data source is in effect.
    When `isTargetUsd` is enabled, it is a 6 point decimal number.
    @dev uint88 is sufficient as it cannot be higher than `MAX_CONTRIBUTION`
  */
  uint88 private target;

  /** 
    @notice
    The maximum amount of contributions while this data source is in effect. 
    When `isHardcapUsd` is enabled, it is a 6 point decimal number.
    @dev uint88 is sufficient as it cannot be higher than `MAX_CONTRIBUTION`
  */
  uint88 private hardcap;

  /** 
    @notice
    Reserved rate to be set in case of a successful round
  */
  uint16 private afterRoundReservedRate;

  /**
    @notice
    Deadline of the round
  */
  uint40 private deadline;

  /**
    @notice
    True if a target is expressed in USD
  */
  bool private isTargetUsd;

  /**
    @notice
    True if a hardcap is expressed in USD
  */
  bool private isHardcapUsd;

  //*********************************************************************//
  // ------------------------- mutable storage ------------------------- //
  //*********************************************************************//

  /**
    @notice
    Total contributions received during round
    @dev uint88 is sufficient as it cannot be higher than `MAX_CONTRIBUTION`
  */
  uint248 private totalContributions;

  /**
    @notice
    True if the round has been closed 
  */
  bool private isRoundClosed;

  /** 
    @notice
    Project metadata splits to be enabled when a successful round is closed.
  */
  JBSplit[] private afterRoundSplits;

  /**
    @notice
    Mapping from beneficiary to contributions
  */
  mapping(address => uint256) public contributions;

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  /**
   * @dev Constructor to prevent initializing implementation
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  //*********************************************************************//
  // -------------------------- initializer ---------------------------- //
  //*********************************************************************//

  /**
    @notice Initializes the contract as immutable clone.

    @param _deployBluntDelegateDeployerData Deployment data sent by deployer contract
    @param _deployBluntDelegateData Deployment data sent by user
  */
  function initialize(
    DeployBluntDelegateDeployerData memory _deployBluntDelegateDeployerData,
    DeployBluntDelegateData memory _deployBluntDelegateData
  ) external override initializer {
    MAX_K = _deployBluntDelegateDeployerData.maxK;
    MIN_K = _deployBluntDelegateDeployerData.minK;
    UPPER_FUNDRAISE_BOUNDARY_USD = _deployBluntDelegateDeployerData.upperFundraiseBoundary;
    LOWER_FUNDRAISE_BOUNDARY_USD = _deployBluntDelegateDeployerData.lowerFundraiseBoundary;
    bluntProjectId = _deployBluntDelegateDeployerData.bluntProjectId;
    projectId = _deployBluntDelegateDeployerData.projectId;
    ethAddress = _deployBluntDelegateDeployerData.ethAddress;
    usdcAddress = _deployBluntDelegateDeployerData.usdcAddress;
    controller = _deployBluntDelegateDeployerData.controller;

    directory = _deployBluntDelegateData.directory;
    projectOwner = _deployBluntDelegateData.projectOwner;
    afterRoundReservedRate = _deployBluntDelegateData.afterRoundReservedRate;
    target = _deployBluntDelegateData.target;
    isTargetUsd = _deployBluntDelegateData.isTargetUsd;
    hardcap = _deployBluntDelegateData.hardcap;
    isHardcapUsd = _deployBluntDelegateData.isHardcapUsd;

    /// Set deadline based on round duration
    deadline = _deployBluntDelegateDeployerData.duration == 0
      ? 0
      : uint40(block.timestamp + _deployBluntDelegateDeployerData.duration);

    /// Store afterRoundSplits
    for (uint256 i; i < _deployBluntDelegateData.afterRoundSplits.length; ) {
      afterRoundSplits.push(_deployBluntDelegateData.afterRoundSplits[i]);

      unchecked {
        ++i;
      }
    }

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
    /// - The blunt round hasn't been closed
    if (
      !directory.isTerminalOf(projectId, IJBPaymentTerminal(msg.sender)) ||
      _data.projectId != projectId ||
      isRoundClosed
    ) revert INVALID_PAYMENT_EVENT();

    /// Require that the funding cycle related to the round hasn't ended
    if (deadline != 0 && block.timestamp > deadline) revert ROUND_ENDED();

    /// Update totalContributions and contributions with amount paid
    if (_data.amount.value > type(uint248).max) revert CAP_REACHED();
    totalContributions += uint248(_data.amount.value);

    /// Revert if `totalContributions` exceeds `hardcap`
    _hardcapCheck();

    /// Cannot overflow as totalContributions would overflow first
    unchecked {
      contributions[_data.beneficiary] += _data.amount.value;
    }
  }

  /**
    @notice 
    Part of IJBRedemptionDelegate, this function gets called when the beneficiary redeems tokens. 
    It will update storage if conditions are met. 

    @dev 
    This function will revert if the contract calling is not one of the project's terminals. 

    @param _data The Juicebox standard project payment data.
  */
  function didRedeem(JBDidRedeemData calldata _data) external payable virtual override {
    /// Require that
    /// - The caller is a terminal of the project
    /// - The call is being made on behalf of an interaction with the correct project
    if (
      !directory.isTerminalOf(projectId, IJBPaymentTerminal(msg.sender)) ||
      _data.projectId != projectId
    ) revert INVALID_PAYMENT_EVENT();

    unchecked {
      /// Decrease contributions based on amount redeemed
      /// @dev Cannot underflow as `_data.reclaimedAmount.value` cannot be higher than `contributions[_data.beneficiary]`
      /// contributions can be inside unchecked as token transfers are disabled during round
      contributions[_data.beneficiary] -= _data.reclaimedAmount.value;

      // Only if round is open
      if (!isRoundClosed) {
        /// Decrease totalContributions by amount redeemed
        totalContributions -= uint248(_data.reclaimedAmount.value);
      }
    }
  }

  /**
    @notice 
    Close blunt round if target has been reached:
    - Pay BF fee, 
    - Reconfigure next FC,
    - Transfer project NFT to projectOwner.
    If called when totalContributions hasn't reached the target, disables payments and keeps full redemptions enabled.

    @dev 
    Can only be called once by the appointed project owner.
  */
  function closeRound() external override {
    if (msg.sender != projectOwner) revert NOT_PROJECT_OWNER();
    if (isRoundClosed) revert ROUND_CLOSED();
    isRoundClosed = true;

    if (isTargetReached()) {
      // Prevent successful rounds to be closed before the deadline
      if (deadline != 0 && block.timestamp < deadline) revert ROUND_NOT_ENDED();

      (
        address jbEthTerminalAddress,
        uint256 bluntFee,
        JBFundingCycleData memory data,
        JBFundingCycleMetadata memory metadata,
        JBGroupedSplits[] memory splits,
        JBFundAccessConstraints[] memory fundAccessConstraints
      ) = _formatReconfigData();

      /// Reconfigure Funding Cycle
      controller.reconfigureFundingCyclesOf(
        projectId,
        data,
        metadata,
        0,
        splits,
        fundAccessConstraints,
        'Blunt round completed'
      );

      // Distribute payout fee to Blunt Finance
      string memory projectIdString = _toString(projectId);
      IJBPayoutTerminal(jbEthTerminalAddress).distributePayoutsOf({
        _projectId: projectId,
        _amount: bluntFee,
        _currency: 1,
        _token: ETH,
        _minReturnedTokens: 0,
        _memo: string(
          abi.encodePacked(
            'Fee from [Project #',
            projectIdString,
            '](https://juicebox.money/v2/p/',
            projectIdString,
            ')'
          )
        )
      });

      /// Transfer project ownership to projectOwner
      directory.projects().safeTransferFrom(address(this), projectOwner, projectId);
    }

    emit RoundClosed();
  }

  //*********************************************************************//
  // ------------------------- external views -------------------------- //
  //*********************************************************************//

  /**
    @notice 
    Part of IJBFundingCycleDataSource, this function gets called when the project receives a payment. It will set itself as the delegate to get a callback from the terminal.

    @dev 
    This function will revert if the contract calling it is not the store of one of the project's terminals. 

    @param _data The Juicebox standard project payment data.

    @return weight The weight that tokens should get minted in accordance to 
    @return memo The memo that should be forwarded to the event.
    @return delegateAllocations The amount to send to delegates instead of adding to the local balance.
  */
  function payParams(
    JBPayParamsData calldata _data
  )
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
    Part of IJBFundingCycleDataSource, this function gets called when a project's token holders redeem. It will return the standard properties.

    @param _data The Juicebox standard project redemption data.

    @return reclaimAmount The amount that should be reclaimed from the treasury.
    @return memo The memo that should be forwarded to the event.
    @return delegateAllocations The amount to send to delegates instead of adding to the beneficiary.
  */
  function redeemParams(
    JBRedeemParamsData calldata _data
  )
    external
    view
    override
    returns (
      uint256 reclaimAmount,
      string memory memo,
      JBRedemptionDelegateAllocation[] memory delegateAllocations
    )
  {
    JBRedemptionDelegateAllocation[] memory allocations = new JBRedemptionDelegateAllocation[](1);
    allocations[0] = JBRedemptionDelegateAllocation(IJBRedemptionDelegate(address(this)), 0);

    /// Forward the recieved weight and memo, and use this contract as a redeem delegate.
    return (_data.reclaimAmount.value, _data.memo, allocations);
  }

  /**
    @notice
    Returns info related to round.
  */
  function getRoundInfo() external view override returns (RoundInfo memory roundInfo) {
    roundInfo = RoundInfo(
      totalContributions,
      target,
      hardcap,
      projectOwner,
      afterRoundReservedRate,
      afterRoundSplits,
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
    uint256 target_ = target;
    if (target_ != 0) {
      if (isTargetUsd) {
        target_ = priceFeed.getQuote(uint128(target_), usdcAddress, ethAddress, 30 minutes);
      }
    }
    return totalContributions > target_;
  }

  //*********************************************************************//
  // ----------------------- private functions ------------------------- //
  //*********************************************************************//

  /**
    @notice
    Revert if total contributions received surpass the round hardcap.
    Used in `didPay`
  */
  function _hardcapCheck() private view {
    uint256 hardcap_ = hardcap;

    if (hardcap_ != 0) {
      if (isHardcapUsd) {
        hardcap_ = priceFeed.getQuote(uint128(hardcap_), usdcAddress, ethAddress, 30 minutes);
      }
      if (totalContributions > hardcap_) revert CAP_REACHED();
    }
  }

  /**
    @notice
    Format data to reconfig project and pay Blunt Finance fee
  */
  function _formatReconfigData()
    private
    view
    returns (
      address jbEthTerminalAddress,
      uint256 bluntFee,
      JBFundingCycleData memory data,
      JBFundingCycleMetadata memory metadata,
      JBGroupedSplits[] memory splits,
      JBFundAccessConstraints[] memory fundAccessConstraints
    )
  {
    /// Set funding cycle data
    data = JBFundingCycleData({
      duration: 0,
      weight: 1e24, /// token issuance 1M
      discountRate: 0,
      ballot: IJBFundingCycleBallot(address(0))
    });

    /// Edit funding cycle metadata:
    /// Get current funding cycle metadata
    (, metadata) = controller.currentFundingCycleOf(projectId);
    /// Set reservedRate from `afterRoundReservedRate`
    metadata.reservedRate = afterRoundReservedRate; // TODO: Make this optional
    /// Disable redemptions
    metadata.pauseRedeem = true;
    delete metadata.redemptionRate;
    /// Enable transfers
    delete metadata.global.pauseTransfers;
    /// Pause pay, to allow projectOwner to reconfig as needed before re-enabling
    metadata.pausePay = true;
    /// Ensure distributions are enabled
    metadata.pauseDistributions = false;
    /// Detach dataSource
    delete metadata.useDataSourceForPay;
    delete metadata.useDataSourceForRedeem;
    delete metadata.dataSource;

    // Calculate BF fee
    bluntFee = _calculateFee(totalContributions);

    /// Format bluntSplits
    JBSplit[] memory bluntSplits = new JBSplit[](1);
    bluntSplits[0] = JBSplit({
      preferClaimed: false,
      preferAddToBalance: false,
      percent: 1_000_000_000,
      projectId: bluntProjectId,
      beneficiary: payable(projectOwner),
      lockedUntil: 0,
      allocator: IJBSplitAllocator(address(0))
    });

    // Format splits
    splits = new JBGroupedSplits[](2);
    splits[0] = JBGroupedSplits(1, bluntSplits); // Payout distribution
    // TODO: Make this optional
    splits[1] = JBGroupedSplits(2, afterRoundSplits); // Reserved rate

    // Get JB ETH terminal
    IJBPaymentTerminal jbEthTerminal = directory.primaryTerminalOf(projectId, ETH);
    jbEthTerminalAddress = address(jbEthTerminal);

    // Format fundAccessConstraints
    fundAccessConstraints = new JBFundAccessConstraints[](1);
    fundAccessConstraints[0] = JBFundAccessConstraints({
      terminal: jbEthTerminal,
      token: ETH,
      distributionLimit: bluntFee,
      distributionLimitCurrency: 1,
      overflowAllowance: 0,
      overflowAllowanceCurrency: 0
    });
  }

  /**
    @notice
    Calculate fee for successful rounds. Used in `_formatReconfigData`
  */
  function _calculateFee(uint256 raised) private view returns (uint256 fee) {
    unchecked {
      uint256 raisedUsd = priceFeed.getQuote(uint128(raised), ethAddress, usdcAddress, 30 minutes);
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

  /**
   * @dev Converts a uint256 to its ASCII string decimal representation.
   */
  function _toString(uint256 value) internal pure virtual returns (string memory str) {
    assembly {
      // The maximum value of a uint256 contains 78 digits (1 byte per digit), but
      // we allocate 0xa0 bytes to keep the free memory pointer 32-byte word aligned.
      // We will need 1 word for the trailing zeros padding, 1 word for the length,
      // and 3 words for a maximum of 78 digits. Total: 5 * 0x20 = 0xa0.
      let m := add(mload(0x40), 0xa0)
      // Update the free memory pointer to allocate.
      mstore(0x40, m)
      // Assign the `str` to the end.
      str := sub(m, 0x20)
      // Zeroize the slot after the string.
      mstore(str, 0)

      // Cache the end of the memory to calculate the length later.
      let end := str

      // We write the string from rightmost digit to leftmost digit.
      // The following is essentially a do-while loop that also handles the zero case.
      // prettier-ignore
      for { let temp := value } 1 {} {
                str := sub(str, 1)
                // Write the character to the pointer.
                // The ASCII index of the '0' character is 48.
                mstore8(str, add(48, mod(temp, 10)))
                // Keep dividing `temp` until zero.
                temp := div(temp, 10)
                // prettier-ignore
                if iszero(temp) { break }
            }

      let length := sub(end, str)
      // Move the pointer 32 bytes leftwards to make room for the length.
      str := sub(str, 0x20)
      // Store the length.
      mstore(str, length)
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
      _interfaceId == type(IJBFundingCycleDataSource).interfaceId ||
      _interfaceId == type(IJBPayDelegate).interfaceId;
  }
}
