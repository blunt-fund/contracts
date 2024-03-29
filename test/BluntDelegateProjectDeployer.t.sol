// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './helper/BluntSetup.sol';
import 'contracts/BluntDelegateProjectDeployer.sol';
import 'contracts/BluntDelegateCloner.sol';
import 'contracts/interfaces/IBluntDelegateDeployer.sol';
import 'contracts/interfaces/IBluntDelegateCloner.sol';

contract BluntDelegateProjectDeployerTest is BluntSetup {
  BluntDelegateProjectDeployer public bluntDeployer;
  IBluntDelegateCloner public delegateCloner;

  function setUp() public virtual override {
    BluntSetup.setUp();

    delegateCloner = new BluntDelegateCloner(_registry);

    bluntDeployer = new BluntDelegateProjectDeployer(
      address(this),
      delegateCloner,
      _jbController,
      _bluntProjectId,
      address(uint160(uint256(keccak256('eth')))),
      address(uint160(uint256(keccak256('usdc')))),
      uint16(_maxK),
      uint16(_minK),
      uint56(_upperFundraiseBoundary),
      uint56(_lowerFundraiseBoundary)
    );
  }

  function testLaunchProject() public {
    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    uint256 projectId = bluntDeployer.launchProjectFor(
      deployBluntDelegateData,
      launchProjectData
    );

    assertEq(projectId, 2);
  }

  function testDelegateAddressIsProjectOwner() public {
    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    uint256 projectId = bluntDeployer.launchProjectFor(
      deployBluntDelegateData,
      launchProjectData
    );
    address owner = _jbProjects.ownerOf(projectId);
    (, JBFundingCycleMetadata memory metadata) = _jbController.currentFundingCycleOf(projectId);

    assertEq(owner, metadata.dataSource);
  }

  function testMetadataOverwrite() public {
    (
      DeployBluntDelegateData memory deployBluntDelegateData,
      JBLaunchProjectData memory launchProjectData
    ) = _formatDeployData();

    // Set wrong metadata
    JBFundAccessConstraints[] memory wrongConstraints = new JBFundAccessConstraints[](1);
    wrongConstraints[0] = JBFundAccessConstraints(
      IJBPaymentTerminal(address(1)),
      address(1),
      1,
      1,
      1,
      1
    );
    JBGroupedSplits[] memory wrongGroupedSplits = new JBGroupedSplits[](1);
    JBSplit[] memory wrongSplits = new JBSplit[](1);
    wrongSplits[0] = JBSplit({
      preferClaimed: false,
      preferAddToBalance: false,
      percent: 1_000_000_000,
      projectId: 1,
      beneficiary: payable(address(1)),
      lockedUntil: 0,
      allocator: IJBSplitAllocator(address(1))
    });
    wrongGroupedSplits[0] = JBGroupedSplits(2, wrongSplits);

    launchProjectData.metadata.dataSource = address(2);
    launchProjectData.metadata.useDataSourceForPay = false;
    launchProjectData.metadata.useDataSourceForRedeem = false;
    launchProjectData.metadata.redemptionRate = 2;
    launchProjectData.metadata.global.pauseTransfers = false;
    launchProjectData.groupedSplits = wrongGroupedSplits;
    launchProjectData.fundAccessConstraints = wrongConstraints;
    launchProjectData.data.ballot = IJBFundingCycleBallot(address(1));

    uint256 projectId = bluntDeployer.launchProjectFor(
      deployBluntDelegateData,
      launchProjectData
    );
    (JBFundingCycle memory fundingCycle, JBFundingCycleMetadata memory metadata) = _jbController
      .currentFundingCycleOf(projectId);
    (uint256 distributionLimit, ) = _jbController.fundAccessConstraintsStore().distributionLimitOf(
      projectId,
      1,
      IJBPaymentTerminal(address(1)),
      address(1)
    );
    JBSplit[] memory splits = _jbSplitsStore.splitsOf({
      _projectId: projectId,
      _domain: block.timestamp,
      _group: 2
    });

    assertFalse(metadata.dataSource == address(2));
    assertBoolEq(metadata.useDataSourceForPay, true);
    assertBoolEq(metadata.useDataSourceForRedeem, true);
    assertEq(metadata.redemptionRate, JBConstants.MAX_REDEMPTION_RATE);
    assertBoolEq(metadata.global.pauseTransfers, true);
    assertEq(splits.length, 0);
    assertEq(distributionLimit, 0);
    assertEq(address(fundingCycle.ballot), address(0));
  }

  function testSetDelegates() public {
    assertEq(address(bluntDeployer.delegateCloner()), address(delegateCloner));

    IBluntDelegateCloner delegateCloner_ = IBluntDelegateCloner(address(2));

    bluntDeployer._setDeployer(delegateCloner_);

    assertEq(address(bluntDeployer.delegateCloner()), address(delegateCloner_));
  }

  function testSetFees() public {
    assertEq(bluntDeployer.maxK(), _maxK);
    assertEq(bluntDeployer.minK(), _minK);
    assertEq(bluntDeployer.upperFundraiseBoundary(), _upperFundraiseBoundary);
    assertEq(bluntDeployer.lowerFundraiseBoundary(), _lowerFundraiseBoundary);

    uint16 maxK_ = 200;
    uint16 minK_ = 100;
    uint56 upperFundraiseBoundary_ = 1e7;
    uint56 lowerFundraiseBoundary_ = 1e6;

    bluntDeployer._setFees(maxK_, minK_, upperFundraiseBoundary_, lowerFundraiseBoundary_);

    assertEq(bluntDeployer.maxK(), maxK_);
    assertEq(bluntDeployer.minK(), minK_);
    assertEq(bluntDeployer.upperFundraiseBoundary(), upperFundraiseBoundary_);
    assertEq(bluntDeployer.lowerFundraiseBoundary(), lowerFundraiseBoundary_);
  }

  ///////////////////////////////////////
  /////////////// REVERTS ///////////////
  ///////////////////////////////////////

  function testRevert_onlyOwner() public {
    hevm.startPrank(address(1));

    hevm.expectRevert('Ownable: caller is not the owner');
    bluntDeployer._setDeployer(
      IBluntDelegateCloner(address(2))
    );

    hevm.expectRevert('Ownable: caller is not the owner');
    bluntDeployer._setFees(300, 100, 1e7, 1e6);

    hevm.stopPrank();
  }

  function testRevert_setFees_exceededMaxFee() public {
    uint16 maxK_ = 600;
    uint16 minK_ = 100;
    uint56 upperFundraiseBoundary_ = 1e7;
    uint56 lowerFundraiseBoundary_ = 1e6;

    hevm.expectRevert(bytes4(keccak256('EXCEEDED_MAX_FEE()')));
    bluntDeployer._setFees(maxK_, minK_, upperFundraiseBoundary_, lowerFundraiseBoundary_);
  }

  function testRevert_setFees_invalidInputs() public {
    uint16 maxK_ = 200;
    uint16 minK_ = 300;
    uint56 upperFundraiseBoundary_ = 1e7;
    uint56 lowerFundraiseBoundary_ = 1e6;

    hevm.expectRevert(bytes4(keccak256('INVALID_INPUTS()')));
    bluntDeployer._setFees(maxK_, minK_, upperFundraiseBoundary_, lowerFundraiseBoundary_);

    maxK_ = 300;
    minK_ = 200;
    upperFundraiseBoundary_ = 1e6;
    lowerFundraiseBoundary_ = 1e7;

    hevm.expectRevert(bytes4(keccak256('INVALID_INPUTS()')));
    bluntDeployer._setFees(maxK_, minK_, upperFundraiseBoundary_, lowerFundraiseBoundary_);
  }

  function testRevert_implementationNotInitializable() public {
    (DeployBluntDelegateData memory deployBluntDelegateData, ) = _formatDeployData();
    IBluntDelegateClone implementation = IBluntDelegateClone(delegateCloner.implementation());

    DeployBluntDelegateDeployerData memory _deployerData = DeployBluntDelegateDeployerData(
      _jbController,
      uint48(_bluntProjectId),
      2,
      0,
      address(1),
      address(2),
      uint16(_maxK),
      uint16(_minK),
      uint56(_upperFundraiseBoundary),
      uint56(_lowerFundraiseBoundary)
    );

    hevm.expectRevert('Initializable: contract is already initialized');
    implementation.initialize(_deployerData, deployBluntDelegateData);
  }
}
