// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@jbx-protocol/juice-contracts-v3/contracts/JBController3_1.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBDirectory.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBETHPaymentTerminal3_1.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBERC20PaymentTerminal.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBSingleTokenPaymentTerminalStore3_1.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBFundingCycleStore.sol';
import "@jbx-protocol/juice-contracts-v3/contracts/JBFundAccessConstraintsStore.sol";
import '@jbx-protocol/juice-contracts-v3/contracts/JBOperatorStore.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBPrices.sol';
import {JBProjects} from '@jbx-protocol/juice-contracts-v3/contracts/JBProjects.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBSplitsStore.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBToken.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBTokenStore.sol';

import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidPayData.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidRedeemData.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBFee.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundAccessConstraints.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycle.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleData.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBGroupedSplits.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBOperatorData.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayParamsData.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedeemParamsData.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol';

import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBToken.sol';

import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBFundingCycleMetadataResolver.sol';

import {DSTestPlus} from 'solmate/test/utils/DSTestPlus.sol';
import 'forge-std/console2.sol';

import './AccessJBLib.sol';
import '../structs/JBPayDataSourceFundingCycleMetadata.sol'; 
import '../../contracts/structs/DeployBluntDelegateData.sol';
import '../../contracts/structs/JBLaunchProjectData.sol';
import 'contracts/interfaces/IPriceFeed.sol';
import 'contracts/interfaces/IJBDelegatesRegistry.sol';
import '../mocks/PriceFeedMock.sol';
import '../mocks/ReceiverMock.sol';
import '../mocks/JBDelegatesRegistryMock.sol';

