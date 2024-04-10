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

import {VRFCoordinatorV2Mock} from "@chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

//Note: Barely started any testing.

contract Testing is Test, StructEnumEventError {
    using Strings for uint256;

    Game game;
    Funding funding;
    EquipmentVault equipmentVault;
    VRFCoordinatorV2Mock coordinator;

    address Alice = address(0xA11CE);
    address Bob = address(0xB0B);
    address Charlie = address(0xC);
    
    string baseURI = "https://bafybeicbsj7vdebm7qpis7fhhpruykpnn6niepcngg2b55gwxtg2nsneri.ipfs.nftstorage.link/";
    uint256 numTokens = 15; // Current number of tokens in the game.

    uint96 baseFee = 1e17; // 0.1 base LINK fee
    uint96 gasPriceLink = 1e9; // gas price

    bytes32 keyHash = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c; // VRF gas lane option, Sepolia only has this one
    uint32 callbackGasLimit = 40000; // VRF gas limit for `fulfillRandomWords()` callback execution.
    uint16 private requestConfirmations = 3; // VRF number of block confirmations to prevent re-orgs.

    function setUp() public {

        // Deploy mock VRF coordinator, setup and fund subscription
        coordinator = new VRFCoordinatorV2Mock(baseFee, gasPriceLink);
        uint64 subscriptionId = coordinator.createSubscription();
        coordinator.fundSubscription(subscriptionId, 1_000_000e18);

        // Deploy contracts
        address Owner = address(this);
        funding = new Funding(Owner);
        equipmentVault = new EquipmentVault(Owner);
        game = new Game(
            Owner, 
            address(funding), 
            address(equipmentVault),
            subscriptionId, 
            keyHash, 
            callbackGasLimit, 
            requestConfirmations, 
            address(coordinator)
        );

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