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

        // VRF arguments
        uint64 subscriptionId = 10346; // chainlink subscription ID
        bytes32 keyHash = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c; // VRF gas lane option, Sepolia only has this one
        uint32 callbackGasLimit = 400000; // VRF gas limit for `fulfillRandomWords()` callback execution.
        uint16 requestConfirmations = 3; // VRF number of block confirmations to prevent re-orgs.
        address vrfCoordinator = 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625; // VRF Sepolia coordinator address

        // Deploy Funding
        Funding funding = new Funding(owner);
        console.log("Deployed Funding.sol at address: ", address(funding));

        // Deploy EquipmentVault
        EquipmentVault equipmentVault = new EquipmentVault(owner);
        console.log("Deployed EquipmentVault.sol at address: ", address(equipmentVault));

        // Deploy Game
        Game game = new Game(
            owner, 
            address(funding), 
            address(equipmentVault), 
            subscriptionId, 
            keyHash, 
            callbackGasLimit, 
            requestConfirmations, 
            vrfCoordinator
        );
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