// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import 'contracts/BluntDelegateProjectDeployer.sol';
import 'contracts/BluntDelegateDeployer.sol';
import 'contracts/BluntDelegateCloner.sol';
import 'contracts/interfaces/IBluntDelegateDeployer.sol';
import 'contracts/interfaces/IBluntDelegateCloner.sol';

contract ForkTest is Test {
  BluntDelegateProjectDeployer public bluntDeployer;
  IBluntDelegateDeployer public delegateDeployer;
  IBluntDelegateCloner public delegateCloner;

  function testLaunchProject() public {
    string memory MAINNET_RPC_URL = vm.envString("RPC_URL_MAINNET");
    vm.createSelectFork(MAINNET_RPC_URL, 16728933);

    delegateDeployer = new BluntDelegateDeployer();
    delegateCloner = new BluntDelegateCloner();

    bluntDeployer = new BluntDelegateProjectDeployer(
      address(this),
      delegateDeployer,
      delegateCloner,
      IJBController3_1(0x97a5b9D9F0F7cD676B69f584F29048D0Ef4BB59b), // controller3_1
      433,
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

    bluntDeployer.launchProjectFor(
      deployBluntDelegateData,
      launchProjectData,
      true
    );
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
      address(this),
      0,
      0,
      1000,
      new JBSplit[](0),
      false,
      false
    );

    IJBPaymentTerminal[] memory terminals = new IJBPaymentTerminal[](1);
    terminals[0] = IJBPaymentTerminal(0x0baCb87Cf7DbDdde2299D92673A938E067a9eb29);

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
}
