// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155URIStorage} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IEquipmentVault} from "./IEquipmentVault.sol";
import {Calculate} from "./Calculate.sol";
import {StructEnumEventError} from "./StructEnumEventError.sol";

// Contract that allows minting of tokens and actions from the player
contract Game is ERC1155, ERC1155URIStorage, Ownable, StructEnumEventError {

    uint256 private uID;
    address private funding;
    address private equipmentVault;
    uint256 private characterSalePrice;
    uint256 immutable MAX_CHARACTER_PRICE = 5e18;
    uint8 immutable TELEPORT_TIME = 5; // 5 seconds
    uint8 immutable INN_PRICE = 30; 
    
    mapping(uint8 => uint32) private xpTable; // Level --> total XP required for that level  
    
    mapping(Location => Coordinates) private coordinates; // Location --> (X,Y) coordinates

    mapping(Location => bool) private teleportLocation; // Location --> Valid teleport location?
    mapping(Location => bool) private shopLocation; // Location --> Store exists here?
    mapping(Location => bool) private innLocation; // Location --> Inn exists here?

    mapping(Location => mapping(Token => bool)) private shopSellsItem; // Does the shop sell this item?
    mapping(Location => mapping(Resource => bool)) private areaHasResource; // Does the area have this resource?

    mapping(Token => PriceInfo) private itemPrice; // Item --> Buy and sell price in gold coins.
    mapping(Token => ItemInfo) private itemInfo; // Item --> Item Info (for consumables)
    mapping(Token => GearInfo) private gearInfo; // Item --> Gear Info (for equipment)
    mapping(Token => ToolInfo) private toolInfo; // Item --> Tool Info (for skilling tools)
    mapping(Resource => ResourceInfo) private resourceInfo; // Resource --> Resource Info
    
    mapping(address => mapping(uint256 => bool)) private ownsCharacter; // Does this address own this character (uID)?

    mapping(uint256 => Token) private charToken; // Token of this character (ALICE or BOB).
    mapping(uint256 => bool) private charHardcore; // is this a hardcore character? (per-character basis)
    mapping(uint256 => Location) private charLocation; // current location of this character.
    mapping(uint256 => mapping(Skill => ProficiencyInfo)) private charSkill; // char --> skill --> proficiency info
    mapping(uint256 => mapping(Attribute => ProficiencyInfo)) private charAttribute; // char --> attr --> proficiency info
    mapping(uint256 => Stats) private charStats; // char --> their stats 
    mapping(uint256 => mapping(GearSlot => Token)) private charEquipment; // char --> specific gear slot --> what they have equipped there
    mapping(uint256 => mapping(BoostType => BoostInfo)) private charBoostInfo; // char --> boost info for each boost type. (is boosted & duration).
    mapping(uint256 => uint64) private charActionFinishedAt; // char --> time when an action is finished.

    constructor(address initialOwner, address _funding, address _equipmentVault) ERC1155("") Ownable(initialOwner) {
        funding = _funding;
        equipmentVault = _equipmentVault;
        _setData();        
    }

    // ------------ CHARACTER CREATION ------------

    function mintCharacter(Token tokenID, bool _hardcore) external payable {
        if (tokenID != Token.ALICE && tokenID != Token.BOB) revert NotACharacter();
        if (msg.value != characterSalePrice) revert InvalidAmount();
        if (!isApprovedForAll(msg.sender, address(equipmentVault))) approveEquipmentVault();
        (bool success, ) = funding.call{value: msg.value}("");
        if(!success) revert FailedCall();

        _mintToken(msg.sender, uint256(tokenID), 1);
        _mintToken(msg.sender, uint256(Token.GOLD_COINS), 69);
        _mintToken(msg.sender, uint256(Token.IRON_SWORD), 1);
        _mintToken(msg.sender, uint256(Token.STRENGTH_POTION), 1);

        ++uID;
        uint256 _uID = uID;
        ownsCharacter[msg.sender][_uID] = true;

        charToken[_uID] = tokenID;
        charHardcore[_uID] = _hardcore;
        charLocation[_uID] = Location.LUMBRIDGE_TOWN_SQ;
        charSkill[_uID][Skill.MINING] = ProficiencyInfo(1, 0);    
        charSkill[_uID][Skill.BLACKSMITHING] = ProficiencyInfo(1, 0);    
        charSkill[_uID][Skill.WOODCUTTING] = ProficiencyInfo(1, 0);    
        charSkill[_uID][Skill.WOODWORKING] = ProficiencyInfo(1, 0);    
        charSkill[_uID][Skill.FISHING] = ProficiencyInfo(1, 0);    
        charSkill[_uID][Skill.COOKING] = ProficiencyInfo(1, 0);   
        charSkill[_uID][Skill.LEATHERWORKING] = ProficiencyInfo(1, 0);    
        charSkill[_uID][Skill.CLOTHWORKING] = ProficiencyInfo(1, 0);     
        charSkill[_uID][Skill.ALCHEMY] = ProficiencyInfo(1, 0);    
        charSkill[_uID][Skill.ENCHANTING] = ProficiencyInfo(1, 0);    
        charAttribute[_uID][Attribute.VITALITY] = ProficiencyInfo(1, 0);    
        charAttribute[_uID][Attribute.STRENGTH] = ProficiencyInfo(1, 0);     
        charAttribute[_uID][Attribute.AGILITY] = ProficiencyInfo(1, 0);    
        charAttribute[_uID][Attribute.INTELLIGENCE] = ProficiencyInfo(1, 0);

        // (cmbLvl, maxHP, currentHP, attPower, attInterval, dodge, critChance, critPower, magicPower, prot, accuracy, attRange)   
        charStats[_uID] = Stats(1, 10, 10, 1, 10000, 200, 200, 15000, 0, 0, 8000, 1);
        
        /**
         * We don't have to set `charEquipment`, `charBoostInfo` or `charActionFinishedAt` mappings.
         * The default values for each mapping are the desired initial starting values for the character:

         * `charEquipment[_uID][GearSlot.EACH_SLOT] = Token.NOTHING;` 
         * `charBoostInfo[_uID][BoostType.EACH_TYPE] = BoostInfo(false, 0);`
         * `charActionFinishedAt[_uID] = 0;`      
         */
    }

    // ------------ GAME FUNCTIONS ------------

    function walk(Location to, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        Location playerLocation = charLocation[_uID];
        if (playerLocation == to) revert AlreadyThere();
        Coordinates storage playerCoord = coordinates[playerLocation];
        Coordinates storage destinationCoord = coordinates[to];
        uint64 travelDistance = Calculate.distance(playerCoord.x, playerCoord.y, destinationCoord.x, destinationCoord.y);
        charActionFinishedAt[_uID] = uint64(block.timestamp) + travelDistance;
        charLocation[_uID] = to;
    }

    function buyItem(Location shop, Token item, uint256 amount, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        _atLocationCheck(shop, _uID);
        if(!shopSellsItem[shop][item]) revert NotInStock();
        uint256 goldCoinBalance = balanceOf(msg.sender, uint256(Token.GOLD_COINS)); 
        uint256 pricePerItem = itemPrice[item].buyPrice; 
        uint256 totalPrice = pricePerItem * amount;
        if (goldCoinBalance < totalPrice) revert NotEnoughGold();
        _burnToken(msg.sender, uint256(Token.GOLD_COINS), totalPrice); 
        _mintToken(msg.sender, uint256(item), amount);
    }

    function sellItem(Location shop, Token item, uint256 amount, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        _atLocationCheck(shop, _uID);
        if (!shopLocation[shop]) revert NotShopLocation();
        uint256 pricePerItem = itemPrice[item].sellPrice;
        uint256 totalPrice = pricePerItem * amount;
        _burnToken(msg.sender, uint256(item), amount);
        _mintToken(msg.sender, uint256(Token.GOLD_COINS), totalPrice);
    }

/*
    function consumeItem(Token item, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        
        ItemInfo storage _itemInfo = itemInfo[item];
        if (!_itemInfo.consumable) revert CannotConsume();
        
        BoostInfo storage _charBoostInfo = charBoostInfo[_uID][_itemInfo.boostType];
        if (_charBoostInfo.isBoosted) revert AlreadyBoosted();

        if (_itemInfo.temporary) {
            _charBoostInfo.isBoosted = true;
            _charBoostInfo.duration = uint64(block.timestamp) + _itemInfo.duration;
        }

        // Might be able to match the stat changes to the boost type? Save some space potentially.
        // something like... `_itemInfo[boostType].hp` for the HP amount of the boost?
        // This would fail for an item that has multiple stats that it can boost at once though?
        Stats storage stats = charStats[_uID];
        stats.currentHP += _itemInfo.hp;
        stats.attackPower += _itemInfo.attackPower; 
        stats.attackInterval += _itemInfo.attackInterval; 
        stats.dodgeChance += _itemInfo.dodgeChance; 
        stats.critChance += _itemInfo.critChance; 
        stats.critPower += _itemInfo.critPower; 
        stats.magicPower += _itemInfo.magicPower; 
        stats.protection += _itemInfo.protection; 
        stats.accuracy += _itemInfo.accuracy; 

        if (stats.currentHP > stats.maxHP) stats.currentHP = stats.maxHP; // This is the only stat that could go above a maximum.
        _burnToken(msg.sender, uint256(item), 1);
    }
*/

    function equipGearPiece(Token newGearPiece, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        if (balanceOf(msg.sender, uint256(newGearPiece)) == 0) revert DoNotOwnItem(); 

        IEquipmentVault(equipmentVault).transferToVault(msg.sender, uint256(newGearPiece), 1, "");

        GearInfo storage newGearInfo = gearInfo[newGearPiece]; 
        if (newGearInfo.slot == GearSlot.NULL) revert NotGear(); // Handles Token.NOTHING and any other uninitialized Tokens.

        ProficiencyInfo storage strengthInfo = charAttribute[_uID][Attribute.STRENGTH];
        ProficiencyInfo storage agilityInfo = charAttribute[_uID][Attribute.AGILITY];
        ProficiencyInfo storage intelligenceInfo = charAttribute[_uID][Attribute.INTELLIGENCE];

        if (
            strengthInfo.level < newGearInfo.requiredStrengthLevel || 
            agilityInfo.level < newGearInfo.requiredAgilityLevel ||
            intelligenceInfo.level < newGearInfo.requiredIntelligenceLevel
        ) revert Noob(); 

		Token oldGearPieceSlotMatch = charEquipment[_uID][newGearInfo.slot];
		Token oldGearPieceMainHand = charEquipment[_uID][GearSlot.MAIN_HAND];
		Token oldGearPieceOffHand = charEquipment[_uID][GearSlot.OFF_HAND];
		
		GearInfo storage oldGearPieceMainHandInfo = gearInfo[oldGearPieceMainHand];

        // Can't equip an item you already have equipped
		if (oldGearPieceSlotMatch == newGearPiece) revert AlreadyEquipped();
		
		// Handles all cases for when we want to equip a 2H
		if (newGearInfo.twoHand) {
			if (oldGearPieceMainHand != Token.NOTHING) unequipGearPiece(oldGearPieceMainHand, _uID);
			if (oldGearPieceOffHand != Token.NOTHING) unequipGearPiece(oldGearPieceOffHand, _uID);
		}

		// If we want to equip an off hand, and currently have equipped a 2H, we must unequip the 2H.
		if (newGearInfo.slot == GearSlot.OFF_HAND && oldGearPieceMainHandInfo.twoHand) unequipGearPiece(oldGearPieceMainHand, _uID);

		// In all other cases, we can just unequip the matching piece.
		if (oldGearPieceSlotMatch != Token.NOTHING) unequipGearPiece(oldGearPieceSlotMatch, _uID);

		// And finally, we explicitly equip the newGear to it's corresponding gear slot.
		charEquipment[_uID][newGearInfo.slot] = newGearPiece;

        Stats storage stats = charStats[_uID];
        stats.attackPower += newGearInfo.attackPower; 
        stats.attackInterval += newGearInfo.attackInterval; 
        stats.dodgeChance += newGearInfo.dodgeChance; 
        stats.critChance += newGearInfo.critChance; 
        stats.critPower += newGearInfo.critPower; 
        stats.magicPower += newGearInfo.magicPower; 
        stats.protection += newGearInfo.protection; 
        stats.accuracy += newGearInfo.accuracy; 
        stats.attackRange += newGearInfo.attackRange;
    }

    function unequipGearPiece(Token requestedGearPiece, uint256 _uID) public {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        if (requestedGearPiece == Token.NOTHING) revert CannotUnequipNothing();
        
        GearInfo storage requestedGearInfo = gearInfo[requestedGearPiece];

        Token currentGear = charEquipment[_uID][requestedGearInfo.slot];
        if (currentGear != requestedGearPiece) revert ItemNotEquipped();

        charEquipment[_uID][requestedGearInfo.slot] = Token.NOTHING;
        
        IEquipmentVault(equipmentVault).transferFromVault(msg.sender, uint256(requestedGearPiece), 1, "");

        Stats storage stats = charStats[_uID];
        stats.attackPower -= requestedGearInfo.attackPower; 
        stats.attackInterval -= requestedGearInfo.attackInterval; 
        stats.dodgeChance -= requestedGearInfo.dodgeChance; 
        stats.critChance -= requestedGearInfo.critChance; 
        stats.critPower -= requestedGearInfo.critPower; 
        stats.magicPower -= requestedGearInfo.magicPower; 
        stats.protection -= requestedGearInfo.protection; 
        stats.accuracy -= requestedGearInfo.accuracy; 
        stats.attackRange -= requestedGearInfo.attackRange; 
    }

    function gatherResource(Resource resource, Token tool, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        if (balanceOf(msg.sender, uint256(tool)) == 0) revert DoNotOwnItem();
        
        Location playerLocation = charLocation[_uID];
        if (!areaHasResource[playerLocation][resource]) revert ResourceNotHere();

        ResourceInfo storage _resourceInfo = resourceInfo[resource];
        ToolInfo storage _toolInfo = toolInfo[tool];
        ProficiencyInfo storage proficiencyInfo = charSkill[_uID][_toolInfo.skill];
        if (_toolInfo.skill != Skill.MINING && _toolInfo.skill != Skill.WOODCUTTING && _toolInfo.skill != Skill.FISHING) revert NotTool();
        if (_toolInfo.skill != _resourceInfo.skill) revert WrongToolForTheJob(); 
        if (proficiencyInfo.level < _toolInfo.requiredLevel || proficiencyInfo.level < _resourceInfo.requiredLevel) revert Noob();

        uint16 timeToGather = Calculate.resourceGatheringSpeed(_toolInfo.gatherSpeed, _resourceInfo.gatherSpeed, proficiencyInfo.level);
        charActionFinishedAt[_uID] = uint64(block.timestamp) + timeToGather;

        proficiencyInfo.xp += _resourceInfo.xp;

        if (xpTable[proficiencyInfo.level + 1] <= proficiencyInfo.xp) {
                proficiencyInfo.level++;
                emit SkillLevelUp(_toolInfo.skill, proficiencyInfo.level); 
            }

        _mintToken(msg.sender, uint256(_resourceInfo.material), 1);
    }

/*
    function sleep(Location inn, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        _atLocationCheck(inn, _uID);
        if (!innLocation[inn]) revert NotInnLocation();
        if (balanceOf(msg.sender, uint256(Token.GOLD_COINS)) < INN_PRICE) revert NotEnoughGold();

        // You should be able to sleep at an inn whenever you want, shouldn't have to wait 30 mins for it to wear off before sleeping again.

        _burnToken(msg.sender, uint256(Token.GOLD_COINS), INN_PRICE);

        Stats storage stats = charStats[_uID];
        stats.currentHP = stats.maxHP;
        stats.dodgeChance += 500; // +5%
        stats.critChance += 500; // +5%
        stats.critPower += 2500; // +25%
        stats.accuracy += 500; // +5%

        charBoostInfo[_uID][BoostType.DODGE].isBoosted = true;
        charBoostInfo[_uID][BoostType.DODGE].duration = uint64(block.timestamp) + 600; // 10 mins

        charBoostInfo[_uID][BoostType.CRIT_CHANCE].isBoosted = true;
        charBoostInfo[_uID][BoostType.CRIT_CHANCE].duration = uint64(block.timestamp) + 300; // 5 mins

        charBoostInfo[_uID][BoostType.CRIT_POWER].isBoosted = true;
        charBoostInfo[_uID][BoostType.CRIT_POWER].duration = uint64(block.timestamp) + 300; // 5 mins

        charBoostInfo[_uID][BoostType.ACCURACY].isBoosted = true;
        charBoostInfo[_uID][BoostType.ACCURACY].duration = uint64(block.timestamp) + 1800; // 30 mins
    }
*/

    function _setData() internal {

        // Set Character Minting Price
        characterSalePrice = 5e18;

        // Set Coordinates for locations. The rest can default to 0,0 for now, that's fine. I'll fill them in later.
        coordinates[Location.LUMBRIDGE_TOWN_SQ] = Coordinates(100, 100);
        coordinates[Location.L_GENERAL_STORE] = Coordinates(120, 120);
        coordinates[Location.FOREST_ONE] = Coordinates(150, 150);

        // Set valid store locations. All other locations are false by default.
        shopLocation[Location.L_GENERAL_STORE] = true;
        shopLocation[Location.F_GENERAL_STORE] = true;
        shopLocation[Location.V_GENERAL_STORE] = true;

        // Set valid inn locations. All other locations are false by default.
        innLocation[Location.L_INN] = true;
        innLocation[Location.F_INN] = true;
        innLocation[Location.V_INN] = true;

        // Set buy and sell item prices. (buyPrice, sellPrice). Player buys item for buyPrice, sells item for sellPrice.
        itemPrice[Token.IRON_SWORD] = PriceInfo(40, 20);
        itemPrice[Token.STRENGTH_POTION] = PriceInfo(15, 5);
        itemPrice[Token.IRON_HATCHET] = PriceInfo(25, 10);

        // Set the items that each stores sells. (All stores can buy any item from player).
        shopSellsItem[Location.L_GENERAL_STORE][Token.IRON_HATCHET] = true;
        shopSellsItem[Location.L_GENERAL_STORE][Token.IRON_SWORD] = true;
        shopSellsItem[Location.L_GENERAL_STORE][Token.STRENGTH_POTION] = true;
        shopSellsItem[Location.F_GENERAL_STORE][Token.IRON_HATCHET] = true;
        shopSellsItem[Location.F_GENERAL_STORE][Token.IRON_SWORD] = true;
        shopSellsItem[Location.F_GENERAL_STORE][Token.STRENGTH_POTION] = true;
        shopSellsItem[Location.V_GENERAL_STORE][Token.IRON_HATCHET] = true;
        shopSellsItem[Location.V_GENERAL_STORE][Token.IRON_SWORD] = true;
        shopSellsItem[Location.V_GENERAL_STORE][Token.STRENGTH_POTION] = true;

        // Set resource info.
        resourceInfo[Resource.NORMAL_TREE] = ResourceInfo(Token.NORMAL_WOOD, Skill.WOODCUTTING, 1, 50, 5);
        resourceInfo[Resource.OAK_TREE] = ResourceInfo(Token.OAK_WOOD, Skill.WOODCUTTING, 15, 150, 15);
        resourceInfo[Resource.WILLOW_TREE] = ResourceInfo(Token.WILLOW_WOOD, Skill.WOODCUTTING, 30, 400, 35);
        resourceInfo[Resource.MAPLE_TREE] = ResourceInfo(Token.MAPLE_WOOD, Skill.WOODCUTTING, 45, 1000, 70);
        resourceInfo[Resource.YEW_TREE] = ResourceInfo(Token.YEW_WOOD, Skill.WOODCUTTING, 60, 2500, 140);
        resourceInfo[Resource.MAGIC_TREE] = ResourceInfo(Token.MAGIC_WOOD, Skill.WOODCUTTING, 75, 6000, 250);

        // Set the resource that each resource location has.
        areaHasResource[Location.FOREST_ONE][Resource.NORMAL_TREE] = true;
        areaHasResource[Location.FOREST_TWO][Resource.OAK_TREE] = true;
        areaHasResource[Location.FOREST_THREE][Resource.WILLOW_TREE] = true;
        areaHasResource[Location.FOREST_FOUR][Resource.MAPLE_TREE] = true;
        areaHasResource[Location.FOREST_FIVE][Resource.YEW_TREE] = true;
        areaHasResource[Location.FOREST_FIVE][Resource.MAGIC_TREE] = true;
        areaHasResource[Location.MINE_ONE][Resource.IRON_VEIN] = true;
        areaHasResource[Location.MINE_TWO][Resource.COAL_VEIN] = true;

        // Set tool info (hatchets, pickaxes, etc.)
        toolInfo[Token.IRON_HATCHET] = ToolInfo(Skill.WOODCUTTING, 1, 10); // maybe make 10000 = 100% speed
        toolInfo[Token.STEEL_HATCHET] = ToolInfo(Skill.WOODCUTTING, 15, 15);
        toolInfo[Token.IRON_PICKAXE] = ToolInfo(Skill.MINING, 1, 10);

        // Set gear info (type, STR/AGIL/INT, attPower, attSpeed, dodge, critChance, critPower, magicPower, prot, accuracy, attackRange)
        gearInfo[Token.IRON_SWORD] = GearInfo(GearSlot.MAIN_HAND, false, 1, 0, 0, 10, 500, 0, 100, 1000, 0, 0, 1000, 0);
        gearInfo[Token.RING_OF_BLOOD] = GearInfo(GearSlot.MAIN_HAND, false, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0);
        gearInfo[Token.IRON_2H_SWORD] = GearInfo(GearSlot.MAIN_HAND, true, 1, 0, 0, 10, 500, 0, 100, 1000, 0, 0, 1000, 0);

        // Set item info for consumables (boost type, temporary, duration, hp, attPower, attInterval, dodge, critChance, critPower, magicPower, prot, accuary)
        itemInfo[Token.HEALTH_POTION] = ItemInfo(BoostType.HP, true, false, 0, 10, 0, 0, 0, 0, 0, 0, 0, 0);
        itemInfo[Token.STRENGTH_POTION] = ItemInfo(BoostType.ATTACK_POWER, true, true, 600, 0, 10, 0, 0, 0, 0, 0, 0, 0);
        itemInfo[Token.PROTECTION_POTION] = ItemInfo(BoostType.PROTECTION, true, true, 600, 0, 0, 0, 0, 0, 0, 0, 10, 0);

        // Set Experience table. (Do the rest later)
        xpTable[1] = 0;
        xpTable[2] = 500;
        xpTable[3] = 1050; // 500 + 550
        xpTable[4] = 1650; // 1050 + 600
        xpTable[5] = 2300; // 1650 + 650
        xpTable[6] = 3000; // 2300 + 700
        xpTable[7] = 3750; // 3000 + 750
        xpTable[8] = 4550; // 3750 + 800
        xpTable[9] = 5400; // 4550 + 850
        xpTable[10] = 6300; // 5400 + 900

        // Set valid teleport locations. All other locations are false by default.
        teleportLocation[Location.LUMBRIDGE_TOWN_SQ] = true;
        teleportLocation[Location.FALADOR_TOWN_SQ] = true;
        teleportLocation[Location.VELRICK_TOWN_SQ] = true;
    }   

    // ------------ HELPER FUNCTIONS ------------

    function _ownsCharacterCheck(address player, uint256 _uID) internal view {
        if (!ownsCharacter[player][_uID]) revert DoesNotOwnCharacter();
    }

    function _doingSomethingCheck(uint256 _uID) internal view {
        if (charActionFinishedAt[_uID] > block.timestamp) revert StillDoingAction();
    }

    function _atLocationCheck(Location place, uint256 _uID) internal view {
        if (charLocation[_uID] != place) revert NotAtLocation();
    }

    function _mintToken(address player, uint256 id, uint256 amount) internal {
        _mint(player, id, amount, "");
    }

    function _burnToken(address player, uint256 id, uint256 amount) internal {
        _burn(player, id, amount);
    }

    function approveEquipmentVault() public {
        setApprovalForAll(address(equipmentVault), true);
    }

    // ------------ OWNER FUNCTIONS ------------
    
    function changeCharacterMintingPrice(uint256 newPrice) external onlyOwner {
        if (newPrice > MAX_CHARACTER_PRICE) revert MintingTooExpensive();
        characterSalePrice = newPrice; // Good for holiday discounts, price never increases beyond maximum.
    }

    function setURIWithID(uint256 tokenID, string memory tokenURI) external onlyOwner {
        _setURI(tokenID, tokenURI); // See ERC1155URIStorage._setURI(). (NOT ERC1155._setURI()?)
    }

    function setBaseURI(string memory baseURI) external onlyOwner {
        _setBaseURI(baseURI); // See ERC1155URIStorage._setBaseURI().
    }


    // ------------ OPTIONAL & REQUIRED OVERRIDES ------------

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal override(ERC1155) {
        if (from != address(0)) {
            for (uint256 i = 0; i < ids.length; ++i) {
                if (uint256(Token.ALICE) == ids[i] || uint256(Token.BOB) == ids[i]) revert CannotTransferCharacters();  
            }
        }
        super._update(from, to, ids, values);
    }

    function uri(uint256 tokenId) public view override(ERC1155, ERC1155URIStorage) returns (string memory) {
        return super.uri(tokenId);
    }
}




