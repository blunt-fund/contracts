// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

contract PriceFeedMock {
  // Mock 1200 USD per ETH for usdc-eth conversion
  function getQuote(
    uint128 usdcBaseAmountXE6,
    address,
    address,
    uint32
  ) external pure returns (uint256 quoteAmount) {
    uint256 weiPerEth = 1e18;
    uint256 usdPerEth = 1.2e9;
    return (usdcBaseAmountXE6 * weiPerEth) / usdPerEth;
  }
}
