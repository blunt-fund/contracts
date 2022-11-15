// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './interfaces/ISliceCore.sol';
import './interfaces/IBluntDelegate.sol';
import '@openzeppelin/contracts/utils/introspection/ERC165.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBConstants.sol';

/// @title Blunt Round data source for Juicebox projects, based on Slice protocol.
/// @author jacopo <jacopo@slice.so>
/// @author jango <jango.eth>
/// @notice Rewards participants of a round with a part of reserved rate, using a slicer for distribution.
contract BluntDelegate is IBluntDelegate {
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//
  error INVALID_PAYMENT_EVENT();
  error CAP_REACHED();
  error SLICER_NOT_YET_CREATED();
  error VALUE_NOT_EXACT();
  error ROUND_CLOSED();
  error NOT_PROJECT_OWNER();

  //*********************************************************************//
  // --------------- public immutable stored properties ---------------- //
  //*********************************************************************//

  /**
    @notice
    Ratio between amount of tokens contributed and slices minted
  */
  uint64 public constant TOKENS_PER_SLICE = 1e15; // 1 slice every 0.001 ETH

  /**
    @notice
    Max total contribution allowed, calculated from `TOKENS_PER_SLICE * type(uint32).max`
  */
  uint88 public constant MAX_CONTRIBUTION = 4.2e6 ether;

  /**
    @notice
    The ID of the project.
  */
  uint256 public immutable projectId;

  /**
    @notice
    The directory of terminals and controllers for projects.
  */
  IJBDirectory public immutable directory;

  IJBTokenStore public immutable tokenStore;

  IJBFundingCycleStore public immutable fundingCycleStore;

  IJBProjects public immutable projects;

  IJBController public immutable controller;

  /**
    @notice
    SliceCore instance
  */
  ISliceCore public immutable sliceCore;

  /** 
    @notice
    The owner of the project once the blunt round is concluded successfully.
  */
  address public immutable projectOwner;
  /** 
    @notice
    The minimum amount of contributions while this data source is in effect.
    @dev uint88 is enough as it cannot be higher than `MAX_CONTRIBUTION`
  */
  uint88 public immutable target;
  /** 
    @notice
    The maximum amount of contributions while this data source is in effect. 
    @dev uint88 is enough as it cannot be higher than `MAX_CONTRIBUTION`
  */
  uint88 public immutable hardCap;
  /**  
    @notice
    The timestamp when the slicer becomes releasable.
  */
  uint40 public immutable releaseTimelock;
  /** 
    @notice
    The timestamp when the slicer becomes transferable.
  */
  uint40 public immutable transferTimelock;
  /** 
    @notice
    The number of the funding cycle related to the blunt round.
    @dev uint40 for bit packing
  */
  uint40 public immutable fundingCycleRound;
  /** 
    @notice
    Reserved rate to be set in case of a successful round
  */
  uint16 public immutable afterRoundReservedRate;
  /** 
    @notice
    Project metadata splits to be enabled when a successful round is closed.
  */
  JBGroupedSplits[] public afterRoundSplits;
  /** 
    @notice
    Name of the token to be issued in case of a successful round
  */
  string public tokenName;
  /** 
    @notice
    Symbol of the token to be issued in case of a successful round
  */
  string public tokenSymbol;

  //*********************************************************************//
  // ---------------- public mutable stored properties ----------------- //
  //*********************************************************************//

  /**
    @notice
    Total contributions received during round
  */
  uint88 public totalContributions;

  /**
    @notice
    ID of the slicer related to the blunt round
    
    @dev Assumes ID 0 is not created, since it's generally taken by the protocol.
  */
  uint160 public slicerId;

  /**
    @notice
    True if the round has been closed 
  */
  bool public isRoundClosed;

  /**
    @notice
    Mapping from beneficiary to contributions
  */
  mapping(address => uint256) public contributions;

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
    Part of IJBFundingCycleDataSource, this function gets called when a project's token holders redeem. It will return the standard properties.

    @param _data The Juicebox standard project redemption data.

    @return reclaimAmount The amount that should be reclaimed from the treasury.
    @return memo The memo that should be forwarded to the event.
    @return delegateAllocations The amount to send to delegates instead of adding to the beneficiary.
  */
  function redeemParams(JBRedeemParamsData calldata _data)
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
  function getRoundInfo()
    external
    view
    override
    returns (
      uint256,
      uint256,
      uint256,
      uint40,
      uint40,
      address,
      uint40,
      uint16,
      JBGroupedSplits[] memory,
      string memory,
      string memory,
      bool,
      uint256
    )
  {
    return (
      totalContributions,
      target,
      hardCap,
      releaseTimelock,
      transferTimelock,
      projectOwner,
      fundingCycleRound,
      afterRoundReservedRate,
      afterRoundSplits,
      tokenName,
      tokenSymbol,
      isRoundClosed,
      slicerId
    );
  }

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  /**
    @param _projectId The ID of the project for which this NFT should be minted in response to payments made. 
    @param _deployBluntDelegateData Data required for deployment
  */
  constructor(uint256 _projectId, DeployBluntDelegateData memory _deployBluntDelegateData) {
    projectId = _projectId;
    directory = _deployBluntDelegateData.directory;
    tokenStore = _deployBluntDelegateData.tokenStore;
    fundingCycleStore = _deployBluntDelegateData.fundingCycleStore;
    projects = _deployBluntDelegateData.projects;
    controller = _deployBluntDelegateData.controller;
    sliceCore = _deployBluntDelegateData.sliceCore;
    projectOwner = _deployBluntDelegateData.projectOwner;
    hardCap = _deployBluntDelegateData.hardCap;
    target = _deployBluntDelegateData.target;
    releaseTimelock = _deployBluntDelegateData.releaseTimelock;
    transferTimelock = _deployBluntDelegateData.transferTimelock;
    afterRoundReservedRate = _deployBluntDelegateData.afterRoundReservedRate;
    afterRoundSplits = _deployBluntDelegateData.afterRoundSplits;
    tokenName = _deployBluntDelegateData.tokenName;
    tokenSymbol = _deployBluntDelegateData.tokenSymbol;

    /// Store current funding cycle
    fundingCycleRound = uint40(
      _deployBluntDelegateData.fundingCycleStore.currentOf(_projectId).number
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
    /// - The funding cycle related to the round hasn't ended
    /// - The blunt round hasn't been closed
    if (
      !directory.isTerminalOf(projectId, IJBPaymentTerminal(msg.sender)) ||
      _data.projectId != projectId ||
      fundingCycleStore.currentOf(projectId).number != fundingCycleRound ||
      isRoundClosed
    ) revert INVALID_PAYMENT_EVENT();

    /// Ensure contributed amount is a multiple of `TOKENS_PER_SLICE`
    if (_data.amount.value % TOKENS_PER_SLICE != 0) revert VALUE_NOT_EXACT();
    if (_data.amount.value > type(uint88).max) revert CAP_REACHED();

    /// Update totalContributions and contributions with amount paid
    totalContributions += uint88(_data.amount.value);

    /// Make sure totalContributions is below `hardCap` and `MAX_CONTRIBUTION`
    uint256 cap = hardCap != 0 ? hardCap : MAX_CONTRIBUTION;
    if (totalContributions > cap) revert CAP_REACHED();

    /// Cannot overflow as totalContributions would overflow first
    unchecked {
      contributions[_data.beneficiary] += _data.amount.value;
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

    /// Ensure contributed amount is a multiple of `TOKENS_PER_SLICE`
    if (_data.reclaimedAmount.value % TOKENS_PER_SLICE != 0) revert VALUE_NOT_EXACT();

    /// @dev Cannot underflow as `_data.reclaimedAmount.value` cannot be higher than `contributions[_data.beneficiary]`
    /// contributions can be inside unchecked as token transfers are disabled during round
    unchecked {
      /// Update totalContributions and contributions with amount redeemed
      totalContributions -= uint88(_data.reclaimedAmount.value);
      contributions[_data.beneficiary] -= _data.reclaimedAmount.value;
    }
  }

  /**
    @notice 
    Transfer any unclaimed slices to `beneficiaries` in batch.

    @dev 
    This function will revert if the slicer hasn't been created yet.
  */
  function transferUnclaimedSlicesTo(address[] calldata beneficiaries) external override {
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
  }

  /**
    @notice 
    Allows a beneficiary to get any unclaimed slices to itself.

    @dev 
    This function will revert if the slicer hasn't been created yet.
  */
  function claimSlices() external override {
    if (slicerId == 0) revert SLICER_NOT_YET_CREATED();

    /// Add reference to contributions for msg.sender
    uint256 contribution = contributions[msg.sender];

    if (contribution != 0) {
      /// Update storage
      contributions[msg.sender] = 0;

      /// Send slices to beneficiary along with a proportional amount of tokens accrued
      sliceCore.safeTransferFromUnreleased(
        address(this),
        msg.sender,
        slicerId,
        contribution / TOKENS_PER_SLICE,
        ''
      );
    }
  }

  // function queueNextPhase() external {
  //   // If blunt round has a duration set
  //   if (_launchProjectData.data.duration != 0) {
  //     // TODO: Configure FC after blunt round to have 0 duration
  //     // in order for `closeRound` to have immediate effect
  //   }
  // }

  /**
    @notice 
    Close blunt round if target has been reached. 
    Consists in minting slices to blunt delegate, reconfiguring next FC and transferring project NFT to projectOwner.
    If called when totalContributions hasn't reached the target, disables payments and keeps full redemptions enabled.

    @dev 
    Can only be called once by the appointed project owner.
  */
  // TODO: @jango Check all of this makes sense
  function closeRound() external override {
    // Revert if not called by projectOwner
    if (msg.sender != projectOwner) revert NOT_PROJECT_OWNER();

    // Revert if not called by projectOwner
    if (isRoundClosed) revert ROUND_CLOSED();
    isRoundClosed = true;

    // If target has been reached
    if (totalContributions > target) {
      // Get current JBFundingCycleMetadata
      (, JBFundingCycleMetadata memory metadata) = controller.currentFundingCycleOf(projectId);

      // Edit current metadata to:
      // Set reservedRate from `afterRoundReservedRate`
      metadata.reservedRate = afterRoundReservedRate;
      // Disable redemptions
      delete metadata.redemptionRate;
      // Enable transfers
      delete metadata.global.pauseTransfers;
      // Pause pay, to allow projectOwner to reconfig as needed before re-enabling
      metadata.pausePay = true;
      // Detach dataSource
      delete metadata.useDataSourceForPay;
      delete metadata.useDataSourceForRedeem;
      delete metadata.dataSource;

      // Set JBFundingCycleData
      JBFundingCycleData memory data = JBFundingCycleData({
        duration: 0,
        weight: 1e24, // token issuance 1M
        discountRate: 0,
        ballot: IJBFundingCycleBallot(address(0))
      });

      // Create slicer, mint slices and issue project token
      address slicerAddress = _mintSlicesToDelegate();

      // If first split beneficiary is unset, it's reserved to the slicer
      if (afterRoundSplits[0].splits[0].beneficiary == address(0)) {
        // Set up slicer split
        afterRoundSplits[0].splits[0].beneficiary = payable(slicerAddress);
        afterRoundSplits[0].splits[0].preferClaimed = true;
      }

      // Reconfigure Funding Cycle
      controller.reconfigureFundingCyclesOf(
        projectId,
        data,
        metadata,
        0,
        afterRoundSplits,
        new JBFundAccessConstraints[](0),
        ''
      );

      /// Transfer project ownership to projectOwner
      projects.safeTransferFrom(address(this), projectOwner, projectId);
    }
  }

  /**
    @notice 
    Creates project's token, slicer and issues `slicesToMint` to this contract.
  */
  function _mintSlicesToDelegate() private returns (address slicerAddress) {
    /// Issue ERC20 project token and get address
    address currency = address(tokenStore.issueFor(projectId, tokenName, tokenSymbol));

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
        transferTimelock,
        address(0),
        0,
        0
      )
    );

    slicerId = uint160(slicerId_);
  }

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

/// Note
/// Slices have a max of `type(uint32).max`, so it's necessary to convert between value paid and slices, either during pay / redeem or during slice issuance.

/// - Storing the VALUE sent on pay / redeem, and calculate slices during issuance, allows to have the most efficient + seamless logic. However consider an extreme scenario where `totalContributions` > 0 but all contributions are below `TOKENS_PER_SLICE`. This would result in no slices being minted even though the treasury has received money. The problem is present whenever the amount paid doesn't exactly correspond that which should've been contributed to get a number of slices, either in excess or in defect.
/// - Designing so that slices are calculated during pay / redeem increases complexity and costs significantly, while adding a bunch of foot guns. I considered going down that road but realised it introduced other issues.
/// - Proposed solution uses the former logic, but enforces `(_data.amount.value % TOKENS_PER_SLICE == 0)` so that there is no payment in excess. This will also be enforced on the frontend, but might require JB frontend to eventually adapt as well
