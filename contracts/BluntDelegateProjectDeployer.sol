// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@jbx-protocol/contracts-v2/contracts/abstract/JBOperatable.sol';
import '@jbx-protocol/contracts-v2/contracts/interfaces/IJBController.sol';
import '@jbx-protocol/contracts-v2/contracts/interfaces/IJBProjects.sol';
import '@jbx-protocol/contracts-v2/contracts/libraries/JBOperations.sol';
import './interfaces/IBluntDelegateProjectDeployer.sol';
import './BluntDelegateDeployer.sol';

contract BluntDelegateProjectDeployer is
  BluntDelegateDeployer,
  IBluntDelegateProjectDeployer,
  JBOperatable
{
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//
  error INVALID_TOKEN_ISSUANCE();

  //*********************************************************************//
  // --------------- public immutable stored properties ---------------- //
  //************************************* ********************************//

  /**
    @notice
    Ratio between amount of tokens contributed and slices minted
  */
  uint64 public constant TOKENS_PER_SLICE = 1e15; // 1 token every 0.001 ETH

  /** 
    @notice
    The controller with which new projects should be deployed. 
  */
  IJBController public immutable override controller;

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  constructor(IJBController _controller, IJBOperatorStore _operatorStore)
    JBOperatable(_operatorStore)
  {
    controller = _controller;
  }

  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /** 
    @notice 
    Launches a new project with a tiered NFT rewards data source attached.

    @param _deployBluntDelegateData Data necessary to fulfill the transaction to deploy a tiered limited NFT rewward data source.
    @param _launchProjectData Data necessary to fulfill the transaction to launch a project.

    @return projectId The ID of the newly configured project.
  */
  function launchProjectFor(
    DeployBluntDelegateData memory _deployBluntDelegateData,
    JBLaunchProjectData memory _launchProjectData
  ) external override returns (uint256 projectId) {
    // Get the project ID, optimistically knowing it will be one greater than the current count.
    projectId = controller.projects().count() + 1;

    // Deploy the data source contract.
    address _delegateAddress = deployDelegateFor(projectId, _deployBluntDelegateData);

    // Set the data source address as the data source of the provided metadata.
    _launchProjectData.metadata.dataSource = _delegateAddress;

    // Set the project to use the data source for it's pay function.
    _launchProjectData.metadata.useDataSourceForPay = true;

    // Require weight to be non zero to allow for redemptions, and a multiple of TOKENS_PER_SLICE
    if (
      _launchProjectData.data.weight == 0 || _launchProjectData.data.weight % TOKENS_PER_SLICE != 0
    ) revert INVALID_TOKEN_ISSUANCE();

    // Launch the project.
    _launchProjectFor(_delegateAddress, _launchProjectData);
  }

  //*********************************************************************//
  // ------------------------ internal functions ----------------------- //
  //*********************************************************************//

  /** 
    @notice
    Launches a project.

    @param _owner The address to set as the owner of the project. The project ERC-721 will be owned by this address.
    @param _launchProjectData Data necessary to fulfill the transaction to launch the project.
  */
  function _launchProjectFor(address _owner, JBLaunchProjectData memory _launchProjectData)
    internal
  {
    controller.launchProjectFor(
      _owner,
      _launchProjectData.projectMetadata,
      _launchProjectData.data,
      _launchProjectData.metadata,
      _launchProjectData.mustStartAtOrAfter,
      _launchProjectData.groupedSplits,
      _launchProjectData.fundAccessConstraints,
      _launchProjectData.terminals,
      _launchProjectData.memo
    );
  }
}

/** TODO:
Handle additional params and logic

PARAMS
- Round token allocation, for next FC
- Reserved rate distribution, for next FC
- Round duration, next FC length
- Project token symbol and issuance
  - Can this be increased arbitrarily for subsequent FC? Or can issuance only be reduced with discount rate

LOGIC
- Where to add closeRound requirements?
- `issueSlices`: Add requirement, FC related to blunt round must have been closed
- `issueSlices`: Handle issuance of Project ERC20
*/
