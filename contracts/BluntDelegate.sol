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
  error SLICER_ALREADY_CREATED();
  error SLICER_NOT_YET_CREATED();

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

  //*********************************************************************//
  // -------------------------- Slice storage -------------------------- //
  //*********************************************************************//

  /// Total slices to be minted when round closes.
  uint32 private slicesToMint;
  /// Mapping from beneficiary's address to number of slices to claim.
  mapping(address => uint32) private slicesToClaim;
  /// Ratio between amount of tokens paid and slices minted;
  uint256 private constant TOKENS_PER_SLICE = 10**15; // 1 slice every 0.001 ETH
  /// ID of the slicer related to the blunt round.
  /// @dev Assumes ID 0 is not created, since it's generally taken by the protocol.
  uint256 private slicerId;

  //*********************************************************************//
  // -------------------- Network-specific storage --------------------- //
  //*********************************************************************//

  // MAINNET
  // address private constant _sliceCoreAddress = 0x21da1b084175f95285B49b22C018889c45E1820d;

  // RINKEBY TESTNET
  address private constant _sliceCoreAddress = 0xA86830240122455343171Ab54b9896896C7C8a6F;

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
    uint256 _hardCap,
    uint256 _target,
    uint40 _releaseTimelock,
    uint40 _transferTimelock
  ) {
    projectId = _projectId;
    directory = _directory;
    tokenStore = _tokenStore;
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
    Part of IJBPayDelegate, this function gets called when the project receives a payment. It will update storage for the NFT mint if conditions are met.

    @dev 
    This function will revert if the contract calling is not one of the project's terminals. 

    @param _data The Juicebox standard project payment data.
  */
  function didPay(JBDidPayData calldata _data) external virtual override {
    // Make sure the caller is a terminal of the project, and the call is being made on behalf of an interaction with the correct project.
    if (
      !directory.isTerminalOf(projectId, IJBPaymentTerminal(msg.sender)) ||
      _data.projectId != projectId
    ) revert INVALID_PAYMENT_EVENT();

    // Make sure the token supply is under the cap.
    if (hardCap != 0 && tokenStore.totalSupplyOf(_data.projectId) > hardCap) revert CAP_REACHED();

    // Update storage with the number of slices claimable by beneficiary and to be minted in total
    uint32 slicesAmount = uint32(_data.amount.value / TOKENS_PER_SLICE);
    slicesToMint += slicesAmount;

    // Cannot overflow as slicesToMint would overflow first
    unchecked {
      slicesToClaim[_data.beneficiary] += slicesAmount;
    }
  }

  /**
    @notice 
    Part of IJBRedemptionDelegate, this function gets called when the beneficiary redeems tokens. It will update storage for the NFT mint.

    @dev 
    This function will revert if the contract calling is not one of the project's terminals. 

    @param _data The Juicebox standard project payment data.
  */
  function didRedeem(JBDidRedeemData calldata _data) external virtual override {
    // TODO: Check logic
    // Make sure the caller is a terminal of the project, and the call is being made on behalf of an interaction with the correct project.
    if (
      !directory.isTerminalOf(projectId, IJBPaymentTerminal(msg.sender)) ||
      _data.projectId != projectId
    ) revert INVALID_PAYMENT_EVENT();

    // TODO: Can I this be safely put into an unchecked block? Should never underflow
    // Cannot underflow as `slicesAmount` cannot be higher than `slicesToClaim[_data.beneficiary]`
    unchecked {
      // Update storage with the number of slices claimable by beneficiary and to be minted in total
      uint32 slicesAmount = uint32(_data.reclaimedAmount.value / TOKENS_PER_SLICE);
      slicesToMint -= slicesAmount;
      slicesToClaim[_data.beneficiary] -= slicesAmount;
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
    // TODO: Add requirement: Revert if current funding cycle hasn't ended

    // TODO: Issue ERC20 and get address

    // Add references for sliceParams
    Payee[] memory payees = new Payee[](1);
    payees[0] = Payee(address(this), slicesToMint, true);
    address[] memory currencies = new address[](1);
    currencies[0] = address(0); // TODO: Add token currency address in place of address(0)

    // Create slicer and mint all slices to this address
    ISliceCore(_sliceCoreAddress).slice(
      SliceParams(
        payees,
        slicesToMint,
        currencies,
        releaseTimelock,
        transferTimelock,
        address(0),
        0,
        0
      )
    );

    slicerId = ISliceCore(_sliceCoreAddress).supply();
  }

  /**
    @notice 
    Transfer any unclaimed slices to `beneficiaries` in batch.

    @dev 
    This function will revert if the slicer hasn't been created yet.
  */
  function transferUnclaimedSlicesTo(address[] calldata beneficiaries) external override {
    if (slicerId == 0) revert SLICER_NOT_YET_CREATED();
    // TODO: Add requirement: Revert if current funding cycle hasn't ended

    // Add reference for slices amounts of each beneficiary
    uint256[] memory amounts = new uint256[](beneficiaries.length);
    // Add reference for slicesAmount of each beneficiary, used in loop
    uint256 slicesAmount;

    // For each beneficiary
    for (uint256 i; i < beneficiaries.length; ) {
      // Add reference for amount of slices to claim
      slicesAmount = slicesToClaim[beneficiaries[i]];
      if (slicesAmount != 0) {
        // Set the beneficiary amount in amounts array
        amounts[i] = slicesAmount;
        // Set slicesToClaim[beneficiary] to 0
        slicesToClaim[beneficiaries[i]] = 0;
      }
      unchecked {
        ++i;
      }
    }

    // Send slices to beneficiaries along with a proportional amount of tokens accrued
    ISliceCore(_sliceCoreAddress).slicerBatchTransfer(
      address(this),
      beneficiaries,
      slicerId,
      amounts,
      false
    );
  }

  /**
    @notice 
    Allows a beneficiary to get any unclaimed slices to itself.

    @dev 
    This function will revert if the slicer hasn't been created yet.
  */
  function claimSlices() external override {
    if (slicerId == 0) revert SLICER_NOT_YET_CREATED();

    // Send slices to beneficiaries along with a proportional amount of tokens accrued
    ISliceCore(_sliceCoreAddress).safeTransferFromUnreleased(
      address(this),
      msg.sender,
      slicerId,
      slicesToClaim[msg.sender],
      ''
    );
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
