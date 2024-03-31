// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Funding} from "../src/Funding.sol";
import {EquipmentVault} from "../src/EquipmentVault.sol";
import {Game} from "../src/Game.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract Deploy is Script {
    using Strings for uint256;

    function run() public {
        vm.startBroadcast();

        // Arguments for contracts
        address owner = msg.sender;
        string memory baseURI = "https://bafybeibmsdabj2hgq6fsirbwfbnxkwbwo6pfwoxdgn3uh7xavtmvfbyy6u.ipfs.nftstorage.link/";

        // Deploy Funding
        Funding funding = new Funding(owner);
        console.log("Deployed Funding.sol at address: ", address(funding));

        // Deploy EquipmentVault
        EquipmentVault equipmentVault = new EquipmentVault(owner);
        console.log("Deployed EquipmentVault.sol at address: ", address(equipmentVault));

        // Deploy Game
        Game game = new Game(owner, address(funding), address(equipmentVault));
        console.log("Deployed Game.sol at address: ", address(game));

        // Post Deployment setters
        equipmentVault.setGameAddress(address(game));
        equipmentVault.renounceOwnership();

        // Generate token URIs
        uint256 numTokens = 15; // Current number of unique tokens in the game.
        game.setBaseURI(baseURI);

        for (uint256 id = 0; id <= numTokens; id++) {
            string memory uri = string(abi.encodePacked(id.toString(), ".json"));
            game.setURIWithID(id, uri);
        }

        vm.stopBroadcast();
    }
}