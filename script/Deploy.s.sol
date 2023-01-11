// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8;

import 'forge-std/Script.sol';
import {CREATE3Factory} from 'create3-factory/CREATE3Factory.sol';

import {BluntDelegateProjectDeployer} from 'contracts/BluntDelegateProjectDeployer.sol';
import {BluntDelegateDeployer} from 'contracts/BluntDelegateDeployer.sol';
import 'contracts/interfaces/IBluntDelegateDeployer.sol';
import {BluntDelegateCloner} from 'contracts/BluntDelegateCloner.sol';
import 'contracts/interfaces/IBluntDelegateCloner.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol';

contract DeployScript is Script {
  function run() public returns (BluntDelegateProjectDeployer bluntDeployer) {
    CREATE3Factory create3Factory = CREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);
    bytes32 salt = keccak256(bytes(vm.envString('SALT')));
    uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');

    // MAINNET PARAMS
    // IJBController jbController = IJBController(___);
    // IJBOperatorStore jbOperatorStore = IJBOperatorStore(___);
    // uint256 bluntProjectId = ___;
    // address ethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // address usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // GOERLI PARAMS
    IJBController jbController = IJBController(0x7Cb86D43B665196BC719b6974D320bf674AFb395);
    IJBOperatorStore jbOperatorStore = IJBOperatorStore(0x99dB6b517683237dE9C494bbd17861f3608F3585);
    uint256 bluntProjectId = 314;
    address ethAddress = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
    address usdcAddress = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F;

    vm.startBroadcast(deployerPrivateKey);

    IBluntDelegateDeployer delegateDeployer = new BluntDelegateDeployer();
    IBluntDelegateCloner delegateCloner = new BluntDelegateCloner();

    bluntDeployer = BluntDelegateProjectDeployer(
      create3Factory.deploy(
        salt,
        bytes.concat(
          type(BluntDelegateProjectDeployer).creationCode,
          abi.encode(
            delegateDeployer,
            delegateCloner,
            jbController,
            jbOperatorStore,
            bluntProjectId,
            ethAddress,
            usdcAddress,
            350, // maxK, 3.5%
            150, // minK, 1.5%
            2e13, // upperFundraiseBoundary, $20M
            1e11 // lowerFundraiseBoundary, $100k
          )
        )
      )
    );

    vm.stopBroadcast();
  }
}
