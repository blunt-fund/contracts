// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './helper/BluntSetup.sol';
import 'contracts/BluntDelegate.sol';
import 'contracts/BluntDelegateProjectDeployer.sol';

contract BluntDelegateTest is BluntSetup {
  BluntDelegateProjectDeployer public bluntDeployer;
  BluntDelegate public bluntDelegate;

  uint256 public projectId;

  function setUp() public virtual override {
    BluntSetup.setUp();

    bluntDeployer = new BluntDelegateProjectDeployer(_jbController, _jbOperatorStore);

    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    projectId = bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData);

    bluntDelegate = BluntDelegate(_jbProjects.ownerOf(projectId));
  }

  function testRoundInfo() public {
    RoundInfo memory roundInfo = bluntDelegate.getRoundInfo();

    assertEq(bluntDelegate.projectId(), projectId);
    assertEq(roundInfo.totalContributions, 0);
    assertEq(roundInfo.target, 1 ether);
    assertEq(roundInfo.hardCap, 10 ether);
    assertEq(roundInfo.releaseTimelock, 0);
    assertEq(roundInfo.transferTimelock, 0);
    assertEq(roundInfo.projectOwner, _bluntProjectOwner);
    assertEq(roundInfo.fundingCycleRound, 0);
    assertEq(roundInfo.afterRoundReservedRate, 1000);
    assertBoolEq(roundInfo.afterRoundSplits[0].preferClaimed, true);
    assertEq(roundInfo.afterRoundSplits[0].percent, JBConstants.SPLITS_TOTAL_PERCENT);
    assertEq(roundInfo.afterRoundSplits[0].beneficiary, address(0));
    assertApproxEq(roundInfo.afterRoundSplits[0].lockedUntil, block.timestamp + 2 days, 1);
    assertEq(roundInfo.tokenName, 'tokenName');
    assertEq(roundInfo.tokenSymbol, 'SYMBOL');
    assertBoolEq(roundInfo.isRoundClosed, false);
    assertEq(roundInfo.slicerId, 0);
  }

  function testPayParams() public {
    (
      uint256 weight,
      string memory memo,
      JBPayDelegateAllocation[] memory delegateAllocations
    ) = bluntDelegate.payParams(
        JBPayParamsData({
          terminal: IJBPaymentTerminal(address(0)),
          payer: address(2),
          amount: JBTokenAmount(address(0), 0, 0, 0),
          projectId: 0,
          currentFundingCycleConfiguration: 0,
          beneficiary: address(3),
          weight: 1e3,
          reservedRate: 1e4,
          memo: 'test',
          metadata: ''
        })
      );

    assertEq(weight, 1e3);
    assertEq(memo, 'test');
    assertEq(address(delegateAllocations[0].delegate), address(bluntDelegate));
    assertEq(delegateAllocations[0].amount, 0);
  }

  function testRedeemParams() public {
    (
      uint256 reclaimAmount,
      string memory memo,
      JBRedemptionDelegateAllocation[] memory delegateAllocations
    ) = bluntDelegate.redeemParams(
        JBRedeemParamsData({
          terminal: IJBPaymentTerminal(address(0)),
          holder: address(2),
          projectId: 0,
          currentFundingCycleConfiguration: 0,
          tokenCount: 0,
          totalSupply: 0,
          overflow: 0,
          reclaimAmount: JBTokenAmount(address(0), 1e3, 0, 0),
          useTotalOverflow: false,
          redemptionRate: 0,
          memo: 'test',
          metadata: ''
        })
      );

    assertEq(reclaimAmount, 1e3);
    assertEq(memo, 'test');
    assertEq(address(delegateAllocations[0].delegate), address(bluntDelegate));
    assertEq(delegateAllocations[0].amount, 0);
  }
}
