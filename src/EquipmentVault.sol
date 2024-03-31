// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {StructEnumEventError} from "./StructEnumEventError.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

// Holds all equipped gear from players so it cannot be transferred/burned while it's equipped.
contract EquipmentVault is ERC1155Holder, Ownable, StructEnumEventError {
    address private game;
    constructor(address initialOwner) Ownable(initialOwner) {}

    function setGameAddress(address _game) external onlyOwner {
        game = _game;
    }

    function transferToVault(address from, uint256 id, uint256 amount, bytes memory data) external {
        if (msg.sender != game) revert NotGameContract();
        IERC1155(game).safeTransferFrom(from, address(this), id, amount, data);
    }

    function transferFromVault(address to, uint256 id, uint256 amount, bytes memory data) external {
        if (msg.sender != game) revert NotGameContract();
        IERC1155(game).safeTransferFrom(address(this), to, id, amount, data);
    }
}