/*
    function craftItem() public {
        // crafting requires `mats`, but there are two types.

        // 1. actually consumable mats that will get burned (ex: 5 steel bars or 3 normal_wood)
        // 2. needles, hammers, knives, chisel, etc. These are secondary tools that you'll need. (Match them with their skill type too!).


        // At the blacksmith, you can 1. do smithing stuff like smelt ore, and turn bars into gear (as long as you have a hammer). 
        // AND it acts as a shop location as well, to trade with the blacksmith. So we set the location to `true` for shop and for this crafting stuff.
    }

    function fightEnemy(Enemy enemy, uint256 _uID) public {
        // Check stat boosts. If expired... we need a way to decrement that stats back down based on what was consumed.
        // Fight the enemy (monster, boss, etc.)
        // Gain XP and loot
        // If XP gained yields a level up, then level up.
        // If he dies, he `_died()`.
    }

    function _died(address user) internal {
        CharacterInfo storage charInfo = characterInfo[user];
        charInfo.hardcore ? _hardcoreDeath() : _normalDeath();
    }

    function _normalDeath() internal {
        // respawn in lumby in tact.
    }

    function _hardcoreDeath() internal {
        // burn their NFT and set all their mappings and structs to defaults.
        // Get user's character info, if they have a character, burn it, and reset the mapping. _burnToken(user, tokenId, 1);
        // require that the owner mapping is now 0 (owns nothing), and do balanceOf(NFT) to verify it doesnt exist. Require that.
    }
*/


