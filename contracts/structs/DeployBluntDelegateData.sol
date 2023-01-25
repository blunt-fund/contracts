// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

struct DeployBluntDelegateData {
  address projectOwner;
  uint88 hardcap;
  uint88 target;
  uint40 duration;
  bool isTargetUsd;
  bool isHardcapUsd;
}
