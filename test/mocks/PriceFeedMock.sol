// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

contract PriceFeedMock {
  // Mock 1200 USD per ETH for usdc-eth conversion
  function getQuote(
    uint128 usdcBaseAmountXE6,
    address baseCurrency,
    address,
    uint32
  ) external pure returns (uint256 quoteAmount) {
    uint256 weiPerEth = 1e18;
    uint256 usdPerEth = 1.2e9;
    return
      baseCurrency == address(uint160(uint256(keccak256('eth'))))
        ? (usdcBaseAmountXE6 * usdPerEth) / weiPerEth
        : (usdcBaseAmountXE6 * weiPerEth) / usdPerEth;
  }
}
