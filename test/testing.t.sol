// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {StructEnumEventError} from "../src/StructEnumEventError.sol";
import {Game} from "../src/Game.sol";
import {Funding} from "../src/Funding.sol";
import {EquipmentVault} from "../src/EquipmentVault.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract Testing is Test, StructEnumEventError {
    using Strings for uint256;

    Game game;
    Funding funding;
    EquipmentVault equipmentVault;

    address Alice = address(0xA11CE);
    address Bob = address(0xB0B);
    address Charlie = address(0xC);
    
    string baseURI = "https://bafybeicbsj7vdebm7qpis7fhhpruykpnn6niepcngg2b55gwxtg2nsneri.ipfs.nftstorage.link/";
    uint256 numTokens = 15; // Current number of tokens in the game.

    function setUp() public {

        address Owner = address(this);
        funding = new Funding(Owner);
        equipmentVault = new EquipmentVault(Owner);
        game = new Game(Owner, address(funding), address(equipmentVault));

        equipmentVault.setGameAddress(address(game));
        equipmentVault.renounceOwnership();

        game.setBaseURI(baseURI);

        for (uint256 id = 0; id <= numTokens; id++) {
            string memory uri = string(abi.encodePacked(id.toString(), ".json"));
            game.setURIWithID(id, uri);
        }
    }

    function test_Basics() public {
        // Note: The first minted character has uID is 1.
        vm.deal(Alice, 10e18);
        vm.startPrank(Alice);
        game.mintCharacter{value: 5e18}(Token.ALICE, false); 

        game.walk(Location.L_GENERAL_STORE, 1);
        vm.warp(block.timestamp + 100); // idk exact time for travel.

        game.buyItem(Location.L_GENERAL_STORE, Token.IRON_HATCHET, 1, 1);

        game.walk(Location.FOREST_ONE, 1);
        vm.warp(block.timestamp + 1000);

        vm.expectRevert();
        game.sellItem(Location.FOREST_ONE, Token.IRON_SWORD, 1, 1);

        game.equipGearPiece(Token.IRON_SWORD, false, 1);
        game.unequipGearPiece(Token.IRON_SWORD, GearSlot.MAIN_HAND, 1);
        game.equipGearPiece(Token.IRON_SWORD, false, 1);

        game.gatherResource(Resource.NORMAL_TREE, Token.IRON_HATCHET, 1);
        vm.warp(block.timestamp + 2000);

        //game.consumeItem(Token.STRENGTH_POTION, 1);


        vm.stopPrank();
    }

}