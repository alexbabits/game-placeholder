// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155URIStorage} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Calculate} from "./Calculate.sol";
import {StructEnumEventError} from "./StructEnumEventError.sol";

import {IEquipmentVault} from "./IEquipmentVault.sol";

// Contract that allows minting of tokens and actions from the player
contract Game is ERC1155, ERC1155URIStorage, Ownable, StructEnumEventError {

    uint256 private uID;
    address private funding;
    address private equipmentVault;
    uint256 private characterSalePrice;
    uint256 immutable MAX_CHARACTER_PRICE = 5e18;
    uint8 immutable TELEPORT_TIME = 5;
    
    mapping(uint8 => uint32) private xpTable; // Level --> total XP required for that level  
    
    mapping(Location => Coordinates) private coordinates; // Location --> (X,Y) coordinates
    mapping(Location => bool) private teleportLocation; // Location --> Is this a valid teleport location?
    mapping(Location => bool) private shopLocation; // Location --> Is this a store?
    mapping(Location => mapping(Token => bool)) private shopSellsItem; // Does a shop sell this item?
    mapping(Location => mapping(Resource => bool)) private areaHasResource; // Does an area have this resource?

    mapping(Token => PriceInfo) private itemPrice; // Item --> Buy and sell price in gold coins.
    mapping(Token => GearInfo) private gearInfo; // Item --> Gear Info
    mapping(Token => ToolInfo) private toolInfo; // Item --> Tool Info
    mapping(Resource => ResourceInfo) private resourceInfo; // Resource --> Resource Info
    
    mapping(address => mapping(uint256 => bool)) private ownsCharacter; // Does this address own this character (uID)?

    mapping(uint256 => Token) private charToken; // Token of this character (ALICE or BOB).
    mapping(uint256 => bool) private charHardcore; // is this a hardcore character? (per-character basis)
    mapping(uint256 => Location) private charLocation; // current location of this character.
    mapping(uint256 => mapping(Skill => ProficiencyInfo)) private charSkill; // char --> skill --> info about that skill for them
    mapping(uint256 => mapping(Attribute => ProficiencyInfo)) private charAttribute; // char --> attr --> info about that attr for them
    mapping(uint256 => Stats) private charStats; // char --> their stats 
    mapping(uint256 => mapping(GearSlot => Token)) private charEquipment; // char --> specific gear slot --> what they have equipped there
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

        _mint(msg.sender, uint256(tokenID), 1, ""); 
        _mint(msg.sender, uint256(Token.GOLD_COINS), 69, ""); 
        _mint(msg.sender, uint256(Token.IRON_SWORD), 1, "");
        
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
        charStats[_uID] = Stats({
            combatLevel: 1,
            maxHP: 10,
            currentHP: 10,
            attackPower: 1,
            attackSpeed: 10000,
            dodgeChance: 200,
            critChance: 200,
            critPower: 15000,
            magicPower: 0,
            protection: 0,
            accuracy: 8000,
            attackRange: 1
        });
        charEquipment[_uID][GearSlot.MAIN_HAND] = Token.NOTHING;
        charEquipment[_uID][GearSlot.OFF_HAND] = Token.NOTHING;
        charEquipment[_uID][GearSlot.HEAD] = Token.NOTHING;
        charEquipment[_uID][GearSlot.CHEST] = Token.NOTHING;
        charEquipment[_uID][GearSlot.LEGS] = Token.NOTHING;
        charEquipment[_uID][GearSlot.GLOVES] = Token.NOTHING;
        charEquipment[_uID][GearSlot.BOOTS] = Token.NOTHING;
        charEquipment[_uID][GearSlot.CLOAK] = Token.NOTHING;
        charEquipment[_uID][GearSlot.RING_ONE] = Token.NOTHING;
        charEquipment[_uID][GearSlot.RING_TWO] = Token.NOTHING;
        charEquipment[_uID][GearSlot.AMULET] = Token.NOTHING;
        charActionFinishedAt[_uID] = uint64(block.timestamp);
    }

    // ------------ GAME FUNCTIONS ------------

    function walk(Location to, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        Location playerLocation = charLocation[_uID];
        if (charLocation[_uID] == to) revert AlreadyThere();
        Coordinates storage playerCoord = coordinates[playerLocation];
        Coordinates storage destinationCoord = coordinates[to];
        uint64 travelDistance = Calculate.distance(playerCoord.x, playerCoord.y, destinationCoord.x, destinationCoord.y);
        charActionFinishedAt[_uID] = uint64(block.timestamp) + travelDistance;
        charLocation[_uID] = to;
    }

    function buyItem(Location shop, Token item, uint256 amount, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        if (charLocation[_uID] != shop) revert NotAtLocation();
        if(!shopSellsItem[shop][item]) revert NotInStock();
        uint256 goldCoinBalance = balanceOf(msg.sender, uint256(Token.GOLD_COINS)); 
        uint256 pricePerItem = itemPrice[item].buyPrice; 
        uint256 totalPrice = pricePerItem * amount;
        if (goldCoinBalance < totalPrice) revert NotEnoughGold();
        _burn(msg.sender, uint256(Token.GOLD_COINS), totalPrice); 
        _mint(msg.sender, uint256(item), amount, "");
    }

    function sellItem(Location shop, Token item, uint256 amount, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        if (!shopLocation[shop]) revert NotShopLocation();
        if (charLocation[_uID] != shop) revert NotAtLocation();
        uint256 pricePerItem = itemPrice[item].sellPrice;
        uint256 totalPrice = pricePerItem * amount;
        _burn(msg.sender, uint256(item), amount); // (Player owns item?) is explicitly checked through `_burn()`.
        _mint(msg.sender, uint256(Token.GOLD_COINS), totalPrice, "");
    }

    function equipGearPiece(Token newGearPiece, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        if (balanceOf(msg.sender, uint256(newGearPiece)) == 0) revert DoNotOwnItem(); 

        IEquipmentVault(equipmentVault).transferToVault(msg.sender, uint256(newGearPiece), 1, "");

        GearInfo storage newGearInfo = gearInfo[newGearPiece]; 
        if (newGearInfo.slot == GearSlot.NULL) revert NotGear(); 

        ProficiencyInfo storage strengthInfo = charAttribute[_uID][Attribute.STRENGTH];
        ProficiencyInfo storage agilityInfo = charAttribute[_uID][Attribute.AGILITY];
        ProficiencyInfo storage intelligenceInfo = charAttribute[_uID][Attribute.INTELLIGENCE];

        if (
            strengthInfo.level < newGearInfo.requiredStrengthLevel || 
            agilityInfo.level < newGearInfo.requiredAgilityLevel ||
            intelligenceInfo.level < newGearInfo.requiredIntelligenceLevel
        ) revert Noob(); 

        Token oldGearPiece = charEquipment[_uID][newGearInfo.slot];
        if (oldGearPiece == newGearPiece) revert AlreadyEquipped(); 
        if (oldGearPiece != Token.NOTHING) unequipGearPiece(oldGearPiece, _uID);
        
        charEquipment[_uID][newGearInfo.slot] = newGearPiece; 

        Stats storage stats = charStats[_uID];

        stats.attackPower += newGearInfo.attackPower; 
        stats.attackSpeed += newGearInfo.attackSpeed; 
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
        stats.attackSpeed -= requestedGearInfo.attackSpeed; 
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
        if (!areaHasResource[playerLocation][resource]) revert NotAtLocation();

        ResourceInfo storage _resourceInfo = resourceInfo[resource];
        ToolInfo storage _toolInfo = toolInfo[tool];
        ProficiencyInfo storage proficiencyInfo = charSkill[_uID][_toolInfo.skill];
        if (_toolInfo.skill != Skill.MINING && _toolInfo.skill != Skill.WOODCUTTING && _toolInfo.skill != Skill.FISHING) revert InvalidTool();
        if (_toolInfo.skill != _resourceInfo.skill) revert WrongToolForTheJob(); 
        if (proficiencyInfo.level < _toolInfo.requiredLevel || proficiencyInfo.level < _resourceInfo.requiredLevel) revert Noob();

        uint16 timeToGather = Calculate.resourceGatheringSpeed(_toolInfo.gatherSpeed, _resourceInfo.gatherSpeed, proficiencyInfo.level);
        charActionFinishedAt[_uID] = uint64(block.timestamp) + timeToGather;

        proficiencyInfo.xp += _resourceInfo.xp;

        if (xpTable[proficiencyInfo.level + 1] <= proficiencyInfo.xp) {
                proficiencyInfo.level++;
                emit SkillLevelUp(_toolInfo.skill, proficiencyInfo.level); 
            }

        _mint(msg.sender, uint256(_resourceInfo.material), 1, "");
    }

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

        // Set buy and sell item prices
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

        // Set gear info (type, STR/AGIL/INT, attPower, attSpeed, dodge, critChance, critPower, magicPower, prot, accuracy, attackRange);
        gearInfo[Token.IRON_SWORD] = GearInfo(GearSlot.MAIN_HAND, 1, 0, 0, 10, 500, 0, 100, 1000, 0, 0, 1000, 0);
        gearInfo[Token.RING_OF_BLOOD] = GearInfo(GearSlot.MAIN_HAND, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0);

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

    function approveEquipmentVault() public {
        setApprovalForAll(address(equipmentVault), true);
    }

    // ------------ OWNER FUNCTIONS ------------
    
    function changeCharacterMintingPrice(uint256 newPrice) external onlyOwner {
        if (newPrice > MAX_CHARACTER_PRICE) revert MintingTooExpensive();
        characterSalePrice = newPrice; // Good for holiday discounts, price never increases.
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
    function craftItem() public {}

    function sleep() public {
        // sleep at an Inn, restore heatlh, maybe minor buff
    }

    function useItem() public {
        // Use potion, burn the potion, then apply the effect through _potionEffect(potion type);
        // Usable items (potions, food, inn boosts, etc.) only effect `Stats` as well.
    }

    function fightMonster() public {
        // Must have a character
        // Fight the monster
        // Gain XP and loot
        // If XP gained yields a level up, then level up.
        // If he dies, he dies.
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