// Base contract for Juicebox system tests.
//
// Provides common functionality, such as deploying contracts on test setup.
contract BluntSetup is DSTestPlus {
  //*********************************************************************//
  // --------------------- internal stored properties ------------------- //
  //*********************************************************************//

  address internal _bluntOwner = address(123456);
  uint256 internal _bluntProjectId;
  address internal _projectOwner = address(123);
  address internal _beneficiary = address(69420);
  address internal _caller = address(696969);
  uint88 internal _hardcap = 10 ether;
  uint88 internal _target = 1 ether;
  uint40 internal _releaseTimelock = 1;
  uint40 internal _transferTimelock = 2;
  uint256 internal _lockPeriod = 2 days;
  string internal _tokenName = 'tokenName';
  string internal _tokenSymbol = 'SYMBOL';
  bool internal _isTargetUsd = false;
  bool internal _isHardcapUsd = false;
  uint256 internal _maxK = 350;
  uint256 internal _minK = 150;
  uint256 internal _upperFundraiseBoundary = 2e13;
  uint256 internal _lowerFundraiseBoundary = 1e11;
  uint256 internal _weight = 1e15;

  address internal _bluntProjectOwner = address(bytes20(keccak256('bluntProjectOwner')));
  IJBDelegatesRegistry internal _registry;
  IPriceFeed internal _priceFeed = IPriceFeed(0x71c96edD5D36935d5c8d6B78bCcD4113725297e3);
  ReceiverMock internal _receiver;

  JBOperatorStore internal _jbOperatorStore;
  JBProjects internal _jbProjects;
  JBPrices internal _jbPrices;
  JBDirectory internal _jbDirectory;
  JBFundingCycleStore internal _jbFundingCycleStore;
  JBTokenStore internal _jbTokenStore;
  JBSplitsStore internal _jbSplitsStore;
  JBController3_1 internal _jbController;
  JBFundAccessConstraintsStore internal _jbFundAccessConstraintsStore;
  JBSingleTokenPaymentTerminalStore3_1 internal _jbPaymentTerminalStore;
  JBETHPaymentTerminal3_1 internal _jbETHPaymentTerminal;
  JBProjectMetadata internal _projectMetadata;
  JBFundingCycleData internal _data;
  JBPayDataSourceFundingCycleMetadata internal _metadata;
  JBGroupedSplits[] internal _groupedSplits;
  JBFundAccessConstraints[] internal _fundAccessConstraints;
  IJBPaymentTerminal[] internal _terminals;
  IJBToken internal _tokenV2;

  AccessJBLib internal _accessJBLib;

  //*********************************************************************//
  // --------------------------- test setup ---------------------------- //
  //*********************************************************************//

  // Deploys and initializes contracts for testing.
  function setUp() public virtual {
    // ---- Set up project ----
    _jbOperatorStore = new JBOperatorStore();
    hevm.label(address(_jbOperatorStore), 'JBOperatorStore');

    _jbProjects = new JBProjects(_jbOperatorStore);
    hevm.label(address(_jbProjects), 'JBProjects');

    _jbPrices = new JBPrices(_projectOwner);
    hevm.label(address(_jbPrices), 'JBPrices');

    address contractAtNoncePlusOne = _addressFrom(address(this), 5);

    _jbFundingCycleStore = new JBFundingCycleStore(IJBDirectory(contractAtNoncePlusOne));
    hevm.label(address(_jbFundingCycleStore), 'JBFundingCycleStore');

    _jbDirectory = new JBDirectory(
      _jbOperatorStore,
      _jbProjects,
      _jbFundingCycleStore,
      _projectOwner
    );
    hevm.label(address(_jbDirectory), 'JBDirectory');

    _jbTokenStore = new JBTokenStore(
      _jbOperatorStore,
      _jbProjects,
      _jbDirectory,
      _jbFundingCycleStore
    );
    hevm.label(address(_jbTokenStore), 'JBTokenStore');

    _jbSplitsStore = new JBSplitsStore(_jbOperatorStore, _jbProjects, _jbDirectory);
    hevm.label(address(_jbSplitsStore), 'JBSplitsStore');

    _jbFundAccessConstraintsStore = new JBFundAccessConstraintsStore(_jbDirectory);

    _jbController = new JBController3_1(
      _jbOperatorStore,
      _jbProjects,
      _jbDirectory,
      _jbFundingCycleStore,
      _jbTokenStore,
      _jbSplitsStore,
      _jbFundAccessConstraintsStore
    );
    hevm.label(address(_jbController), 'JBController3_1');

    hevm.prank(_projectOwner);
    _jbDirectory.setIsAllowedToSetFirstController(address(_jbController), true);

    _jbPaymentTerminalStore = new JBSingleTokenPaymentTerminalStore3_1(
      _jbDirectory,
      _jbFundingCycleStore,
      _jbPrices
    );
    hevm.label(address(_jbPaymentTerminalStore), 'JBSingleTokenPaymentTerminalStore3_1');

    _accessJBLib = new AccessJBLib();

    _jbETHPaymentTerminal = new JBETHPaymentTerminal3_1(
      _accessJBLib.ETH(),
      _jbOperatorStore,
      _jbProjects,
      _jbDirectory,
      _jbSplitsStore,
      _jbPrices,
      _jbPaymentTerminalStore,
      _projectOwner
    );
    hevm.label(address(_jbETHPaymentTerminal), 'JBETHPaymentTerminal3_1');

    _terminals.push(_jbETHPaymentTerminal);

    _projectMetadata = JBProjectMetadata({content: 'myIPFSHash', domain: 1});

    _data = JBFundingCycleData({
      duration: 7 days,
      weight: 1e21,
      discountRate: 450000000,
      ballot: IJBFundingCycleBallot(address(0))
    });

    _metadata = JBPayDataSourceFundingCycleMetadata({
      global: JBGlobalFundingCycleMetadata({
        allowSetTerminals: false,
        allowSetController: false,
        pauseTransfers: false
      }),
      reservedRate: 5000, //50%
      redemptionRate: 5000, //50%
      ballotRedemptionRate: 5000,
      pausePay: false,
      pauseDistributions: false,
      pauseRedeem: false,
      pauseBurn: false,
      allowMinting: true,
      allowTerminalMigration: false,
      allowControllerMigration: false,
      holdFees: false,
      preferClaimedTokenOverride: false,
      useTotalOverflowForRedemptions: false,
      useDataSourceForRedeem: true,
      metadata: 0x00
    });

    // ---- Deploy BF Project ----
    _bluntProjectId = _jbController.launchProjectFor(
      _bluntOwner,
      _projectMetadata,
      _data,
      JBFundingCycleMetadata({
        global: JBGlobalFundingCycleMetadata({
          allowSetTerminals: false,
          allowSetController: false,
          pauseTransfers: false
        }),
        reservedRate: 0,
        redemptionRate: 0,
        ballotRedemptionRate: 0,
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
        useDataSourceForPay: false,
        useDataSourceForRedeem: false,
        dataSource: address(0),
        metadata: 0
      }),
      0,
      new JBGroupedSplits[](0),
      new JBFundAccessConstraints[](0),
      _terminals,
      ''
    );

    // ---- Deploy JBDelegatesRegistry ----
    _registry = IJBDelegatesRegistry(new JBDelegatesRegistryMock());

    // ---- Deploy Price Feed Mock ----
    PriceFeedMock priceFeedMock = new PriceFeedMock();
    hevm.etch(0x71c96edD5D36935d5c8d6B78bCcD4113725297e3, address(priceFeedMock).code);
    hevm.label(address(priceFeedMock), 'Price Feed');

    // ---- Deploy Receiver Mock ----
    _receiver = new ReceiverMock();
    hevm.label(address(_receiver), 'Receiver');

    // ---- general setup ----
    hevm.deal(_beneficiary, 100 ether);
    hevm.deal(_projectOwner, 100 ether);
    hevm.deal(_caller, 100 ether);

    hevm.label(_projectOwner, 'projectOwner');
    hevm.label(_beneficiary, 'beneficiary');
    hevm.label(_caller, 'caller');
  }

  //https://ethereum.stackexchange.com/questions/24248/how-to-calculate-an-ethereum-contracts-address-during-its-creation-using-the-so
  function _addressFrom(address _origin, uint256 _nonce) internal pure returns (address _address) {
    bytes memory data;
    if (_nonce == 0x00) data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80));
    else if (_nonce <= 0x7f)
      data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, uint8(_nonce));
    else if (_nonce <= 0xff)
      data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), _origin, bytes1(0x81), uint8(_nonce));
    else if (_nonce <= 0xffff)
      data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), _origin, bytes1(0x82), uint16(_nonce));
    else if (_nonce <= 0xffffff)
      data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), _origin, bytes1(0x83), uint24(_nonce));
    else data = abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce));
    bytes32 hash = keccak256(data);
    assembly {
      mstore(0, hash)
      _address := mload(0)
    }
  }

  function _formatDeployData()
    internal
    view
    returns (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    )
  {
    deployBluntDelegateData = DeployBluntDelegateData(
      _jbDirectory,
      _bluntProjectOwner,
      _hardcap,
      _target,
      _isTargetUsd,
      _isHardcapUsd,
      _tokenName,
      _tokenSymbol
    );

    IJBPaymentTerminal[] memory terminals = new IJBPaymentTerminal[](1);
    terminals[0] = IJBPaymentTerminal(_jbETHPaymentTerminal);

    launchProjectData = JBLaunchProjectData(
      JBProjectMetadata({content: '', domain: 0}),
      JBFundingCycleData({
        duration: 7 days,
        weight: _weight, // 0.001 tokens per ETH contributed
        discountRate: 0,
        ballot: IJBFundingCycleBallot(address(0))
      }),
      JBFundingCycleMetadata({
        global: JBGlobalFundingCycleMetadata({
          allowSetTerminals: false,
          allowSetController: false,
          pauseTransfers: false
        }),
        reservedRate: 0,
        redemptionRate: 0,
        ballotRedemptionRate: 0,
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
        useDataSourceForPay: false,
        useDataSourceForRedeem: false,
        dataSource: address(0),
        metadata: 0
      }),
      0, // mustStartAtOrAfter
      new JBGroupedSplits[](0),
      new JBFundAccessConstraints[](0),
      terminals,
      '' // memo
    );
  }
  
  /**
    @notice
    Helper function to calculate blunt fee based on raised amount.
  */
  function _calculateFee(uint256 raised) internal view returns (uint256 fee) {
    unchecked {
      uint256 raisedUsd = _priceFeed.getQuote(uint128(raised), address(uint160(uint256(keccak256('eth')))), address(0), 30 minutes);
      uint256 k;
      if (raisedUsd < _lowerFundraiseBoundary) {
        k = _maxK;
      } else if (raisedUsd > _upperFundraiseBoundary) {
        k = _minK;
      } else {
        // prettier-ignore
        k = _maxK - (
          ((_maxK - _minK) * (raisedUsd - _lowerFundraiseBoundary)) /
          (_upperFundraiseBoundary - _lowerFundraiseBoundary)
        );
      }

      fee = (k * raised) / 10000;
    }
  }
}