// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import 'forge-std/Test.sol';
import 'contracts/BluntDelegateProjectDeployer.sol';
import 'contracts/BluntDelegateCloner.sol';
import 'contracts/interfaces/IBluntDelegateDeployer.sol';
import 'contracts/interfaces/IBluntDelegateCloner.sol';
import 'contracts/interfaces/IJBDelegatesRegistry.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBETHPaymentTerminal3_1.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBTokenStore.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBController3_1.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBFundingCycleStore.sol';
import {JBProjects} from '@jbx-protocol/juice-contracts-v3/contracts/JBProjects.sol';

contract ForkTest is Test {
  BluntDelegateProjectDeployer public bluntDeployer  = BluntDelegateProjectDeployer(0x1d6b0Ff3D522C3870294a9e2948beb18994561dE);
  IBluntDelegateCloner public delegateCloner = BluntDelegateCloner(0x2123c29B76EcEb8bB0893724f64F561ccFB38FAb);
  JBETHPaymentTerminal3_1 internal jbETHPaymentTerminal = JBETHPaymentTerminal3_1(0xFA391De95Fcbcd3157268B91d8c7af083E607A5C);
  JBProjects internal jbProjects = JBProjects(0xD8B4359143eda5B2d763E127Ed27c77addBc47d3);
  JBTokenStore internal jbTokenStore = JBTokenStore(0x6FA996581D7edaABE62C15eaE19fEeD4F1DdDfE7);
  JBController3_1 internal jbController = JBController3_1(0x97a5b9D9F0F7cD676B69f584F29048D0Ef4BB59b);
  JBFundingCycleStore internal jbFundingCycleStore = JBFundingCycleStore(0x6f18cF9173136c0B5A6eBF45f19D58d3ff2E17e6);
  IPriceFeed internal priceFeed = IPriceFeed(0x71c96edD5D36935d5c8d6B78bCcD4113725297e3);
  BluntDelegateClone public bluntDelegate;
  address projectOwner = makeAddr('projectOwner');

  uint256 internal _maxK = 350;
  uint256 internal _minK = 150;
  uint256 internal _upperFundraiseBoundary = 2e13;
  uint256 internal _lowerFundraiseBoundary = 1e11;
  uint256 internal _weight = 1e15;

  function setUp() public {
    string memory MAINNET_RPC_URL = vm.envString('RPC_URL_MAINNET');
    vm.createSelectFork(MAINNET_RPC_URL, 17243897);

    delegateCloner;
    bluntDeployer;
    jbETHPaymentTerminal;
    jbProjects;
    jbTokenStore;
    jbController;
    jbFundingCycleStore;
    priceFeed;
  }

  function testLaunchProject() public {
    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData);
  }

  function testCloseRoundSuccessfully() public {
    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    uint256 projectId = bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData);
    bluntDelegate = BluntDelegateClone(jbProjects.ownerOf(projectId));
    
    uint256 amount = 1e15;
    jbETHPaymentTerminal.pay{value: amount}(
      projectId,
      0,
      address(0),
      msg.sender,
      0,
      false,
      '',
      ''
    );
    uint256 initBfBalance = IJBSingleTokenPaymentTerminalStore(jbETHPaymentTerminal.store()).balanceOf(
      jbETHPaymentTerminal,
      490 // bluntProjectId
    );

    uint256 totalContributions = bluntDelegate.getRoundInfo().totalContributions;
    vm.warp(block.timestamp + 7 days);
    vm.prank(projectOwner);
    bluntDelegate.closeRound();

    assertTrue(bluntDelegate.getRoundInfo().isRoundClosed);

    vm.warp(block.timestamp + 100);

    _successfulRoundAssertions(projectId, block.timestamp, totalContributions,initBfBalance);

    address currency = address(jbTokenStore.tokenOf(projectId));
    assertTrue(currency != address(0));
  }

  function testLaunchProject_newContracts() public {
    delegateCloner = new BluntDelegateCloner(
      IJBDelegatesRegistry(0x7A53cAA1dC4d752CAD283d039501c0Ee45719FaC)
    );

    bluntDeployer = new BluntDelegateProjectDeployer(
      address(this),
      delegateCloner,
      IJBController3_1(0x97a5b9D9F0F7cD676B69f584F29048D0Ef4BB59b), // controller3_1
      490,
      0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // eth
      0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // usdc
      350, // maxK, 3.5%
      150, // minK, 1.5%
      2e13, // upperFundraiseBoundary, $20M
      1e11 // lowerFundraiseBoundary, $100k
    );

    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData);
  }

  function _formatDeployData()
    internal
    view
    returns (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    )
  {
    JBSplit[] memory _afterRoundSplits = new JBSplit[](2);
    _afterRoundSplits[0] = JBSplit({
      preferClaimed: false,
      preferAddToBalance: false,
      percent: JBConstants.SPLITS_TOTAL_PERCENT - 1000,
      projectId: 0,
      beneficiary: payable(address(0)),
      lockedUntil: block.timestamp + 1e3,
      allocator: IJBSplitAllocator(address(0))
    });
    _afterRoundSplits[1] = JBSplit({
      preferClaimed: false,
      preferAddToBalance: false,
      percent: 1000,
      projectId: 0,
      beneficiary: payable(address(1)),
      lockedUntil: 0,
      allocator: IJBSplitAllocator(address(0))
    });

    deployBluntDelegateData = DeployBluntDelegateData(
      IJBDirectory(0x65572FB928b46f9aDB7cfe5A4c41226F636161ea),
      projectOwner,
      0,
      0,
      false,
      false,
      'Blunt',
      'BLUNT'
    );

    IJBPaymentTerminal[] memory terminals = new IJBPaymentTerminal[](1);
    terminals[0] = IJBPaymentTerminal(jbETHPaymentTerminal);

    launchProjectData = JBLaunchProjectData(
      JBProjectMetadata({content: '', domain: 0}),
      JBFundingCycleData({
        duration: 7 days,
        weight: 1e15, // 0.001 tokens per ETH contributed
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

  function _successfulRoundAssertions(
    uint256 projectId_,
    uint256 timestamp_,
    uint256 totalContributions_,
    uint256 initBfBalance_
  ) internal returns (JBFundingCycle memory fundingCycle, JBFundingCycleMetadata memory metadata) {
    (fundingCycle, metadata) = jbController.currentFundingCycleOf(projectId_);

    assertEq(fundingCycle.duration, 0);
    assertEq(fundingCycle.weight, _weight);
    assertEq(fundingCycle.discountRate, 0);
    assertEq(address(fundingCycle.ballot), address(0));
    assertTrue(metadata.pauseRedeem);
    assertEq(metadata.redemptionRate, 0);
    assertFalse(metadata.global.pauseTransfers);
    assertTrue(metadata.pausePay);
    assertFalse(metadata.pauseDistributions);
    assertFalse(metadata.useDataSourceForPay);
    assertFalse(metadata.useDataSourceForRedeem);
    assertEq(metadata.dataSource, address(0));

    // Blunt fee logic
    uint256 bluntFee = _calculateFee(totalContributions_);
    (uint256 distributionLimit, ) = jbController.fundAccessConstraintsStore().distributionLimitOf(
      projectId_,
      jbFundingCycleStore.latestConfigurationOf(projectId_),
      jbETHPaymentTerminal,
      0x000000000000000000000000000000000000EEEe
    );
    uint256 projectBalance = IJBSingleTokenPaymentTerminalStore(jbETHPaymentTerminal.store())
      .balanceOf(jbETHPaymentTerminal, projectId_);
    uint256 bfBalance = IJBSingleTokenPaymentTerminalStore(jbETHPaymentTerminal.store()).balanceOf(
      jbETHPaymentTerminal,
      490 // bluntProjectId
    );
    assertEq(distributionLimit, bluntFee);
    assertEq(projectBalance, totalContributions_ - bluntFee);
    assertEq(bfBalance-initBfBalance_, bluntFee);

    address owner = jbProjects.ownerOf(projectId_);
    assertEq(owner, projectOwner);
  }
  
  /**
    @notice
    Helper function to calculate blunt fee based on raised amount.
  */
  function _calculateFee(uint256 raised) internal view returns (uint256 fee) {
    unchecked {
      uint256 raisedUsd = priceFeed.getQuote(uint128(raised), address(uint160(uint256(keccak256('eth')))), address(0), 30 minutes);
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