/*
    function teleport(Location to, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        CharacterInfo storage charInfo = characterInfo[_uID];
        if (!teleportLocation[to]) revert NotTeleportLocation();
        if (charInfo.location == to) revert AlreadyThere();
        if (charInfo.actionFinishedTime > block.timestamp) revert StillDoingAction();

        //uint8 intelligenceLevel = charInfo.attributes.intelligenceInfo.level; // players current INT level
        //uint32 intelligenceXP = charInfo.attributes.intelligenceInfo.xp; // players current INT xp.

        // For the spell, we need information about the spell 1. It's runes (Tokens) 2. It's level requirement to cast.
        // Maybe even a mapping from location to the spell mapping.

        //if (intelligenceLevel < _spellInfo.level) revert Noob(); // require INT level high enough for specific spell.
        //if (balanceOf(msg.sender, uint256(_spellInfo.RuneOne)) == 0); // require player has enough runes to teleport to `to` location.
        //if (balanceOf(msg.sender, uint256(_spellInfo.RuneTwo)) == 0); // require player has enough runes to teleport to `to` location.

        // decrement the runes here, via _burnBatch(); or _burn();
        // gain INT experience based on which spell was cast. If enough XP, gain a level.
        charInfo.actionFinishedTime = uint64(block.timestamp) + TELEPORT_TIME; 
        charInfo.location = to; 
    }
*/