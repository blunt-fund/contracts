// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8;

import 'forge-std/Script.sol';
import {CREATE3Factory} from 'create3-factory/CREATE3Factory.sol';

import {BluntDelegateProjectDeployer} from 'contracts/BluntDelegateProjectDeployer.sol';
import {BluntDelegateCloner} from 'contracts/BluntDelegateCloner.sol';
import 'contracts/interfaces/IBluntDelegateCloner.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol';

contract DeployScript is Script {
  function run() public returns (BluntDelegateProjectDeployer bluntDeployer) {
    CREATE3Factory create3Factory = CREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);
    bytes32 saltProjectDeployer = keccak256(bytes(vm.envString('SALT_PROJECT_DEPLOYER')));
    bytes32 saltCloner = keccak256(bytes(vm.envString('SALT_CLONER')));
    uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
    address deployerAddress = vm.addr(deployerPrivateKey);

    // MAINNET PARAMS
    // IJBController3_1 jbController = IJBController3_1(0x97a5b9D9F0F7cD676B69f584F29048D0Ef4BB59b);
    // uint256 bluntProjectId = 490;
    // address ethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // address usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // GOERLI PARAMS
    IJBController3_1 jbController = IJBController3_1(0x1d260DE91233e650F136Bf35f8A4ea1F2b68aDB6);
    uint256 bluntProjectId = 314;
    address ethAddress = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
    address usdcAddress = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F;

    vm.startBroadcast(deployerPrivateKey);

    BluntDelegateCloner delegateCloner = BluntDelegateCloner(
      create3Factory.deploy(saltCloner, bytes.concat(type(BluntDelegateCloner).creationCode))
    );

    bluntDeployer = BluntDelegateProjectDeployer(
      create3Factory.deploy(
        saltProjectDeployer,
        bytes.concat(
          type(BluntDelegateProjectDeployer).creationCode,
          abi.encode(
            deployerAddress,
            delegateCloner,
            jbController,
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
