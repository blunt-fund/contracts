// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './helper/BluntSetup.sol';
import './mocks/ERC20Mock.sol';
import 'contracts/BluntDelegate.sol';
import 'contracts/BluntDelegateDeployer.sol';
import 'contracts/BluntDelegateCloner.sol';
import 'contracts/BluntDelegateProjectDeployer.sol';
import 'contracts/interfaces/IBluntDelegateDeployer.sol';
import 'contracts/interfaces/IBluntDelegateCloner.sol';

contract BluntDelegateTest is BluntSetup {
  //*********************************************************************//
  // ----------------------------- storage ----------------------------- //
  //*********************************************************************//

  BluntDelegateProjectDeployer public bluntDeployer;
  BluntDelegate public bluntDelegate;

  address public constant user = address(69);
  address public constant user2 = address(420);
  uint256 public projectId;

  //*********************************************************************//
  // ------------------------------ events ----------------------------- //
  //*********************************************************************//

  event RoundCreated(
    DeployBluntDelegateData deployBluntDelegateData,
    uint256 projectId,
    uint256 duration
  );
  event RoundClosed();
  event DeadlineSet(uint256 deadline);

  //*********************************************************************//
  // ------------------------------ setup ------------------------------ //
  //*********************************************************************//

  function setUp() public virtual override {
    BluntSetup.setUp();

    IBluntDelegateDeployer delegateDeployer = new BluntDelegateDeployer();
    IBluntDelegateCloner delegateCloner = new BluntDelegateCloner();

    bluntDeployer = new BluntDelegateProjectDeployer(
      address(this),
      delegateDeployer,
      delegateCloner,
      _jbController,
      _jbOperatorStore,
      _bluntProjectId,
      address(uint160(uint256(keccak256('eth')))),
      address(uint160(uint256(keccak256('usdc')))),
      uint16(_maxK),
      uint16(_minK),
      uint56(_upperFundraiseBoundary),
      uint56(_lowerFundraiseBoundary)
    );

    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    projectId = bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData, _clone);

    bluntDelegate = BluntDelegate(_jbProjects.ownerOf(projectId));
    hevm.deal(user, 1e30);
    hevm.deal(user2, 1e30);
    hevm.deal(_bluntProjectOwner, 1e30);
  }

  //*********************************************************************//
  // ------------------------------ tests ------------------------------ //
  //*********************************************************************//

  function testConstructor() public {
    assertEq(bluntDelegate.projectId(), projectId);
    assertEq(bluntDelegate.bluntProjectId(), _bluntProjectId);
    assertEq(bluntDelegate.MAX_K(), _maxK);
    assertEq(bluntDelegate.MIN_K(), _minK);
    assertEq(bluntDelegate.UPPER_FUNDRAISE_BOUNDARY_USD(), _upperFundraiseBoundary);
    assertEq(bluntDelegate.LOWER_FUNDRAISE_BOUNDARY_USD(), _lowerFundraiseBoundary);

    (, BluntDelegate bluntDelegateAlt_) = _createDelegateWithoutDeadline();
    RoundInfo memory roundInfo = bluntDelegateAlt_.getRoundInfo();
    assertEq(roundInfo.deadline, 0);
  }

  function testConstructorAcceptsERC721() public {
    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    deployBluntDelegateData.projectOwner = address(_receiver);

    bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData, _clone);
  }

  function testRoundInfo() public {
    RoundInfo memory roundInfo = bluntDelegate.getRoundInfo();

    (, JBLaunchProjectData memory launchProjectData) = _formatDeployData();

    assertEq(roundInfo.totalContributions, 0);
    assertEq(roundInfo.target, _target);
    assertEq(roundInfo.hardcap, _hardcap);
    assertEq(roundInfo.projectOwner, _bluntProjectOwner);
    assertEq(roundInfo.afterRoundReservedRate, _afterRoundReservedRate);
    assertBoolEq(roundInfo.afterRoundSplits[0].preferClaimed, false);
    assertEq(roundInfo.afterRoundSplits[0].percent, JBConstants.SPLITS_TOTAL_PERCENT - 1000);
    assertEq(roundInfo.afterRoundSplits[0].beneficiary, address(0));
    assertEq(roundInfo.afterRoundSplits[1].percent, 1000);
    assertEq(roundInfo.afterRoundSplits[1].beneficiary, address(1));
    assertApproxEq(roundInfo.afterRoundSplits[0].lockedUntil, block.timestamp + 2 days, 1);
    assertBoolEq(roundInfo.isRoundClosed, false);
    assertEq(roundInfo.deadline, block.timestamp + launchProjectData.data.duration);
    assertBoolEq(roundInfo.isTargetUsd, _isTargetUsd);
    assertBoolEq(roundInfo.isHardcapUsd, _isHardcapUsd);
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
    assertEq(uint256(bluntDelegate.getRoundInfo().totalContributions), amount);
    assertEq(bluntDelegate.contributions(msg.sender), amount);
  }

  function testDidPayWithoutDeadline() public {
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateWithoutDeadline();

    uint256 amount = 1e15;
    uint256 mintedTokens = _jbETHPaymentTerminal.pay{value: amount}(
      projectId_,
      0,
      address(0),
      msg.sender,
      0,
      false,
      '',
      ''
    );

    assertEq(mintedTokens, 1e12);
    assertEq(uint256(bluntDelegateAlt_.getRoundInfo().totalContributions), amount);
    assertEq(bluntDelegateAlt_.contributions(msg.sender), amount);
  }

  function testDidPayAcceptsErc1155() public {
    _jbETHPaymentTerminal.pay{value: _target}(
      projectId,
      0,
      address(0),
      address(_receiver),
      0,
      false,
      '',
      ''
    );
  }

  function testDidRedeem() public {
    hevm.startPrank(user);

    uint256 mintedTokens = _jbETHPaymentTerminal.pay{value: _target}(
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
    assertEq(uint256(bluntDelegate.getRoundInfo().totalContributions), 9e17);
    assertEq(bluntDelegate.contributions(user), 9e17);
  }

  function testDidRedeemWhileRoundClosed() public {
    hevm.prank(user);
    uint256 mintedTokens = _jbETHPaymentTerminal.pay{value: _target}(
      projectId,
      0,
      address(0),
      user,
      0,
      false,
      '',
      ''
    );

    hevm.prank(_bluntProjectOwner);

    bluntDelegate.closeRound();

    uint256 tokensReturned = 1e14;
    hevm.prank(user);
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

    assertEq(mintedTokens, 1e15);
    assertEq(reclaimAmount, 1e17);
    assertEq(uint256(bluntDelegate.getRoundInfo().totalContributions), _target);
    assertEq(bluntDelegate.contributions(user), _target - reclaimAmount);
  }

  function testDidRedeemWithoutDeadline() public {
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateWithoutDeadline();

    hevm.startPrank(user);

    uint256 mintedTokens = _jbETHPaymentTerminal.pay{value: _target}(
      projectId_,
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
      projectId_,
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
    assertEq(uint256(bluntDelegateAlt_.getRoundInfo().totalContributions), 9e17);
    assertEq(bluntDelegateAlt_.contributions(user), 9e17);
  }

  function testCloseRoundBelowTarget() public {
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

    hevm.prank(_bluntProjectOwner);
    bluntDelegate.closeRound();

    assertBoolEq(bluntDelegate.getRoundInfo().isRoundClosed, true);

    hevm.warp(100);

    address owner = _jbProjects.ownerOf(projectId);
    assertEq(owner, address(bluntDelegate));
  }

  function testCloseRoundAtZero_NoTarget() public {
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateNoTargetNoCap();

    hevm.warp(100);
    hevm.prank(_bluntProjectOwner);
    bluntDelegateAlt_.closeRound();

    assertBoolEq(bluntDelegateAlt_.getRoundInfo().isRoundClosed, true);

    hevm.warp(100);

    address owner = _jbProjects.ownerOf(projectId_);
    assertEq(owner, address(bluntDelegateAlt_));
  }

  function testCloseRoundSuccessfully_NoTarget() public {
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateNoTargetNoCap();

    uint256 amount = 1e15;
    _jbETHPaymentTerminal.pay{value: amount}(
      projectId_,
      0,
      address(0),
      msg.sender,
      0,
      false,
      '',
      ''
    );

    uint256 totalContributions = bluntDelegateAlt_.getRoundInfo().totalContributions;
    hevm.warp(100);
    hevm.prank(_bluntProjectOwner);
    bluntDelegateAlt_.closeRound();

    uint256 timestamp = block.timestamp;

    assertBoolEq(bluntDelegateAlt_.getRoundInfo().isRoundClosed, true);

    hevm.warp(100);

    _successfulRoundAssertions(projectId_, timestamp, totalContributions);

    JBSplit[] memory splits = _jbSplitsStore.splitsOf({
      _projectId: projectId_,
      _domain: timestamp,
      _group: 2
    });
    assertEq(splits.length, 2);
    assertEq(address(splits[0].beneficiary), address(0));
    assertBoolEq(splits[0].preferClaimed, false);
    assertEq(splits[0].percent, JBConstants.SPLITS_TOTAL_PERCENT - 1000);
    assertTrue(splits[0].lockedUntil != 0);
    assertEq(address(splits[1].beneficiary), address(1));
    assertBoolEq(splits[1].preferClaimed, false);
    assertEq(splits[1].percent, 1000);
    assertEq(splits[1].lockedUntil, 0);
  }

  function testSetDeadline() public {
    (, BluntDelegate bluntDelegateAlt_) = _createDelegateWithoutDeadline();

    RoundInfo memory roundInfo = bluntDelegateAlt_.getRoundInfo();
    assertEq(roundInfo.deadline, 0);

    uint256 deadline_ = block.timestamp + 1e4;
    hevm.prank(_bluntProjectOwner);
    hevm.expectEmit(false, false, false, true);
    emit DeadlineSet(deadline_);
    bluntDelegateAlt_.setDeadline(deadline_);

    RoundInfo memory newRoundInfo = bluntDelegateAlt_.getRoundInfo();
    assertEq(newRoundInfo.deadline, deadline_);
  }

  function testCloseRoundAboveTarget() public {
    uint256 amount = _target + 1e15;
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

    uint256 totalContributions = bluntDelegate.getRoundInfo().totalContributions;

    hevm.warp(7 days + 100);

    hevm.prank(_bluntProjectOwner);
    bluntDelegate.closeRound();

    uint256 timestamp = block.timestamp;

    assertBoolEq(bluntDelegate.getRoundInfo().isRoundClosed, true);

    // Wait for the funding cycle to end
    hevm.warp(7 days + 100);

    _successfulRoundAssertions(projectId, timestamp, totalContributions);

    JBSplit[] memory splits = _jbSplitsStore.splitsOf({
      _projectId: projectId,
      _domain: timestamp,
      _group: 2
    });
    assertEq(splits.length, 2);
    assertEq(address(splits[0].beneficiary), address(0));
    assertBoolEq(splits[0].preferClaimed, false);
    assertEq(splits[0].percent, JBConstants.SPLITS_TOTAL_PERCENT - 1000);
    assertTrue(splits[0].lockedUntil != 0);
    assertEq(address(splits[1].beneficiary), address(1));
    assertBoolEq(splits[1].preferClaimed, false);
    assertEq(splits[1].percent, 1000);
    assertEq(splits[1].lockedUntil, 0);
  }

  function testCalculateFee_lowerBoundary(uint256 amount) public {
    hevm.assume(amount < _lowerFundraiseBoundary / 1200000);
    amount *= 1e15;
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateNoTargetNoCap();

    _jbETHPaymentTerminal.pay{value: amount}(
      projectId_,
      0,
      address(0),
      msg.sender,
      0,
      false,
      '',
      ''
    );

    uint256 totalContributions = bluntDelegateAlt_.getRoundInfo().totalContributions;
    hevm.warp(100);
    hevm.prank(_bluntProjectOwner);
    bluntDelegateAlt_.closeRound();

    uint256 bluntFee = _calculateFee(totalContributions);
    assertEq(bluntFee, (totalContributions * _maxK) / 10000);
  }

  function testCalculateFee_midBoundary() public {
    uint256 amount = (((_lowerFundraiseBoundary + _upperFundraiseBoundary) / 1200000) / 2) * 1e15;
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateNoTargetNoCap();

    _jbETHPaymentTerminal.pay{value: amount}(
      projectId_,
      0,
      address(0),
      msg.sender,
      0,
      false,
      '',
      ''
    );

    uint256 totalContributions = bluntDelegateAlt_.getRoundInfo().totalContributions;
    hevm.warp(100);
    hevm.prank(_bluntProjectOwner);
    bluntDelegateAlt_.closeRound();

    uint256 bluntFee = _calculateFee(totalContributions);
    uint256 k = (_maxK + _minK) / 2;
    assertRelApproxEq(bluntFee, (totalContributions * k) / 10000, 0.005e18);
  }

  function testCalculateFee_upperBoundary(uint256 amount) public {
    amount = bound(amount, (_upperFundraiseBoundary / 1200000) + 1, 4.2e9);
    amount *= 1e15;
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateNoTargetNoCap();

    _jbETHPaymentTerminal.pay{value: amount}(
      projectId_,
      0,
      address(0),
      msg.sender,
      0,
      false,
      '',
      ''
    );

    uint256 totalContributions = bluntDelegateAlt_.getRoundInfo().totalContributions;
    hevm.warp(100);
    hevm.prank(_bluntProjectOwner);
    bluntDelegateAlt_.closeRound();

    uint256 bluntFee = _calculateFee(totalContributions);
    assertEq(bluntFee, (totalContributions * _minK) / 10000);
  }

  function testCalculateFee_linearDecrement(uint256 amount) public {
    amount = bound(
      amount,
      (_lowerFundraiseBoundary / 1200000) + 1,
      _upperFundraiseBoundary / 1200000
    );
    amount *= 1e15;
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateNoTargetNoCap();

    _jbETHPaymentTerminal.pay{value: amount}(
      projectId_,
      0,
      address(0),
      msg.sender,
      0,
      false,
      '',
      ''
    );

    uint256 totalContributions = bluntDelegateAlt_.getRoundInfo().totalContributions;
    hevm.warp(100);
    hevm.prank(_bluntProjectOwner);
    bluntDelegateAlt_.closeRound();

    uint256 raisedUsd = _priceFeed.getQuote(
      uint128(totalContributions),
      address(uint160(uint256(keccak256('eth')))),
      address(0),
      30 minutes
    );
    uint256 k = _maxK -
      (((_maxK - _minK) * (raisedUsd - _lowerFundraiseBoundary)) /
        (_upperFundraiseBoundary - _lowerFundraiseBoundary));

    uint256 bluntFee = _calculateFee(totalContributions);
    assertEq(bluntFee, (totalContributions * k) / 10000);
  }

  function testIsTargetReached() public {
    assertBoolEq(bluntDelegate.isTargetReached(), false);

    _jbETHPaymentTerminal.pay{value: _target}(
      projectId,
      0,
      address(0),
      msg.sender,
      0,
      false,
      '',
      ''
    );
    assertBoolEq(bluntDelegate.isTargetReached(), false);
    _jbETHPaymentTerminal.pay{value: 1e15}(projectId, 0, address(0), msg.sender, 0, false, '', '');
    assertBoolEq(bluntDelegate.isTargetReached(), true);
  }

  function testIsTargetReachedUsd() public {
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateUsd();

    uint128 targetUsd = 1e10;
    uint256 convertedTarget = _priceFeed.getQuote(targetUsd, address(0), address(0), 0);
    uint256 formattedTarget = convertedTarget - (convertedTarget % 1e15);

    assertBoolEq(bluntDelegateAlt_.isTargetReached(), false);
    _jbETHPaymentTerminal.pay{value: formattedTarget}(
      projectId_,
      0,
      address(0),
      msg.sender,
      0,
      false,
      '',
      ''
    );
    assertBoolEq(bluntDelegateAlt_.isTargetReached(), false);
    _jbETHPaymentTerminal.pay{value: 1e15}(projectId_, 0, address(0), msg.sender, 0, false, '', '');
    assertBoolEq(bluntDelegateAlt_.isTargetReached(), true);
  }

  ///////////////////////////////////////
  /////////////// EVENTS ////////////////
  ///////////////////////////////////////

  function testEvent_roundCreated() public {
    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    hevm.expectEmit(false, false, false, true);
    emit RoundCreated(deployBluntDelegateData, 3, launchProjectData.data.duration);
    bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData, _clone);
  }

  function testEvent_closedRound() public {
    hevm.startPrank(_bluntProjectOwner);
    hevm.expectEmit(false, false, false, false);
    emit RoundClosed();
    bluntDelegate.closeRound();
    hevm.stopPrank();
  }

  ///////////////////////////////////////
  /////////////// REVERTS ///////////////
  ///////////////////////////////////////

  function testRevert_didPay_RoundEnded() public {
    hevm.warp(7 days + 100);

    hevm.expectRevert(bytes4(keccak256('ROUND_ENDED()')));
    _jbETHPaymentTerminal.pay{value: _target}(
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

  function testRevert_didPay_RoundClosed() public {
    hevm.prank(_bluntProjectOwner);
    bluntDelegate.closeRound();

    hevm.expectRevert(bytes4(keccak256('INVALID_PAYMENT_EVENT()')));
    _jbETHPaymentTerminal.pay{value: _target}(
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
    _jbETHPaymentTerminal.pay{value: _hardcap}(
      projectId,
      0,
      address(0),
      msg.sender,
      0,
      false,
      '',
      ''
    );

    hevm.expectRevert(bytes4(keccak256('CAP_REACHED()')));
    _jbETHPaymentTerminal.pay{value: 1e15}(projectId, 0, address(0), msg.sender, 0, false, '', '');
  }

  function testRevert_didPay_capReachedUsd() public {
    (uint256 projectId_, ) = _createDelegateUsd();

    uint128 capUsd = 1e12;
    uint256 weiCap = _priceFeed.getQuote(capUsd, address(0), address(0), 0);
    uint256 formattedCap = weiCap - (weiCap % 1e15);

    _jbETHPaymentTerminal.pay{value: formattedCap}(
      projectId_,
      0,
      address(0),
      msg.sender,
      0,
      false,
      '',
      ''
    );

    hevm.expectRevert(bytes4(keccak256('CAP_REACHED()')));
    _jbETHPaymentTerminal.pay{value: 1e15}(projectId_, 0, address(0), msg.sender, 0, false, '', '');
  }

  function testRevert_didRedeem_roundClosed() public {
    uint256 amount = _target + 1e15;
    hevm.prank(user);
    _jbETHPaymentTerminal.pay{value: amount}(projectId, 0, address(0), user, 0, false, '', '');

    hevm.warp(7 days + 100);

    hevm.prank(_bluntProjectOwner);
    bluntDelegate.closeRound();

    uint256 tokensReturned = 1e14;
    hevm.expectRevert(bytes4(keccak256('FUNDING_CYCLE_REDEEM_PAUSED()')));
    hevm.prank(user);
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

  function testRevert_closeRound_roundNotEnded() public {
    uint256 amount = _target + 1e15;
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

    hevm.prank(_bluntProjectOwner);
    hevm.expectRevert(bytes4(keccak256('ROUND_NOT_ENDED()')));
    bluntDelegate.closeRound();
  }

  function testRevert_setDeadline_notProjectOwner() public {
    (, BluntDelegate bluntDelegateAlt_) = _createDelegateWithoutDeadline();
    uint256 deadline_ = block.timestamp + 1e4;

    hevm.expectRevert(bytes4(keccak256('NOT_PROJECT_OWNER()')));
    bluntDelegateAlt_.setDeadline(deadline_);
  }

  function testRevert_setDeadline_roundClosed() public {
    (, BluntDelegate bluntDelegateAlt_) = _createDelegateWithoutDeadline();
    hevm.startPrank(_bluntProjectOwner);
    uint256 deadline_ = block.timestamp + 1e4;
    bluntDelegateAlt_.closeRound();

    hevm.expectRevert(bytes4(keccak256('ROUND_CLOSED()')));
    bluntDelegateAlt_.setDeadline(deadline_);

    hevm.stopPrank();
  }

  function testRevert_setDeadline_deadlineSet() public {
    (, BluntDelegate bluntDelegateAlt_) = _createDelegateWithoutDeadline();
    hevm.startPrank(_bluntProjectOwner);
    uint256 deadline_ = block.timestamp + 1e4;
    bluntDelegateAlt_.setDeadline(deadline_);

    hevm.expectRevert(bytes4(keccak256('DEADLINE_SET()')));
    bluntDelegateAlt_.setDeadline(deadline_ + 1e4);

    hevm.expectRevert(bytes4(keccak256('DEADLINE_SET()')));
    bluntDelegate.setDeadline(deadline_);

    hevm.stopPrank();
  }

  function testRevert_setDeadline_invalidDeadline() public {
    (, BluntDelegate bluntDelegateAlt_) = _createDelegateWithoutDeadline();
    hevm.startPrank(_bluntProjectOwner);
    hevm.warp(2 days);
    uint256 deadline_ = block.timestamp - 1e4;

    hevm.expectRevert(bytes4(keccak256('INVALID_DEADLINE()')));
    bluntDelegateAlt_.setDeadline(deadline_);

    hevm.stopPrank();
  }

  ///////////////////////////////////////
  /////////////// HELPERS ///////////////
  ///////////////////////////////////////

  // Same as normal delegate, but no deadline
  function _createDelegateWithoutDeadline()
    internal
    returns (uint256 _projectId, BluntDelegate _bluntDelegate)
  {
    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    JBSplit[] memory afterRoundSplits_ = new JBSplit[](1);
    afterRoundSplits_[0] = JBSplit({
      preferClaimed: false,
      preferAddToBalance: false,
      percent: JBConstants.SPLITS_TOTAL_PERCENT,
      projectId: 0,
      beneficiary: payable(address(1)),
      lockedUntil: 0,
      allocator: IJBSplitAllocator(address(0))
    });

    deployBluntDelegateData.afterRoundSplits = afterRoundSplits_;
    launchProjectData.data.duration = 0;

    _projectId = bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData, _clone);
    _bluntDelegate = BluntDelegate(_jbProjects.ownerOf(_projectId));
  }

  // Same as blunt delegate, but without target and hardcap
  function _createDelegateNoTargetNoCap()
    internal
    returns (uint256 _projectId, BluntDelegate _bluntDelegate)
  {
    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    launchProjectData.data.duration = 0;
    deployBluntDelegateData.target = 0;
    deployBluntDelegateData.hardcap = 0;

    _projectId = bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData, _clone);
    _bluntDelegate = BluntDelegate(_jbProjects.ownerOf(_projectId));
  }

  // Same as blunt delegate, but with target and hardcap in USD
  function _createDelegateUsd()
    internal
    returns (uint256 _projectId, BluntDelegate _bluntDelegate)
  {
    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    launchProjectData.data.duration = 0;
    deployBluntDelegateData.target = 1e10; // 10k USD
    deployBluntDelegateData.hardcap = 1e12; // 1M USD
    deployBluntDelegateData.isTargetUsd = true;
    deployBluntDelegateData.isHardcapUsd = true;

    _projectId = bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData, _clone);
    _bluntDelegate = BluntDelegate(_jbProjects.ownerOf(_projectId));
  }

  function _successfulRoundAssertions(
    uint256 projectId_,
    uint256 timestamp_,
    uint256 totalContributions_
  ) internal returns (JBFundingCycle memory fundingCycle, JBFundingCycleMetadata memory metadata) {
    (fundingCycle, metadata) = _jbController.currentFundingCycleOf(projectId_);

    assertEq(fundingCycle.duration, 0);
    assertEq(fundingCycle.weight, 1e24);
    assertEq(fundingCycle.discountRate, 0);
    assertEq(address(fundingCycle.ballot), address(0));
    assertEq(metadata.reservedRate, _afterRoundReservedRate);
    assertBoolEq(metadata.pauseRedeem, true);
    assertEq(metadata.redemptionRate, 0);
    assertBoolEq(metadata.global.pauseTransfers, false);
    assertBoolEq(metadata.pausePay, true);
    assertBoolEq(metadata.pauseDistributions, false);
    assertBoolEq(metadata.useDataSourceForPay, false);
    assertBoolEq(metadata.useDataSourceForRedeem, false);
    assertEq(metadata.dataSource, address(0));

    JBSplit[] memory bluntSplits = _jbSplitsStore.splitsOf({
      _projectId: projectId_,
      _domain: timestamp_,
      _group: 1
    });
    assertEq(bluntSplits.length, 1);
    assertBoolEq(bluntSplits[0].preferClaimed, false);
    assertBoolEq(bluntSplits[0].preferAddToBalance, false);
    assertEq(bluntSplits[0].percent, JBConstants.SPLITS_TOTAL_PERCENT);
    assertEq(bluntSplits[0].projectId, _bluntProjectId);
    assertEq(bluntSplits[0].beneficiary, _bluntProjectOwner);
    assertTrue(bluntSplits[0].lockedUntil == 0);
    assertEq(address(bluntSplits[0].allocator), address(0));

    // Blunt fee logic
    uint256 bluntFee = _calculateFee(totalContributions_);
    (uint256 distributionLimit, ) = _jbController.distributionLimitOf(
      projectId_,
      _jbFundingCycleStore.latestConfigurationOf(projectId_),
      _jbETHPaymentTerminal,
      0x000000000000000000000000000000000000EEEe
    );
    uint256 projectBalance = IJBSingleTokenPaymentTerminalStore(_jbETHPaymentTerminal.store())
      .balanceOf(_jbETHPaymentTerminal, projectId_);
    uint256 bfBalance = IJBSingleTokenPaymentTerminalStore(_jbETHPaymentTerminal.store()).balanceOf(
      _jbETHPaymentTerminal,
      _bluntProjectId
    );
    assertEq(distributionLimit, bluntFee);
    assertEq(projectBalance, totalContributions_ - bluntFee);
    assertEq(bfBalance, bluntFee);

    address owner = _jbProjects.ownerOf(projectId_);
    assertEq(owner, _bluntProjectOwner);
  }
}
