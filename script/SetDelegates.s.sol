// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8;

import 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';

import {IBluntDelegateProjectDeployer} from 'contracts/interfaces/IBluntDelegateProjectDeployer.sol';
import {BluntDelegateDeployer} from 'contracts/BluntDelegateDeployer.sol';
import {BluntDelegateCloner} from 'contracts/BluntDelegateCloner.sol';

contract DeployScript is Script {
  using stdJson for string;

  function run() public {
    bytes32 saltDeployer = keccak256(bytes(vm.envString('SALT_DEPLOYER')));
    bytes32 saltCloner = keccak256(bytes(vm.envString('SALT_CLONER')));
    uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');

    string memory root = vm.projectRoot();
    string memory path = string.concat(root, '/deployment/addresses.json');
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
