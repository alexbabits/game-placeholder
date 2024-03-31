// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEquipmentVault {
    function transferToVault(address from, uint256 id, uint256 amount, bytes memory data) external;
    function transferFromVault(address to, uint256 id, uint256 amount, bytes memory data) external;
}