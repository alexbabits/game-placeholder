// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Game} from "../src/Game.sol";
// Script to set a new URI associated with a token ID.
// `cast send $Contract "setURIWithId(uint256,string)" 12345 $tokenURI --from $OWNER --rpc-url $MUMBAI_RPC_URL --private-key $PRIVATE_KEY_A`
/*
contract SetURI is Script {
    function run(address deployedAddress) public {
        vm.startBroadcast();
        Game game = Game(deployedAddress);
        console.log("Interacting with game.sol at address: ", address(game));
        uint256 tokenId = 12345; // Example token ID
        string memory tokenURI = "https://{hash}.ipfs.nftstorage.link/{Id}.json"; // Example URI
        game.setURIWithId(tokenId, tokenURI);
        vm.stopBroadcast();
    }
}
*/