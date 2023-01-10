// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './interfaces/ISliceCore.sol';
import './interfaces/IBluntDelegate.sol';
import './interfaces/IPriceFeed.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutTerminal.sol';

/// @title Blunt Round data source for Juicebox projects, based on Slice protocol.
/// @author jacopo <jacopo@slice.so>
/// @notice Funding rounds with pre-defined rules which reward contributors with tokens and slices.
contract BluntDelegate is IBluntDelegate {
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//
  error INVALID_PAYMENT_EVENT();
  error CAP_REACHED();
  error SLICER_NOT_YET_CREATED();
  error VALUE_NOT_EXACT();
  error ROUND_ENDED();
  error ROUND_NOT_ENDED();
  error ROUND_CLOSED();
  error ROUND_NOT_CLOSED();
  error NOT_PROJECT_OWNER();
  error TOKEN_NOT_SET();
  error CANNOT_ACCEPT_ERC1155();
  error CANNOT_ACCEPT_ERC721();

  //*********************************************************************//
  // ------------------------------ events ----------------------------- //
  //*********************************************************************//
  event RoundCreated(
    DeployBluntDelegateData deployBluntDelegateData,
    uint256 projectId,
    uint256 duration
  );
  event ClaimedSlices(address beneficiary, uint256 amount);
  event ClaimedSlicesBatch(address[] beneficiaries, uint256[] amounts);
  event TokenMetadataSet(string tokenName_, string tokenSymbol_);
  event RoundClosed();
  event SlicerCreated(uint256 slicerId_, address slicerAddress);

  //*********************************************************************//
  // ------------------------ immutable storage ------------------------ //
  //*********************************************************************//

  /**
    @notice
    Ratio between amount of tokens contributed and slices minted
  */
  uint256 public constant TOKENS_PER_SLICE = 1e15; /// 1 slice every 0.001 ETH

  /**
    @notice
    Max total contribution allowed, calculated from `TOKENS_PER_SLICE * type(uint32).max`
  */
  uint256 public constant MAX_CONTRIBUTION = 4.2e6 ether;

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
    The ID of the Blunt Finance project.
  */
  uint256 public immutable bluntProjectId;

  /**
    @notice
    The ID of the project.
  */
  uint256 public immutable projectId;

  /**
    @notice
    Constants used to calculate Blunt Finance fee
  */
  uint256 public immutable MAX_K;
  uint256 public immutable MIN_K;
  uint256 public immutable UPPER_FUNDRAISE_BOUNDARY_USD;
  uint256 public immutable LOWER_FUNDRAISE_BOUNDARY_USD;

  /**
    @notice
    The directory of terminals and controllers for projects.
  */
  IJBDirectory private immutable directory;

  IJBController private immutable controller;

  /**
    @notice
    SliceCore instance
  */
  ISliceCore private immutable sliceCore;

  /**
    @notice
    WETH address on Uniswap
  */
  address private immutable ethAddress;

  /**
    @notice
    USDC address on Uniswap
  */
  address private immutable usdcAddress;

  /** 
    @notice
    The owner of the project once the blunt round is concluded successfully.
  */
  address private immutable projectOwner;

  /** 
    @notice
    The minimum amount of contributions while this data source is in effect.
    When `isTargetUsd` is enabled, it is a 6 point decimal number.
  */
  uint256 private immutable target;

  /** 
    @notice
    The maximum amount of contributions while this data source is in effect. 
    When `isHardcapUsd` is enabled, it is a 6 point decimal number.
  */
  uint256 private immutable hardcap;

  /**  
    @notice
    The timestamp when the slicer becomes releasable.
  */
  uint256 private immutable releaseTimelock;

  /** 
    @notice
    The timestamp when the slicer becomes transferable.
  */
  uint256 private immutable transferTimelock;

  /** 
    @notice
    Reserved rate to be set in case of a successful round
  */
  uint256 private immutable afterRoundReservedRate;

  /**
    @notice
    Deadline of the round
  */
  uint256 private immutable deadline;

  /**
    @notice
    True if a target is expressed in USD
  */
  bool private immutable isTargetUsd;

  /**
    @notice
    True if a hardcap is expressed in USD
  */
  bool private immutable isHardcapUsd;

  /**
    @notice
    True if a slicer is created when round closes successfully
  */
  bool private immutable isSlicerToBeCreated;

  //*********************************************************************//
  // ------------------------- mutable storage ------------------------- //
  //*********************************************************************//

  /**
    @notice
    ID of the slicer related to the blunt round
    
    @dev Assumes ID 0 is not created, since it's generally taken by the protocol.
    uint144 is sufficient and saves gas by bit packing efficiently.
  */
  uint144 private slicerId;

  /**
    @notice
    Total contributions received during round
    @dev uint88 is sufficient as it cannot be higher than `MAX_CONTRIBUTION`
  */
  uint88 private totalContributions;

  /**
    @notice
    True if the round has been closed 
  */
  bool private isRoundClosed;

  /** 
    @notice
    Name of the token to be issued in case of a successful round
  */
  string private tokenName;

  /** 
    @notice
    Symbol of the token to be issued in case of a successful round
  */
  string private tokenSymbol;

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
    @param _deployBluntDelegateDeployerData Deployment data sent by deployer contract
    @param _deployBluntDelegateData Deployment data sent by user
  */
  constructor(
    DeployBluntDelegateDeployerData memory _deployBluntDelegateDeployerData,
    DeployBluntDelegateData memory _deployBluntDelegateData
  ) {
    if (_deployBluntDelegateData.projectOwner.code.length != 0)
      _doSafeTransferAcceptanceCheckERC721(_deployBluntDelegateData.projectOwner);

    MAX_K = uint16(_deployBluntDelegateDeployerData.maxK);
    MIN_K = uint16(_deployBluntDelegateDeployerData.minK);
    UPPER_FUNDRAISE_BOUNDARY_USD = uint56(_deployBluntDelegateDeployerData.upperFundraiseBoundary);
    LOWER_FUNDRAISE_BOUNDARY_USD = uint56(_deployBluntDelegateDeployerData.lowerFundraiseBoundary);
    bluntProjectId = _deployBluntDelegateDeployerData.bluntProjectId;
    projectId = _deployBluntDelegateDeployerData.projectId;
    ethAddress = _deployBluntDelegateDeployerData.ethAddress;
    usdcAddress = _deployBluntDelegateDeployerData.usdcAddress;
    controller = _deployBluntDelegateDeployerData.controller;

    directory = _deployBluntDelegateData.directory;
    sliceCore = _deployBluntDelegateData.sliceCore;
    projectOwner = _deployBluntDelegateData.projectOwner;
    releaseTimelock = _deployBluntDelegateData.releaseTimelock;
    transferTimelock = _deployBluntDelegateData.transferTimelock;
    afterRoundReservedRate = _deployBluntDelegateData.afterRoundReservedRate;
    target = _deployBluntDelegateData.target;
    isTargetUsd = _deployBluntDelegateData.isTargetUsd;
    hardcap = _deployBluntDelegateData.hardcap;
    isHardcapUsd = _deployBluntDelegateData.isHardcapUsd;

    /// Set `isSlicerToBeCreated` if the first split is reserved to the slicer
    isSlicerToBeCreated =
      _deployBluntDelegateData.enforceSlicerCreation ||
      (_deployBluntDelegateData.afterRoundSplits.length != 0 &&
        _deployBluntDelegateData.afterRoundSplits[0].beneficiary == address(0));

    /// Set token name and symbol
    if (bytes(_deployBluntDelegateData.tokenName).length != 0)
      tokenName = _deployBluntDelegateData.tokenName;
    if (bytes(_deployBluntDelegateData.tokenSymbol).length != 0)
      tokenSymbol = _deployBluntDelegateData.tokenSymbol;

    /// Set deadline based on round duration
    deadline = _deployBluntDelegateDeployerData.duration == 0
      ? 0
      : block.timestamp + _deployBluntDelegateDeployerData.duration;

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
    It will update storage for the slices mint if conditions are met.

    @dev 
    This function will revert if the contract calling is not one of the project's terminals. 
    Value sent must be a multiple of 0.001 ETH.

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

    /// Ensure contributed amount is a multiple of `TOKENS_PER_SLICE`
    if (_data.amount.value % TOKENS_PER_SLICE != 0) revert VALUE_NOT_EXACT();
    if (_data.amount.value > type(uint88).max) revert CAP_REACHED();

    /// Update totalContributions and contributions with amount paid
    totalContributions += uint88(_data.amount.value);

    /// Revert if `totalContributions` exceeds `hardcap` or `MAX_CONTRIBUTION`
    _hardcapCheck();

    /// If a slicer is to be created when round closes
    if (isSlicerToBeCreated) {
      /// If it's the first contribution of the beneficiary, and it is a contract
      if (contributions[_data.beneficiary] == 0 && _data.beneficiary.code.length != 0) {
        /// Revert if beneficiary doesn't accept ERC1155
        _doSafeTransferAcceptanceCheckERC1155(_data.beneficiary);
      }

      /// Cannot overflow as totalContributions would overflow first
      unchecked {
        contributions[_data.beneficiary] += _data.amount.value;
      }
    }
  }

  /**
    @notice 
    Part of IJBRedemptionDelegate, this function gets called when the beneficiary redeems tokens. 
    It will update storage for the slices mint if conditions are met. 

    @dev 
    This function will revert if the contract calling is not one of the project's terminals. 
    Value redeemed must be a multiple of 0.001 ETH.

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

    /// If round is open, execute logic to keep track of slices to issue
    if (!isRoundClosed) {
      /// Ensure contributed amount is a multiple of `TOKENS_PER_SLICE`
      if (_data.reclaimedAmount.value % TOKENS_PER_SLICE != 0) revert VALUE_NOT_EXACT();

      /// @dev Cannot underflow as `_data.reclaimedAmount.value` cannot be higher than `contributions[_data.beneficiary]`
      /// contributions can be inside unchecked as token transfers are disabled during round
      unchecked {
        /// Update totalContributions and contributions with amount redeemed
        totalContributions -= uint88(_data.reclaimedAmount.value);

        /// If a slicer is to be created when round closes
        if (isSlicerToBeCreated) {
          contributions[_data.beneficiary] -= _data.reclaimedAmount.value;
        }
      }
    }
  }

  /**
    @notice 
    Transfer any unclaimed slices to `beneficiaries` in batch.

    @dev 
    This function will revert if the slicer hasn't been created yet.
  */
  function transferUnclaimedSlicesTo(address[] calldata beneficiaries) external override {
    if (slicerId == 0) revert SLICER_NOT_YET_CREATED();

    /// Add reference for slices amounts of each beneficiary
    uint256[] memory amounts = new uint256[](beneficiaries.length);

    uint256 contribution;
    /// Loop over beneficiaries
    for (uint256 i; i < beneficiaries.length; ) {
      contribution = contributions[beneficiaries[i]];
      if (contribution != 0) {
        /// Calculate slices to claim and set the beneficiary amount in amounts array
        amounts[i] = contribution / TOKENS_PER_SLICE;
        /// Update storage
        contributions[beneficiaries[i]] = 0;
      }
      unchecked {
        ++i;
      }
    }

    /// Send slices to beneficiaries along with any earnings
    sliceCore.slicerBatchTransfer(address(this), beneficiaries, slicerId, amounts, false);

    emit ClaimedSlicesBatch(beneficiaries, amounts);
  }

  /**
    @notice 
    Allows a beneficiary to get any unclaimed slices to itself.

    @dev 
    This function will revert if the slicer hasn't been created yet.
  */
  function claimSlices() external override {
    if (slicerId == 0) revert SLICER_NOT_YET_CREATED();

    /// Calculate amount to claim
    uint256 amount = contributions[msg.sender] / TOKENS_PER_SLICE;

    if (amount != 0) {
      /// Update storage
      contributions[msg.sender] = 0;

      /// Send slices to beneficiary along with a proportional amount of tokens accrued
      sliceCore.safeTransferFromUnreleased(address(this), msg.sender, slicerId, amount, '');
    }

    emit ClaimedSlices(msg.sender, amount);
  }

  /**
    @notice 
    Update token metadata related to the project

    @dev
    Non null token name and symbol are required to close a round successfully
  */
  function setTokenMetadata(
    string memory tokenName_,
    string memory tokenSymbol_
  ) external override {
    if (msg.sender != projectOwner) revert NOT_PROJECT_OWNER();
    if (isRoundClosed) revert ROUND_CLOSED();

    tokenName = tokenName_;
    tokenSymbol = tokenSymbol_;

    emit TokenMetadataSet(tokenName_, tokenSymbol_);
  }

  /**
    @notice 
    Transfers the entire balance of an ERC20 token from this contract to the slicer if the round 
    was closed successfully, otherwise the project owner.
    Acts as safeguard if ERC20 tokens are mistakenly sent to this address, preventing them to end up locked.
    
    @dev Reverts if round is not closed.
  */
  function transferToken(IERC20 token) external override {
    if (!isRoundClosed) revert ROUND_NOT_CLOSED();
    uint256 slicerId_ = slicerId;

    address to = isTargetReached() && slicerId_ != 0 ? sliceCore.slicers(slicerId_) : projectOwner;
    token.transfer(to, token.balanceOf(address(this)));
  }

  /**
    @notice 
    Close blunt round if target has been reached:
    - Pay BF fee, 
    - Mint slices to blunt delegate, 
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
      if (deadline != 0 && block.timestamp < deadline) revert ROUND_NOT_ENDED();

      address currency;
      string memory tokenName_ = tokenName;
      string memory tokenSymbol_ = tokenSymbol;
      /// If token name and symbol have been set
      if (bytes(tokenName_).length != 0 && bytes(tokenSymbol_).length != 0) {
        /// Issue ERC20 project token and get contract address
        currency = address(controller.tokenStore().issueFor(projectId, tokenName_, tokenSymbol_));
      }

      if (isSlicerToBeCreated) {
        /// Revert if currency hasn't been issued
        if (currency == address(0)) revert TOKEN_NOT_SET();

        /// Create slicer and mint slices to bluntDelegate
        address slicerAddress = _mintSlicesToDelegate(currency);

        if (afterRoundSplits.length != 0 && afterRoundSplits[0].beneficiary == address(0)) {
          /// Update split with slicer address
          afterRoundSplits[0].beneficiary = payable(slicerAddress);
          afterRoundSplits[0].preferClaimed = true;
        }
      }

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
        ''
      );

      // Distribute payout fee to Blunt Finance
      IJBPayoutTerminal(jbEthTerminalAddress).distributePayoutsOf({
        _projectId: projectId,
        _amount: bluntFee,
        _currency: 1,
        _token: ETH,
        _minReturnedTokens: 0,
        _memo: ''
      });

      /// Transfer project ownership to projectOwner
      directory.projects().safeTransferFrom(address(this), projectOwner, projectId);
    }

    emit RoundClosed();
  }

  /**
    @notice 
    Creates project's token, slicer and issues `slicesToMint` to this contract.
  */
  function _mintSlicesToDelegate(address currency) private returns (address slicerAddress) {
    /// Calculate `slicesToMint`
    /// @dev Cannot overflow uint32 as totalContributions <= MAX_CONTRIBUTION
    uint32 slicesToMint = uint32(totalContributions / TOKENS_PER_SLICE);

    /// Add references for sliceParams
    Payee[] memory payees = new Payee[](1);
    payees[0] = Payee(address(this), slicesToMint, true);
    address[] memory acceptedCurrencies = new address[](1);
    acceptedCurrencies[0] = currency;

    /// Create slicer and mint all slices to this address
    uint256 slicerId_;
    (slicerId_, slicerAddress) = sliceCore.slice(
      SliceParams(
        payees,
        slicesToMint, /// 100% superowner slices
        acceptedCurrencies,
        releaseTimelock,
        uint40(transferTimelock),
        address(0),
        0,
        0
      )
    );

    slicerId = uint144(slicerId_);

    emit SlicerCreated(slicerId_, slicerAddress);
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

  /**
    @notice
    Returns info related to round.
  */
  function getRoundInfo() external view override returns (RoundInfo memory roundInfo) {
    roundInfo = RoundInfo(
      totalContributions,
      target,
      hardcap,
      releaseTimelock,
      transferTimelock,
      projectOwner,
      afterRoundReservedRate,
      afterRoundSplits,
      tokenName,
      tokenSymbol,
      isRoundClosed,
      deadline,
      isTargetUsd,
      isHardcapUsd,
      isSlicerToBeCreated,
      slicerId
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
    } else {
      hardcap_ = MAX_CONTRIBUTION;
    }

    if (totalContributions > hardcap_) revert CAP_REACHED();
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
    @notice
    See {ERC1155:_doSafeTransferAcceptanceCheck}
  */
  function _doSafeTransferAcceptanceCheckERC1155(address to) private {
    try IERC1155Receiver(to).onERC1155Received(address(this), address(this), 1, 1, '') returns (
      bytes4 response
    ) {
      if (response != this.onERC1155Received.selector) {
        revert CANNOT_ACCEPT_ERC1155();
      }
    } catch Error(string memory reason) {
      revert(reason);
    } catch {
      revert CANNOT_ACCEPT_ERC1155();
    }
  }

  /**
    @notice
    See {ERC721:_checkOnERC721Received}
  */
  function _doSafeTransferAcceptanceCheckERC721(address to) private {
    try IERC721Receiver(to).onERC721Received(address(this), address(this), 1, '') returns (
      bytes4 response
    ) {
      if (response != this.onERC721Received.selector) {
        revert CANNOT_ACCEPT_ERC721();
      }
    } catch Error(string memory reason) {
      revert(reason);
    } catch {
      revert CANNOT_ACCEPT_ERC721();
    }
  }

  //*********************************************************************//
  // ------------------------------ hooks ------------------------------ //
  //*********************************************************************//

  /**
   * @dev See `ERC1155Receiver`
   */
  function onERC1155Received(
    address,
    address,
    uint256,
    uint256,
    bytes memory
  ) public view override returns (bytes4) {
    if (msg.sender != address(sliceCore)) revert('NOT_SUPPORTED');
    return this.onERC1155Received.selector;
  }

  /**
   * @dev See `ERC1155Receiver`
   */
  function onERC1155BatchReceived(
    address,
    address,
    uint256[] memory,
    uint256[] memory,
    bytes memory
  ) public view override returns (bytes4) {
    if (msg.sender != address(sliceCore)) revert('NOT_SUPPORTED');
    return this.onERC1155BatchReceived.selector;
  }

  /**
   * @dev See `ERC721Receiver`
   */
  function onERC721Received(
    address,
    address,
    uint256,
    bytes calldata
  ) public pure override returns (bytes4) {
    return this.onERC721Received.selector;
  }
}
