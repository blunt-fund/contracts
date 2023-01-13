// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8;

import 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';
import {CREATE3Factory} from 'create3-factory/CREATE3Factory.sol';

import {IBluntDelegateProjectDeployer} from 'contracts/interfaces/IBluntDelegateProjectDeployer.sol';
import {BluntDelegateDeployer} from 'contracts/BluntDelegateDeployer.sol';
import {BluntDelegateCloner} from 'contracts/BluntDelegateCloner.sol';

contract DeployScript is Script {
  using stdJson for string;

  function run() public {
    CREATE3Factory create3Factory = CREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);
    bytes32 saltDeployer = keccak256(bytes(vm.envString('SALT_DEPLOYER')));
    bytes32 saltCloner = keccak256(bytes(vm.envString('SALT_CLONER')));
    uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');

    string memory root = vm.projectRoot();
    string memory path = string.concat(root, '/deployments/addresses.json');
    string memory json = vm.readFile(path);
    IBluntDelegateProjectDeployer bluntDeployer = IBluntDelegateProjectDeployer(
      json.readAddress('BluntDelegateProjectDeployer')
    );

    vm.startBroadcast(deployerPrivateKey);

    BluntDelegateDeployer delegateDeployer = BluntDelegateDeployer(
      create3Factory.deploy(saltDeployer, bytes.concat(type(BluntDelegateDeployer).creationCode))
    );

    BluntDelegateCloner delegateCloner = BluntDelegateCloner(
      create3Factory.deploy(saltCloner, bytes.concat(type(BluntDelegateCloner).creationCode))
    );

    bluntDeployer._setDelegates(delegateDeployer, delegateCloner);

    vm.stopBroadcast();
  }
}
