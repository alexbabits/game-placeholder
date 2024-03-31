// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Holds all MATIC sent to the protocol.
contract Funding is Ownable {

    constructor(address initialOwner) Ownable(initialOwner) {}
    receive() external payable {}

    function withdrawAllFunds(address payable to) external onlyOwner {
        (bool success, ) = to.call{value: address(this).balance}("");
        require(success, "Failed to withdraw funds");
    }

    function withdrawSpecificFunds(address payable to, uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient funds in contract");
        (bool success, ) = to.call{value: amount}("");
        require(success, "Failed to withdraw funds");
    }
}