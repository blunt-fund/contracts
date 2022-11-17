// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './helper/BluntSetup.sol';
import 'contracts/BluntDelegate.sol';
import 'contracts/BluntDelegateProjectDeployer.sol';

contract BluntDelegateTest is BluntSetup {
  BluntDelegateProjectDeployer public bluntDeployer;
  BluntDelegate public bluntDelegate;

  address public constant user = address(69);
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
    hevm.deal(user, 1e21);
    hevm.deal(_bluntProjectOwner, 1e21);
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
    assertEq(roundInfo.fundingCycleRound, 1);
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

  function testDidPay() public {
    uint256 amount = 1e15;
    uint256 mintedTokens = _jbETHPaymentTerminal.pay{value: amount}(
      projectId,
      0,
      address(0),
      msg.sender,
      0,
      false,
      '',
      ''
    );

    assertEq(mintedTokens, 1e12);
    assertEq(uint256(bluntDelegate.totalContributions()), amount);
    assertEq(bluntDelegate.contributions(msg.sender), amount);
  }

  function testDidRedeem() public {
    hevm.startPrank(user);

    uint256 amount = 1e18;
    uint256 mintedTokens = _jbETHPaymentTerminal.pay{value: amount}(
      projectId,
      0,
      address(0),
      user,
      0,
      false,
      '',
      ''
    );

    uint256 tokensReturned = 1e14;
    uint256 reclaimAmount = _jbETHPaymentTerminal.redeemTokensOf(
      user,
      projectId,
      tokensReturned,
      address(0),
      tokensReturned,
      payable(user),
      '',
      ''
    );

    hevm.stopPrank();

    assertEq(mintedTokens, 1e15);
    assertEq(reclaimAmount, 1e17);
    assertEq(uint256(bluntDelegate.totalContributions()), 9e17);
    assertEq(bluntDelegate.contributions(user), 9e17);
  }

  function testQueueNextPhase() public {
    hevm.warp(100);
    bluntDelegate.queueNextPhase();

    (JBFundingCycle memory fundingCycle, , ) = _jbController.latestConfiguredFundingCycleOf(
      projectId
    );

    assertEq(fundingCycle.duration, 0);
    assertEq(fundingCycle.weight, 0);
    assertEq(fundingCycle.discountRate, 0);
    assertEq(address(fundingCycle.ballot), address(0));
  }

  function testcloseRoundBelowTarget() public {
    uint256 amount = 1e17;
    _jbETHPaymentTerminal.pay{value: amount}(
      projectId,
      0,
      address(0),
      msg.sender,
      0,
      false,
      '',
      ''
    );

    hevm.startPrank(_bluntProjectOwner);
    bluntDelegate.closeRound();
    hevm.stopPrank();

    assertBoolEq(bluntDelegate.isRoundClosed(), true);
  }

  function testcloseRoundAboveTarget() public {
    address currency = address(_jbTokenStore.tokenOf(projectId));
    uint256 slicerId = bluntDelegate.slicerId();
    assertTrue(currency == address(0));
    assertTrue(slicerId == 0);
    assertTrue(_sliceCore.balanceOf(address(bluntDelegate), slicerId) == 0);

    uint256 amount = 1e18;
    _jbETHPaymentTerminal.pay{value: amount}(
      projectId,
      0,
      address(0),
      msg.sender,
      0,
      false,
      '',
      ''
    );

    uint256 totalContributions= bluntDelegate.totalContributions();
    hevm.warp(100);
    hevm.startPrank(_bluntProjectOwner);
    bluntDelegate.closeRound();
    hevm.stopPrank();

    // Wait for the funding cycle to end
    hevm.warp(7 days + 100);

    (JBFundingCycle memory fundingCycle, JBFundingCycleMetadata memory metadata) = _jbController
      .currentFundingCycleOf(projectId);
    address owner = _jbProjects.ownerOf(projectId);
    currency = address(_jbTokenStore.tokenOf(projectId));

    assertBoolEq(bluntDelegate.isRoundClosed(), true);

    assertEq(metadata.reservedRate, _afterRoundReservedRate);
    assertEq(metadata.redemptionRate, 0);
    assertBoolEq(metadata.global.pauseTransfers, false);
    assertBoolEq(metadata.pausePay, true);
    assertBoolEq(metadata.useDataSourceForPay, false);
    assertBoolEq(metadata.useDataSourceForRedeem, false);
    assertEq(metadata.dataSource, address(0));
    
    assertEq(fundingCycle.duration, 0);
    assertEq(fundingCycle.weight, 1e24);
    assertEq(fundingCycle.discountRate, 0);
    assertEq(address(fundingCycle.ballot), address(0));
    
    assertEq(owner, address(_bluntProjectOwner));

    assertTrue(currency != address(0));

    slicerId = bluntDelegate.slicerId();
    assertTrue(slicerId != 0);
    assertTrue(_sliceCore.balanceOf(address(bluntDelegate), slicerId) == totalContributions / 1e15);

    // TODO: Figure out why splits don't work. 
    // Did I set them wrong in the contracts, or am I retrieving them wrong in the tests?
    // 
    // JBSplit[] memory splits = _jbSplitsStore.splitsOf(projectId, 1, 2);
    // assertEq(splits.length, 1);
    // assertBoolEq(address(splits[0].beneficiary) != address(0));
    // assertBoolEq(splits[0].preferClaimed, true);
  }

  ///////////////////////////////////////
  /////////////// REVERTS ///////////////
  ///////////////////////////////////////

  function testRevert_didPay_valueNotExact() public {
    uint256 amount = 1e18 + 1e14;

    hevm.expectRevert(bytes4(keccak256('VALUE_NOT_EXACT()')));
    _jbETHPaymentTerminal.pay{value: amount}(
      projectId,
      0,
      address(0),
      msg.sender,
      0,
      false,
      '',
      ''
    );
  }

  function testRevert_didPay_capReached() public {
    uint256 amount = 1e19 + 1e15;

    hevm.expectRevert(bytes4(keccak256('CAP_REACHED()')));
    _jbETHPaymentTerminal.pay{value: amount}(
      projectId,
      0,
      address(0),
      msg.sender,
      0,
      false,
      '',
      ''
    );
  }

  function testRevert_didRedeem_valueNotExact() public {
    hevm.startPrank(user);

    uint256 amount = 1e18;
    _jbETHPaymentTerminal.pay{value: amount}(
      projectId,
      0,
      address(0),
      user,
      0,
      false,
      '',
      ''
    );

    uint256 tokensReturned = 1e11; // corresponds to 1e14 wei
    hevm.expectRevert(bytes4(keccak256('VALUE_NOT_EXACT()')));
    _jbETHPaymentTerminal.redeemTokensOf(
      user,
      projectId,
      tokensReturned,
      address(0),
      tokensReturned,
      payable(user),
      '',
      ''
    );
    hevm.stopPrank();
  }

  function testRevert_queueNextPhase_alreadyQueued() public {
    hevm.warp(100);
    bluntDelegate.queueNextPhase();
    hevm.expectRevert(bytes4(keccak256('ALREADY_QUEUED()')));
    bluntDelegate.queueNextPhase();
  }

  function testRevert_queueNextPhase_noNeedToQueue() public {
    (
      DeployBluntDelegateData memory deployBluntDelegateData_,
      JBLaunchProjectData memory launchProjectData_
    ) = _formatDeployData();

    launchProjectData_.data = JBFundingCycleData(0, 1e15, 0, IJBFundingCycleBallot(address(0)));

    uint256 projectId_ = bluntDeployer.launchProjectFor(
      deployBluntDelegateData_,
      launchProjectData_
    );
    BluntDelegate bluntDelegate_ = BluntDelegate(_jbProjects.ownerOf(projectId_));

    hevm.warp(100);
    hevm.expectRevert(bytes4(keccak256('ALREADY_QUEUED()')));
    bluntDelegate_.queueNextPhase();
  }

  function testRevert_closeRound_notProjectOwner() public {
    hevm.expectRevert(bytes4(keccak256('NOT_PROJECT_OWNER()')));
    bluntDelegate.closeRound();
  }

  function testRevert_closeRound_roundClosed() public {
    hevm.startPrank(_bluntProjectOwner);
    bluntDelegate.closeRound();

    hevm.expectRevert(bytes4(keccak256('ROUND_CLOSED()')));
    bluntDelegate.closeRound();
    hevm.stopPrank();
  }
}
