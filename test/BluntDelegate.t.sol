// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './helper/BluntSetup.sol';
import './mocks/ERC20Mock.sol';
import 'contracts/BluntDelegate.sol';
import 'contracts/BluntDelegateProjectDeployer.sol';

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
    uint256 duration,
    uint256 currentFundingCycle
  );
  event Paid(address beneficiary, uint256 amount);
  event Redeemed(address beneficiary, uint256 amount);
  event ClaimedSlices(address beneficiary, uint256 amount);
  event ClaimedSlicesBatch(address[] beneficiaries, uint256[] amounts);
  event Queued();
  event TokenMetadataSet(string tokenName_, string tokenSymbol_);
  event RoundClosed();
  event SlicerCreated(uint256 slicerId_, address slicerAddress);

  //*********************************************************************//
  // ------------------------------ setup ------------------------------ //
  //*********************************************************************//

  function setUp() public virtual override {
    BluntSetup.setUp();

    bluntDeployer = new BluntDelegateProjectDeployer(
      _jbController,
      _jbOperatorStore,
      address(uint160(uint256(keccak256('eth')))),
      address(uint160(uint256(keccak256('usdc'))))
    );

    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    projectId = bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData);

    bluntDelegate = BluntDelegate(_jbProjects.ownerOf(projectId));
    hevm.deal(user, 1e30);
    hevm.deal(user2, 1e30);
    hevm.deal(_bluntProjectOwner, 1e30);
  }

  //*********************************************************************//
  // ------------------------------ tests ------------------------------ //
  //*********************************************************************//

  function testConstructor() public {
    (, BluntDelegate bluntDelegateAlt_) = _createDelegateWithoutSlicer();

    RoundInfo memory roundInfo = bluntDelegateAlt_.getRoundInfo();
    assertBoolEq(roundInfo.isQueued, true);
    assertBoolEq(roundInfo.isSlicerToBeCreated, false);

    (, BluntDelegate bluntDelegateAlt2_) = _createDelegateEnforcedSlicer();
    assertBoolEq(bluntDelegateAlt2_.isSlicerToBeCreated(), true);
  }

  function testRoundInfo() public {
    RoundInfo memory roundInfo = bluntDelegate.getRoundInfo();

    assertEq(bluntDelegate.projectId(), projectId);
    assertEq(roundInfo.totalContributions, 0);
    assertEq(roundInfo.target, _target);
    assertEq(roundInfo.hardcap, _hardcap);
    assertEq(roundInfo.releaseTimelock, _releaseTimelock);
    assertEq(roundInfo.transferTimelock, _transferTimelock);
    assertEq(roundInfo.projectOwner, _bluntProjectOwner);
    assertEq(roundInfo.fundingCycleRound, 1);
    assertEq(roundInfo.afterRoundReservedRate, _afterRoundReservedRate);
    assertBoolEq(roundInfo.afterRoundSplits[0].preferClaimed, false);
    assertEq(roundInfo.afterRoundSplits[0].percent, JBConstants.SPLITS_TOTAL_PERCENT - 1000);
    assertEq(roundInfo.afterRoundSplits[0].beneficiary, address(0));
    assertEq(roundInfo.afterRoundSplits[1].percent, 1000);
    assertEq(roundInfo.afterRoundSplits[1].beneficiary, address(1));
    assertApproxEq(roundInfo.afterRoundSplits[0].lockedUntil, block.timestamp + 2 days, 1);
    assertEq(roundInfo.tokenName, _tokenName);
    assertEq(roundInfo.tokenSymbol, _tokenSymbol);
    assertBoolEq(roundInfo.isRoundClosed, false);
    assertBoolEq(roundInfo.isQueued, false);
    assertBoolEq(roundInfo.isSlicerToBeCreated, true);
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

  function testDidPayWithoutSlices() public {
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateWithoutSlicer();

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
    assertEq(uint256(bluntDelegateAlt_.totalContributions()), amount);
    assertEq(bluntDelegateAlt_.contributions(msg.sender), 0);
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
    assertEq(uint256(bluntDelegate.totalContributions()), 9e17);
    assertEq(bluntDelegate.contributions(user), 9e17);
  }

  function testDidRedeemWithoutSlices() public {
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateWithoutSlicer();

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
    assertEq(uint256(bluntDelegateAlt_.totalContributions()), 9e17);
    assertEq(bluntDelegateAlt_.contributions(user), 0);
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

  function testSetTokenMetadata() public {
    string memory newTokenName = 'Name';
    string memory newTokenSymbol = 'SYM';

    hevm.startPrank(_bluntProjectOwner);
    bluntDelegate.setTokenMetadata(newTokenName, newTokenSymbol);
    hevm.stopPrank();

    RoundInfo memory roundInfo = bluntDelegate.getRoundInfo();

    assertEq(roundInfo.tokenName, newTokenName);
    assertEq(roundInfo.tokenSymbol, newTokenSymbol);
  }

  function testTransferTokenToSlicer() public {
    ERC20Mock erc20 = new ERC20Mock(address(bluntDelegate));

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

    hevm.warp(100);
    hevm.startPrank(_bluntProjectOwner);
    bluntDelegate.closeRound();
    hevm.stopPrank();
    hevm.warp(7 days + 100);

    bluntDelegate.transferToken(IERC20(erc20));

    address slicerAddress = address(uint160(uint256(keccak256('slicerId'))));
    assertEq(erc20.balanceOf(address(bluntDelegate)), 0);
    assertEq(erc20.balanceOf(slicerAddress), _target);
  }

  function testTransferTokenToProjectOwner() public {
    ERC20Mock erc20 = new ERC20Mock(address(bluntDelegate));

    hevm.warp(100);
    hevm.startPrank(_bluntProjectOwner);
    bluntDelegate.closeRound();
    hevm.stopPrank();
    hevm.warp(7 days + 100);

    bluntDelegate.transferToken(IERC20(erc20));

    assertEq(erc20.balanceOf(address(bluntDelegate)), 0);
    assertEq(erc20.balanceOf(address(_bluntProjectOwner)), _target);
  }

  function testTransferTokenToProjectOwnerWithoutSlicer() public {
    ERC20Mock erc20 = new ERC20Mock(address(bluntDelegate));
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateWithoutSlicer();

    uint256 amount = _target + 1e15;
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

    hevm.warp(100);
    hevm.startPrank(_bluntProjectOwner);
    bluntDelegate.closeRound();
    hevm.stopPrank();
    hevm.warp(7 days + 100);

    bluntDelegate.transferToken(IERC20(erc20));

    assertEq(erc20.balanceOf(address(bluntDelegate)), 0);
    assertEq(erc20.balanceOf(address(_bluntProjectOwner)), _target);
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

    hevm.startPrank(_bluntProjectOwner);
    bluntDelegate.closeRound();
    hevm.stopPrank();

    assertBoolEq(bluntDelegate.isRoundClosed(), true);
    assertEq(bluntDelegate.slicerId(), 0);
  }

  function testCloseRoundAtZero_NoTarget() public {
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateNoTargetNoCap();

    hevm.warp(100);
    hevm.startPrank(_bluntProjectOwner);
    bluntDelegateAlt_.closeRound();
    hevm.stopPrank();

    uint256 timestamp = block.timestamp;

    assertBoolEq(bluntDelegateAlt_.isRoundClosed(), true);

    hevm.warp(100);

    address owner = _jbProjects.ownerOf(projectId_);
    assertEq(owner, address(bluntDelegateAlt_));

    address currency = address(_jbTokenStore.tokenOf(projectId_));
    assertEq(currency, address(0));

    assertEq(bluntDelegate.slicerId(), 0);
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

    uint256 totalContributions = bluntDelegateAlt_.totalContributions();
    hevm.warp(100);
    hevm.startPrank(_bluntProjectOwner);
    bluntDelegateAlt_.closeRound();
    hevm.stopPrank();

    uint256 timestamp = block.timestamp;

    assertBoolEq(bluntDelegateAlt_.isRoundClosed(), true);

    hevm.warp(100);

    (
      JBFundingCycle memory fundingCycle,
      JBFundingCycleMetadata memory metadata
    ) = _successfulRoundAssertions(projectId_);

    address currency = address(_jbTokenStore.tokenOf(projectId_));
    assertTrue(currency != address(0));

    uint256 slicerId = bluntDelegateAlt_.slicerId();
    assertTrue(slicerId != 0);
    assertEq(_sliceCore.balanceOf(address(bluntDelegateAlt_), slicerId), totalContributions / 1e15);

    JBSplit[] memory splits = _jbSplitsStore.splitsOf({
      _projectId: projectId_,
      _domain: timestamp,
      _group: 2
    });
    assertEq(splits.length, 2);
    assertFalse(address(splits[0].beneficiary) == address(0));
    assertBoolEq(splits[0].preferClaimed, true);
    assertEq(splits[0].percent, JBConstants.SPLITS_TOTAL_PERCENT - 1000);
    assertTrue(splits[0].lockedUntil != 0);
    assertEq(address(splits[1].beneficiary), address(1));
    assertBoolEq(splits[1].preferClaimed, false);
    assertEq(splits[1].percent, 1000);
    assertEq(splits[1].lockedUntil, 0);
  }

  function testCloseRoundAboveTarget() public {
    address currency = address(_jbTokenStore.tokenOf(projectId));
    uint256 slicerId = bluntDelegate.slicerId();
    assertTrue(currency == address(0));
    assertTrue(slicerId == 0);
    assertTrue(_sliceCore.balanceOf(address(bluntDelegate), slicerId) == 0);

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

    uint256 totalContributions = bluntDelegate.totalContributions();
    hevm.warp(100);
    hevm.startPrank(_bluntProjectOwner);
    bluntDelegate.closeRound();
    hevm.stopPrank();

    uint256 timestamp = block.timestamp;

    assertBoolEq(bluntDelegate.isRoundClosed(), true);

    // Wait for the funding cycle to end
    hevm.warp(7 days + 100);

    (
      JBFundingCycle memory fundingCycle,
      JBFundingCycleMetadata memory metadata
    ) = _successfulRoundAssertions(projectId);

    currency = address(_jbTokenStore.tokenOf(projectId));
    assertTrue(currency != address(0));

    slicerId = bluntDelegate.slicerId();
    assertTrue(slicerId != 0);
    assertEq(_sliceCore.balanceOf(address(bluntDelegate), slicerId), totalContributions / 1e15);

    JBSplit[] memory splits = _jbSplitsStore.splitsOf({
      _projectId: projectId,
      _domain: timestamp,
      _group: 2
    });
    assertEq(splits.length, 2);
    assertFalse(address(splits[0].beneficiary) == address(0));
    assertBoolEq(splits[0].preferClaimed, true);
    assertEq(splits[0].percent, JBConstants.SPLITS_TOTAL_PERCENT - 1000);
    assertTrue(splits[0].lockedUntil != 0);
    assertEq(address(splits[1].beneficiary), address(1));
    assertBoolEq(splits[1].preferClaimed, false);
    assertEq(splits[1].percent, 1000);
    assertEq(splits[1].lockedUntil, 0);
  }

  function testCloseRoundAboveTarget_withSlicer_notInSplits() public {
    (uint256 projectId_, BluntDelegate bluntDelegateAlt2_) = _createDelegateEnforcedSlicer();

    address currency = address(_jbTokenStore.tokenOf(projectId_));
    uint256 slicerId = bluntDelegateAlt2_.slicerId();
    assertTrue(currency == address(0));
    assertTrue(slicerId == 0);
    assertTrue(_sliceCore.balanceOf(address(bluntDelegateAlt2_), slicerId) == 0);

    uint256 amount = _target + 1e15;
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

    uint256 totalContributions = bluntDelegateAlt2_.totalContributions();
    hevm.warp(100);
    hevm.startPrank(_bluntProjectOwner);
    bluntDelegateAlt2_.closeRound();
    hevm.stopPrank();

    uint256 timestamp = block.timestamp;

    assertBoolEq(bluntDelegateAlt2_.isRoundClosed(), true);

    hevm.warp(100);

    (
      JBFundingCycle memory fundingCycle,
      JBFundingCycleMetadata memory metadata
    ) = _successfulRoundAssertions(projectId_);

    currency = address(_jbTokenStore.tokenOf(projectId_));
    assertTrue(currency != address(0));

    slicerId = bluntDelegateAlt2_.slicerId();
    assertTrue(slicerId != 0);
    assertEq(
      _sliceCore.balanceOf(address(bluntDelegateAlt2_), slicerId),
      totalContributions / 1e15
    );

    JBSplit[] memory splits = _jbSplitsStore.splitsOf({
      _projectId: projectId_,
      _domain: timestamp,
      _group: 2
    });
    assertEq(splits.length, 1);
    assertEq(address(splits[0].beneficiary), address(1));
    assertBoolEq(splits[0].preferClaimed, false);
    assertEq(splits[0].percent, JBConstants.SPLITS_TOTAL_PERCENT);
    assertEq(splits[0].lockedUntil, 0);
  }

  function testCloseRoundAboveTarget_withoutSlicer() public {
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateWithoutSlicer();

    address currency = address(_jbTokenStore.tokenOf(projectId_));
    uint256 slicerId = bluntDelegateAlt_.slicerId();
    assertTrue(currency == address(0));
    assertTrue(slicerId == 0);
    assertTrue(_sliceCore.balanceOf(address(bluntDelegateAlt_), slicerId) == 0);

    uint256 amount = _target + 1e15;
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

    hevm.warp(100);
    hevm.startPrank(_bluntProjectOwner);
    bluntDelegateAlt_.closeRound();
    hevm.stopPrank();

    uint256 timestamp = block.timestamp;

    assertBoolEq(bluntDelegateAlt_.isRoundClosed(), true);

    hevm.warp(100);

    (
      JBFundingCycle memory fundingCycle,
      JBFundingCycleMetadata memory metadata
    ) = _successfulRoundAssertions(projectId_);

    currency = address(_jbTokenStore.tokenOf(projectId_));
    assertTrue(currency != address(0));

    slicerId = bluntDelegateAlt_.slicerId();
    assertEq(slicerId, 0);
    assertEq(_sliceCore.balanceOf(address(bluntDelegateAlt_), slicerId), 0);

    JBSplit[] memory splits = _jbSplitsStore.splitsOf({
      _projectId: projectId_,
      _domain: timestamp,
      _group: 2
    });
    assertEq(splits.length, 1);
    assertEq(address(splits[0].beneficiary), address(1));
    assertBoolEq(splits[0].preferClaimed, false);
    assertEq(splits[0].percent, JBConstants.SPLITS_TOTAL_PERCENT);
    assertEq(splits[0].lockedUntil, 0);
  }

  function testCloseRoundAboveTarget_withoutSlicer_withoutCurrency() public {
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateWithoutSlicer();

    address currency = address(_jbTokenStore.tokenOf(projectId_));
    uint256 slicerId = bluntDelegateAlt_.slicerId();
    assertTrue(currency == address(0));
    assertTrue(slicerId == 0);
    assertTrue(_sliceCore.balanceOf(address(bluntDelegateAlt_), slicerId) == 0);

    uint256 amount = _target + 1e15;
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

    hevm.warp(100);
    hevm.startPrank(_bluntProjectOwner);
    bluntDelegateAlt_.setTokenMetadata('', '');
    bluntDelegateAlt_.closeRound();
    hevm.stopPrank();

    uint256 timestamp = block.timestamp;

    assertBoolEq(bluntDelegateAlt_.isRoundClosed(), true);

    hevm.warp(100);

    (
      JBFundingCycle memory fundingCycle,
      JBFundingCycleMetadata memory metadata
    ) = _successfulRoundAssertions(projectId_);

    currency = address(_jbTokenStore.tokenOf(projectId_));
    assertEq(currency, address(0));

    slicerId = bluntDelegateAlt_.slicerId();
    assertEq(slicerId, 0);
    assertEq(_sliceCore.balanceOf(address(bluntDelegateAlt_), slicerId), 0);

    JBSplit[] memory splits = _jbSplitsStore.splitsOf({
      _projectId: projectId_,
      _domain: timestamp,
      _group: 2
    });
    assertEq(splits.length, 1);
    assertEq(address(splits[0].beneficiary), address(1));
    assertBoolEq(splits[0].preferClaimed, false);
    assertEq(splits[0].percent, JBConstants.SPLITS_TOTAL_PERCENT);
    assertEq(splits[0].lockedUntil, 0);
  }

  function testTransferUnclaimedSlicesTo() public {
    // Make two payments
    hevm.prank(user);
    _jbETHPaymentTerminal.pay{value: _target}(projectId, 0, address(0), user, 0, false, '', '');
    hevm.prank(user2);
    _jbETHPaymentTerminal.pay{value: _target * 2}(projectId, 0, address(0), user2, 0, false, '', '');

    // Close round
    hevm.warp(100);
    hevm.startPrank(_bluntProjectOwner);
    bluntDelegate.closeRound();
    hevm.stopPrank();

    uint256 slicerId = bluntDelegate.slicerId();
    address[] memory beneficiaries = new address[](3);
    beneficiaries[0] = user;
    beneficiaries[1] = address(3);
    beneficiaries[2] = user2;

    bluntDelegate.transferUnclaimedSlicesTo(beneficiaries);

    assertEq(_sliceCore.balanceOf(address(bluntDelegate), slicerId), 0);
    assertEq(_sliceCore.balanceOf(user, slicerId), _target / 1e15);
    assertEq(_sliceCore.balanceOf(user2, slicerId), 2e18 / 1e15);
    assertEq(_sliceCore.balanceOf(address(3), slicerId), 0);
    assertEq(bluntDelegate.contributions(user), 0);
    assertEq(bluntDelegate.contributions(user2), 0);
  }

  function testClaimSlices() public {
    // Make two payments
    hevm.prank(user);
    _jbETHPaymentTerminal.pay{value: _target}(projectId, 0, address(0), user, 0, false, '', '');
    hevm.prank(user2);
    _jbETHPaymentTerminal.pay{value: _target*2}(projectId, 0, address(0), user2, 0, false, '', '');

    // Close round
    hevm.warp(100);
    hevm.startPrank(_bluntProjectOwner);
    bluntDelegate.closeRound();
    hevm.stopPrank();

    uint256 slicerId = bluntDelegate.slicerId();

    hevm.prank(user);
    bluntDelegate.claimSlices();

    assertEq(_sliceCore.balanceOf(address(bluntDelegate), slicerId), 2e18 / 1e15);
    assertEq(_sliceCore.balanceOf(user, slicerId), _target / 1e15);
    assertEq(bluntDelegate.contributions(user), 0);
    assertEq(bluntDelegate.contributions(user2), 2e18);
  }

  function testIsTargetReached() public {
    assertBoolEq(bluntDelegate.isTargetReached(), false);
    
    _jbETHPaymentTerminal.pay{value: _target}(projectId, 0, address(0), msg.sender, 0, false, '', '');
    assertBoolEq(bluntDelegate.isTargetReached(), false);
    _jbETHPaymentTerminal.pay{value: 1e15}(projectId, 0, address(0), msg.sender, 0, false, '', '');
    assertBoolEq(bluntDelegate.isTargetReached(), true);
  }

  function testIsTargetReachedUsd() public {
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateUsd();

    uint128 targetUsd = 1e10;
    uint256 convertedTarget = _priceFeed.getQuote(targetUsd, address(0), address(0), 0);
    uint256 formattedTarget = convertedTarget - convertedTarget % 1e15;

    assertBoolEq(bluntDelegateAlt_.isTargetReached(), false);
    _jbETHPaymentTerminal.pay{value: formattedTarget}(projectId_, 0, address(0), msg.sender, 0, false, '', '');
    assertBoolEq(bluntDelegateAlt_.isTargetReached(), false);
    _jbETHPaymentTerminal.pay{value: 1e15}(projectId_, 0, address(0), msg.sender, 0, false, '', '');
    assertBoolEq(bluntDelegateAlt_.isTargetReached(), true);
  }

  ///////////////////////////////////////
  /////////////// EVENTS ////////////////
  ///////////////////////////////////////

  function testEvent_paid() public {
    uint256 amount = 1e15;

    hevm.expectEmit(false, false, false, true);
    emit Paid(msg.sender, amount);
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
  }

  function testEvent_redeemed() public {
    hevm.startPrank(user);

    uint256 amount = 1e15;
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

    hevm.expectEmit(false, false, false, true);
    emit Redeemed(user, amount);
    uint256 reclaimAmount = _jbETHPaymentTerminal.redeemTokensOf(
      user,
      projectId,
      amount / 1000,
      address(0),
      amount / 1000,
      payable(user),
      '',
      ''
    );

    hevm.stopPrank();
  }

  function testEvent_ClaimedSlices() public {
    uint256 amount = _target + 1e15;
    hevm.prank(user);
    _jbETHPaymentTerminal.pay{value: amount}(projectId, 0, address(0), user, 0, false, '', '');

    // Close round
    hevm.warp(100);
    hevm.startPrank(_bluntProjectOwner);
    bluntDelegate.closeRound();
    hevm.stopPrank();

    uint256 slicerId = bluntDelegate.slicerId();

    hevm.expectEmit(false, false, false, true);
    emit ClaimedSlices(user, amount / 1e15);
    hevm.prank(user);
    bluntDelegate.claimSlices();
  }

  function testEvent_ClaimedSlicesBatch() public {
    hevm.prank(user);
    _jbETHPaymentTerminal.pay{value: _target}(projectId, 0, address(0), user, 0, false, '', '');
    hevm.prank(user2);
    _jbETHPaymentTerminal.pay{value: _target * 2}(projectId, 0, address(0), user2, 0, false, '', '');

    // Close round
    hevm.warp(100);
    hevm.startPrank(_bluntProjectOwner);
    bluntDelegate.closeRound();
    hevm.stopPrank();

    address[] memory beneficiaries = new address[](3);
    beneficiaries[0] = user;
    beneficiaries[1] = address(3);
    beneficiaries[2] = user2;

    uint256[] memory amounts = new uint256[](3);
    amounts[0] = 1e3;
    amounts[1] = 0;
    amounts[2] = 2e3;

    hevm.expectEmit(false, false, false, true);
    emit ClaimedSlicesBatch(beneficiaries, amounts);
    bluntDelegate.transferUnclaimedSlicesTo(beneficiaries);
  }

  function testEvent_queued() public {
    hevm.warp(100);
    hevm.expectEmit(false, false, false, false);
    emit Queued();
    bluntDelegate.queueNextPhase();
  }

  function testEvent_roundCreated() public {
    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    hevm.expectEmit(false, false, false, true);
    emit RoundCreated(deployBluntDelegateData, 2, launchProjectData.data.duration, 1);
    bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData);
  }

  function testEvent_closedRound() public {
    hevm.startPrank(_bluntProjectOwner);
    hevm.expectEmit(false, false, false, false);
    emit RoundClosed();
    bluntDelegate.closeRound();
    hevm.stopPrank();
  }

  function testEvent_closedRoundWithSlicer() public {
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
    hevm.warp(100);

    hevm.startPrank(_bluntProjectOwner);
    hevm.expectEmit(false, false, false, true);
    emit RoundClosed();
    emit SlicerCreated(1, address(uint160(uint256(keccak256('slicerId')))));
    bluntDelegate.closeRound();
    hevm.stopPrank();
  }

  function testEvent_closedRoundWithoutSlicer() public {
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateWithoutSlicer();

    uint256 amount = _target + 1e15;
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
    hevm.warp(100);

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

  function testRevert_didPay_RoundClosed() public {
    hevm.startPrank(_bluntProjectOwner);
    bluntDelegate.closeRound();
    hevm.stopPrank();

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

  function testRevert_didPay_valueNotExact() public {
    uint256 amount = _target + 1e14;

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
    _jbETHPaymentTerminal.pay{value: 1e15}(
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

  function testRevert_didPay_capReachedUsd() public {
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateUsd();

    uint128 capUsd = 1e12;
    uint256 weiCap = _priceFeed.getQuote(capUsd, address(0), address(0), 0);
    uint256 formattedCap = weiCap - weiCap % 1e15;

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
    _jbETHPaymentTerminal.pay{value: 1e15}(
      projectId_,
      0,
      address(0),
      msg.sender,
      0,
      false,
      '',
      ''
    );
  }

  function testRevert_didPay_noCap_maxReached() public {
    (uint256 projectId_, ) = _createDelegateNoTargetNoCap();

    uint256 amount = 4.2e6 ether;
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

    amount = 1e15;
    hevm.expectRevert(bytes4(keccak256('CAP_REACHED()')));
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
  }

  function testRevert_didRedeem_valueNotExact() public {
    hevm.startPrank(user);

    _jbETHPaymentTerminal.pay{value: _target}(projectId, 0, address(0), user, 0, false, '', '');

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
    (uint256 projectId_, BluntDelegate bluntDelegateAlt_) = _createDelegateWithoutSlicer();
    hevm.warp(100);
    hevm.expectRevert(bytes4(keccak256('ALREADY_QUEUED()')));
    bluntDelegateAlt_.queueNextPhase();
  }

  function testRevert_setTokenMetadata_notProjectOwner() public {
    string memory newTokenName = 'Name';
    string memory newTokenSymbol = 'SYM';

    hevm.expectRevert(bytes4(keccak256('NOT_PROJECT_OWNER()')));
    bluntDelegate.setTokenMetadata(newTokenName, newTokenSymbol);
  }

  function testRevert_setTokenMetadata_roundClosed() public {
    string memory newTokenName = 'Name';
    string memory newTokenSymbol = 'SYM';

    hevm.startPrank(_bluntProjectOwner);
    bluntDelegate.closeRound();

    hevm.expectRevert(bytes4(keccak256('ROUND_CLOSED()')));
    bluntDelegate.setTokenMetadata(newTokenName, newTokenSymbol);
    hevm.stopPrank();
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

  function testRevert_closeRound_tokenNotSet() public {
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

    hevm.warp(100);
    hevm.startPrank(_bluntProjectOwner);
    bluntDelegate.setTokenMetadata('', '');
    hevm.expectRevert(bytes4(keccak256('TOKEN_NOT_SET()')));
    bluntDelegate.closeRound();
    hevm.stopPrank();
  }

  function testRevert_transferUnclaimedSlicesTo_slicerNotCreated() public {
    // Make two payments
    hevm.prank(user);
    _jbETHPaymentTerminal.pay{value: _target}(projectId, 0, address(0), user, 0, false, '', '');
    hevm.prank(user2);
    _jbETHPaymentTerminal.pay{value: _target*2}(projectId, 0, address(0), user2, 0, false, '', '');

    address[] memory beneficiaries = new address[](2);
    beneficiaries[0] = user;
    beneficiaries[1] = user2;

    hevm.expectRevert(bytes4(keccak256('SLICER_NOT_YET_CREATED()')));
    bluntDelegate.transferUnclaimedSlicesTo(beneficiaries);
  }

  function testRevert_claimSlices_slicerNotCreated() public {
    // Make two payments
    hevm.prank(user);
    _jbETHPaymentTerminal.pay{value: _target}(projectId, 0, address(0), user, 0, false, '', '');
    hevm.prank(user2);
    _jbETHPaymentTerminal.pay{value: _target*2}(projectId, 0, address(0), user2, 0, false, '', '');

    hevm.startPrank(user);
    hevm.expectRevert(bytes4(keccak256('SLICER_NOT_YET_CREATED()')));
    bluntDelegate.claimSlices();
    hevm.stopPrank();
  }

  function testRevert_transferToken_roundNotClosed() public {
    ERC20Mock erc20 = new ERC20Mock(address(bluntDelegate));

    hevm.expectRevert(bytes4(keccak256('ROUND_NOT_CLOSED()')));
    bluntDelegate.transferToken(IERC20(erc20));
  }

  ///////////////////////////////////////
  /////////////// HELPERS ///////////////
  ///////////////////////////////////////

  // Same as normal delegate, but unlimited duration and no slicer in the split
  function _createDelegateWithoutSlicer()
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
      beneficiary: payable(address(1)), // Gets replaced with slicer address later
      lockedUntil: 0,
      allocator: IJBSplitAllocator(address(0))
    });

    deployBluntDelegateData.afterRoundSplits = afterRoundSplits_;
    launchProjectData.data.duration = 0;

    _projectId = bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData);
    _bluntDelegate = BluntDelegate(_jbProjects.ownerOf(_projectId));
  }

  // Same as alt delegate, but which enforces slicer slicer creation
  function _createDelegateEnforcedSlicer()
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
      beneficiary: payable(address(1)), // Gets replaced with slicer address later
      lockedUntil: 0,
      allocator: IJBSplitAllocator(address(0))
    });

    deployBluntDelegateData.afterRoundSplits = afterRoundSplits_;
    launchProjectData.data.duration = 0;
    deployBluntDelegateData.enforceSlicerCreation = true;

    _projectId = bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData);
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

    _projectId = bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData);
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

    _projectId = bluntDeployer.launchProjectFor(deployBluntDelegateData, launchProjectData);
    _bluntDelegate = BluntDelegate(_jbProjects.ownerOf(_projectId));
  }

  function _successfulRoundAssertions(
    uint256 projectId_
  ) internal returns (JBFundingCycle memory fundingCycle, JBFundingCycleMetadata memory metadata) {
    (fundingCycle, metadata) = _jbController.currentFundingCycleOf(projectId_);

    assertEq(fundingCycle.duration, 0);
    assertEq(fundingCycle.weight, 1e24);
    assertEq(fundingCycle.discountRate, 0);
    assertEq(address(fundingCycle.ballot), address(0));
    assertEq(metadata.reservedRate, _afterRoundReservedRate);
    assertEq(metadata.redemptionRate, 0);
    assertBoolEq(metadata.global.pauseTransfers, false);
    assertBoolEq(metadata.pausePay, true);
    assertBoolEq(metadata.useDataSourceForPay, false);
    assertBoolEq(metadata.useDataSourceForRedeem, false);
    assertEq(metadata.dataSource, address(0));

    address owner = _jbProjects.ownerOf(projectId_);
    assertEq(owner, address(_bluntProjectOwner));
  }
}
