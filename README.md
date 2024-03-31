
Local Deployment: 
1. `anvil --block-time 5` if you want mined blocks every 5 seconds, or just `anvil`.
2. `forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast`

WARNING!!! IF YOU ADD/REMOVE CONTRACTS THESE ADDRESSES WILL CHANGE

Local Interactions:
// Variables
1. `export OWNER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"; export FUNDING="0x5FbDB2315678afecb367f032d93F642f64180aa3"; export GAME="0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"; export CHAR_PRICE=5000000000000000000`

// Tips
1. `cast block` // gets current block, Also look back at the Anvil terminal.
2. `cast call $GAME "uri(uint256)" 5` // returns URI for token ID 5.

// Character Creation
1. `cast send $GAME --unlocked --from $OWNER "mintCharacter(uint8,bool)" 1 false --value $CHAR_PRICE` // mints character
2. `cast call $GAME "getCharacterInfo(address)" $OWNER` // All their info (NEED PUBLIC GETTER)
3. `cast call $GAME "ownsCharacter(address)" $OWNER` // 0x01 = true (NEED PUBLIC GETTER)
4. `cast balance $FUNDING` // funding contract received 5 MATIC payment.
5. `cast call $GAME "balanceOf(address,uint256)" $OWNER 1` // User owns 1 character.
6. `cast call $GAME "balanceOf(address,uint256)" $OWNER 5` // User owns 3 gold.

// Travel to shop, buy axe, equip it, chop some trees
1. `cast send $GAME --unlocked --from $OWNER "walk(uint8)" 4` // walk from lumby (spawned there) to general store (4) (DBLE CHECK TIME & ORIG LOCATION)
2. `cast send $GAME --unlocked --from $OWNER "buyItem(uint8,uint8,uint256)" 4 9 1` // from store (4), buy iron hatchet (9) quantity (1) for 2gp
3. `cast call $GAME "balanceOf(address,uint256)" $OWNER 9` // owns iron hatchet
4. `cast call $GAME "balanceOf(address,uint256)" $OWNER 5` // owns less gold
5. `cast send $GAME --unlocked --from $OWNER "equipItem(uint8)" 9` // equip iron hatchet
6. `cast send $GAME --unlocked --from $OWNER "walk(uint8)" 33` // walk from general store to forest (33)
7. `cast send $GAME --unlocked --from $OWNER "chopTree(uint8)" 0` // chop a normal tree (0)
8. `cast call $GAME "balanceOf(address,uint256)" $OWNER 11` // gets 1 log (11)







Mumbai Deployment: 
1. `forge script script/Deploy.s.sol --rpc-url $MUMBAI_RPC_URL --private-key $PRIVATE_KEY_A`


Mumbai Interactions:
