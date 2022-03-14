// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IFastVault {
    function TOKEN() external view returns (address);
    function borrowFor(address receiver, uint256 amount, bytes calldata _sig) external returns (uint256);
    function mint(address receiver, uint256 _amount, bytes32 _nHash, bytes calldata _sig) external;
}