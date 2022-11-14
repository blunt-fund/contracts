// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import './interfaces/ISliceCore.sol';
import './interfaces/IBluntDelegate.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol';
import '@openzeppelin/contracts/utils/introspection/ERC165.sol';
import '@jbx-protocol/contracts-v2/contracts/interfaces/IJBDirectory.sol';
import '@jbx-protocol/contracts-v2/contracts/interfaces/IJBTokenStore.sol';
import '@jbx-protocol/contracts-v2/contracts/interfaces/IJBFundingCycleDataSource.sol';
import '@jbx-protocol/contracts-v2/contracts/interfaces/IJBPayDelegate.sol';
import '@jbx-protocol/contracts-v2/contracts/interfaces/IJBRedemptionDelegate.sol';

contract BluntDelegate is
  IBluntDelegate,
  IJBFundingCycleDataSource,
  IJBPayDelegate,
  IJBRedemptionDelegate,
  IERC1155Receiver
{
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//
  error INVALID_PAYMENT_EVENT();
  error CAP_REACHED();
  error TARGET_NOT_REACHED();
  error SLICER_ALREADY_CREATED();
  error SLICER_NOT_YET_CREATED();
  error VALUE_NOT_EXACT();
  error NOT_PROJECT_OWNER();

  //*********************************************************************//
  // --------------- public immutable stored properties ---------------- //
  //*********************************************************************//

  /**
    @notice
    The ID of the project this NFT should be distributed for.
  */
  uint256 public immutable projectId;

  /**
    @notice
    The directory of terminals and controllers for projects.
  */
  IJBDirectory public immutable directory;

  IJBTokenStore public immutable tokenStore;

  /** 
    @notice
    The minimum amount of project tokens allowed to be issued while this data source is in effect. 
  */
  uint256 public immutable target;
  /** 
    @notice
    The maximum amount of project tokens allowed to be issued while this data source is in effect. 
  */
  uint256 public immutable hardCap;
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
    SliceCore instance
  */
  ISliceCore public immutable sliceCore;

  /**
    @notice
    Ratio between amount of tokens contributed and slices minted
  */
  uint64 public constant TOKENS_PER_SLICE = 1e15; // 1 slice every 0.001 ETH

  /**
    @notice
    Max total contribution allowed, calculated from `TOKENS_PER_SLICE * type(uint32).max`
  */
  uint96 public constant MAX_CONTRIBUTION = 4.2e6 ether;

  //*********************************************************************//
  // ---------------- public mutable stored properties ----------------- //
  //*********************************************************************//

  /**
    @notice
    Total contributions received during round
  */
  uint256 public totalContributions;

  /**
    @notice
    Mapping from beneficiary to contributions
  */
  mapping(address => uint256) public contributions;

  /**
    @notice
    ID of the slicer related to the blunt round
    
    @dev Assumes ID 0 is not created, since it's generally taken by the protocol.
  */
  uint256 public slicerId;

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
    @return delegate A delegate to call once the payment has taken place.
  */
  function payParams(JBPayParamsData calldata _data)
    external
    view
    override
    returns (
      uint256 weight,
      string memory memo,
      IJBPayDelegate delegate
    )
  {
    // Forward the recieved weight and memo, and use this contract as a pay delegate.
    return (_data.weight, _data.memo, IJBPayDelegate(address(this)));
  }

  /**
    @notice 
    Part of IJBFundingCycleDataSource, this function gets called when a project's token holders redeem. It will return the standard properties.

    @param _data The Juicebox standard project redemption data.

    @return reclaimAmount The amount that should be reclaimed from the treasury.
    @return memo The memo that should be forwarded to the event.
    @return delegate A delegate to call once the redemption has taken place.
  */
  function redeemParams(JBRedeemParamsData calldata _data)
    external
    view
    override
    returns (
      uint256 reclaimAmount,
      string memory memo,
      IJBRedemptionDelegate delegate
    )
  {
    return (_data.reclaimAmount.value, _data.memo, IJBRedemptionDelegate(address(this)));
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

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  /**
    @param _projectId The ID of the project for which this NFT should be minted in response to payments made. 
    @param _directory The directory of terminals and controllers for projects.
    @param _hardCap The maximum amount of project tokens that can be issued.
  */
  constructor(
    uint256 _projectId,
    IJBDirectory _directory,
    IJBTokenStore _tokenStore,
    ISliceCore _sliceCore,
    uint256 _hardCap,
    uint256 _target,
    uint40 _releaseTimelock,
    uint40 _transferTimelock
  ) {
    projectId = _projectId;
    directory = _directory;
    tokenStore = _tokenStore;
    sliceCore = _sliceCore;
    hardCap = _hardCap;
    target = _target;
    releaseTimelock = _releaseTimelock;
    transferTimelock = _transferTimelock;
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
  function didPay(JBDidPayData calldata _data) external virtual override {
    // Make sure the caller is a terminal of the project, and the call is being made on behalf of an interaction with the correct project.
    if (
      !directory.isTerminalOf(projectId, IJBPaymentTerminal(msg.sender)) ||
      _data.projectId != projectId
    ) revert INVALID_PAYMENT_EVENT();

    // Ensure contributed amount is a multiple of `TOKENS_PER_SLICE`
    if (_data.amount.value % TOKENS_PER_SLICE != 0) revert VALUE_NOT_EXACT();

    // Update totalContributions and contributions with amount paid
    totalContributions += _data.amount.value;

    // Make sure totalContributions is below `hardCap` and `MAX_CONTRIBUTION`
    uint256 cap = hardCap != 0 && hardCap < MAX_CONTRIBUTION ? hardCap : MAX_CONTRIBUTION;
    if (totalContributions > cap) revert CAP_REACHED();

    // Cannot overflow as totalContributions would overflow first
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
  function didRedeem(JBDidRedeemData calldata _data) external virtual override {
    // Make sure the caller is a terminal of the project, and the call is being made on behalf of an interaction with the correct project.
    if (
      !directory.isTerminalOf(projectId, IJBPaymentTerminal(msg.sender)) ||
      _data.projectId != projectId
    ) revert INVALID_PAYMENT_EVENT();

    // Ensure contributed amount is a multiple of `TOKENS_PER_SLICE`
    if (_data.reclaimedAmount.value % TOKENS_PER_SLICE != 0) revert VALUE_NOT_EXACT();

    // Cannot underflow as `_data.reclaimedAmount.value` cannot be higher than `contributions[_data.beneficiary]`
    unchecked {
      // Update totalContributions and contributions with amount redeemed
      totalContributions -= _data.reclaimedAmount.value;
      contributions[_data.beneficiary] -= _data.reclaimedAmount.value;
    }
  }

  /**
    @notice 
    Creates slicer and issues `slicesToMint` to this contract.

    @dev 
    This function will revert if the funding cycle related to the blunt round hasn't ended or if the slicer has already been created.
  */
  function issueSlices() external override {
    if (slicerId != 0) revert SLICER_ALREADY_CREATED();

    // TODO: @jango Add requirement: Revert if current funding cycle hasn't ended? What other requirements

    // TODO: Add this in requirements for closing funding cycle
    if (target != 0) {
      if (totalContributions < target) revert TARGET_NOT_REACHED();
    }

    // TODO: @jango Issue ERC20 and get address
    address currency;

    // Cannot overflow uint32 as totalContributions <= MAX_CONTRIBUTION
    uint32 slicesToMint = uint32(totalContributions / TOKENS_PER_SLICE);

    // Add references for sliceParams
    Payee[] memory payees = new Payee[](1);
    payees[0] = Payee(address(this), slicesToMint, true);
    address[] memory acceptedCurrencies = new address[](1);
    acceptedCurrencies[0] = currency;

    // Create slicer and mint all slices to this address
    sliceCore.slice(
      SliceParams(
        payees,
        slicesToMint, // 100% superowner slices
        acceptedCurrencies,
        releaseTimelock,
        transferTimelock,
        address(0),
        0,
        0
      )
    );

    slicerId = sliceCore.supply() - 1;
  }

  /**
    @notice 
    Transfer any unclaimed slices to `beneficiaries` in batch.

    @dev 
    This function will revert if the slicer hasn't been created yet.
  */
  function transferUnclaimedSlicesTo(address[] calldata beneficiaries) external override {
    if (slicerId == 0) revert SLICER_NOT_YET_CREATED();

    // Add reference for slices amounts of each beneficiary
    uint256[] memory amounts = new uint256[](beneficiaries.length);

    uint256 contribution;
    // Loop over beneficiaries
    for (uint256 i; i < beneficiaries.length; ) {
      contribution = contributions[beneficiaries[i]];
      if (contribution != 0) {
        // Calculate slices to claim and set the beneficiary amount in amounts array
        amounts[i] = contribution / TOKENS_PER_SLICE;
        // Update storage
        contributions[beneficiaries[i]] = 0;
      }
      unchecked {
        ++i;
      }
    }

    // Send slices to beneficiaries along with any earnings
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

    // Add reference to contributions for msg.sender
    uint256 contribution = contributions[msg.sender];

    if (contribution != 0) {
      // Update storage
      contributions[msg.sender] = 0;

      // Send slices to beneficiary along with a proportional amount of tokens accrued
      sliceCore.safeTransferFromUnreleased(
        address(this),
        msg.sender,
        slicerId,
        contribution / TOKENS_PER_SLICE,
        ''
      );
    }
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
  ) external virtual override returns (bytes4) {
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
  ) public virtual override returns (bytes4) {
    return this.onERC1155BatchReceived.selector;
  }
}

// Note
// Slices have a max of `type(uint32).max`, so it's necessary to convert between value paid and slices, either during pay / redeem or during slice issuance.

// - Storing the VALUE sent on pay / redeem, and calculate slices during issuance, allows to have the most efficient + seamless logic. However consider an extreme scenario where `totalContributions` > 0 but all contributions are below `TOKENS_PER_SLICE`. This would result in no slices being minted even though the treasury has received money. The problem is present whenever the amount paid doesn't exactly correspond that which should've been contributed to get a number of slices, either in excess or in defect.
// - Designing so that slices are calculated during pay / redeem increases complexity and costs significantly, while adding a bunch of foot guns. I considered going down that road but realised it introduced other issues.
// - Proposed solution uses the former logic, but enforces `(_data.amount.value % TOKENS_PER_SLICE == 0)` so that there is no payment in excess. This will also be enforced on the frontend, but might require JB frontend to eventually adapt as well

// TODO: Add other missing params from interface
