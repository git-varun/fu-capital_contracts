// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IEsketitPriceModule {
    function getPriceInUSD(address) external view returns (uint256);
    function getPriceInEUR(address) external view returns (uint256);
}
