// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ISwap {
    function estimateFromNativeToToken(uint256 amountIn) external view returns (uint256);
    function estimateFromTokenToNative(uint256 amountIn) external view returns (uint256);
    function fromNativeToToken(uint256 amountOutMin) payable external returns (uint256);
    function fromTokenToNative(uint256 amountOutMin) external returns (uint256);
}
