// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155URIStorage} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IEquipmentVault} from "./IEquipmentVault.sol";
import {Calculate} from "./Calculate.sol";
import {StructEnumEventError} from "./StructEnumEventError.sol";

// Contains all the logic for the game.
contract Game is ERC1155, ERC1155URIStorage, Ownable, StructEnumEventError {

    uint256 private uID;
    uint256 private characterSalePrice;
    
    address private funding;
    address private equipmentVault;
    uint64 immutable MAX_CHARACTER_PRICE = 5e18;
    uint8 immutable INN_PRICE = 30;
    uint16 immutable ONE_HOUR = 3600;
    uint16 immutable PERCENTAGE = 10000;
    
    mapping(uint8 => uint32) private xpTable; // Level --> total XP required for that level  
    
    mapping(Location => Coordinates) private coordinates; // Location --> (X,Y) coordinates

    mapping(Location => bool) private shopLocation; // Location --> Store exists here?
    mapping(Location => bool) private innLocation; // Location --> Inn exists here?

    mapping(Location => mapping(Token => bool)) private shopSellsItem; // Does the shop sell this item?
    mapping(Location => mapping(Resource => bool)) private areaHasResource; // Does the area have this resource?
    mapping(Location => mapping(Skill => bool)) private validCraftingArea; // Does this Location allow a specific crafting skill to be done?

    mapping(Token => PriceInfo) private itemPrice; // Item --> Buy and sell price in gold coins.
    mapping(Token => GearInfo) private gearInfo; // Item --> Gear Info (for equipment)
    mapping(Token => ConsumableInfo) private consumableInfo; // item --> consumable info
    mapping(Token => ToolInfo) private toolInfo; // Item --> Tool Info (for skilling tools)
    mapping(Token => CraftingInfo) private craftingInfo; // Item --> Crafting Info (for crafting any output product)
    mapping(Token => Element) private element; // (Staff/Wand) --> element type.
    mapping(Resource => ResourceInfo) private resourceInfo; // Resource --> Resource Info
    
    mapping(Stat => int16) private innBuffValues; // buff values for sleeping at an inn.
    mapping(BuffSpell => SpellInfo) private buffSpellInfo; // Spell buff -> it's info
    mapping(BuffSpell => BuffSpellEffects) private buffSpellEffects; // Spell buff --> it's effects
    mapping(CombatSpell => SpellInfo) private combatSpellInfo; // combat spell -> it's info
    mapping(CombatSpell => CombatSpellEffects) private combatSpellEffects; // combat spell -> it's effects
    mapping(TeleportSpell => TeleportSpellInfo) private teleportSpellInfo; // tele spell -> all it's info+location

    mapping(address => mapping(uint256 => bool)) private ownsCharacter; // Does this address own this character (uID)?

    mapping(uint256 => Token) private charToken; // Token of this character (ALICE or BOB).
    mapping(uint256 => bool) private charHardcore; // is this a hardcore character? (per-character basis)
    mapping(uint256 => Location) private charLocation; // current location of this character.
    mapping(uint256 => mapping(Skill => ProficiencyInfo)) private charSkill; // char --> skill --> proficiency info
    mapping(uint256 => mapping(Attribute => ProficiencyInfo)) private charAttribute; // char --> attr --> proficiency info
    mapping(uint256 => mapping(Stat => int16)) private charStat; // char --> specific stat --> value (Can change int16 into `StatInfo`)
    mapping(uint256 => mapping(GearSlot => Token)) private charEquipment; // char --> specific gear slot --> what they have equipped there
    mapping(uint256 => BuffSpellsApplied) private charBuffSpellsApplied; // char --> magic buffs currently applied
    mapping(uint256 => ConsumableBuffsApplied) private charConsumableBuffsApplied; // char --> consumable buffs applied
    mapping(uint256 => uint64) private charInnBuffExpiration; // char --> inn buff expiration time.
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
        charStat[_uID][Stat.CMB_LVL] = 1;
        charStat[_uID][Stat.MAX_HP] = 10;
        charStat[_uID][Stat.HP] = 10;
        charStat[_uID][Stat.ATT_POWER] = 5;
        charStat[_uID][Stat.ATT_FREQ] = 10000;
        charStat[_uID][Stat.ATT_RANGE] = 1;
        charStat[_uID][Stat.DODGE_CHANCE] = 200;
        charStat[_uID][Stat.CRIT_CHANCE] = 200;
        charStat[_uID][Stat.CRIT_POWER] = 15000;
        charStat[_uID][Stat.MAGIC_POWER] = 0;
        charStat[_uID][Stat.PROTECTION] = 0;
        charStat[_uID][Stat.ACCURACY] = 8000;

        /**
         * To keep contract size low, the default initialization values for some  
         * character specific mappings are sufficient and do not need to be explicitly set:

         * `charEquipment`: `charEquipment[_uID][GearSlot.EACH_SLOT] = Token.NOTHING;`
         * `charActionFinishedAt`: `charActionFinishedAt[_uID] = 0;` // immediately free to do anything upon character creation
         * `charInffBuffExpiration`: `charInnBuffExpiration[_uID] = 0;` // 0 = expiration in the past, do not receive any temporary buffs.
         * `charBuffSpellsApplied`: `charBuffSpellsApplied[_uID] = BuffSpellsApplied(BuffSpell.NONE, BuffSpell.NONE, 0, 0);` 
         * `charConsumableBuffsApplied`: `charConsumableBuffsApplied[_uID] = ConsumableBuffsApplied(Token.NOTHING, Token.NOTHING, 0, 0);`
         
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

    function castTeleport(TeleportSpell teleportSpell, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        
		TeleportSpellInfo storage _teleportSpellInfo = teleportSpellInfo[teleportSpell]; // Load info about the spell
		if (charLocation[_uID] == _teleportSpellInfo.destination) revert AlreadyThere(); // Can't teleport to where you already are
		_burnToken(msg.sender, uint256(Token.ESSENCE_CRYSTAL), _teleportSpellInfo.numberOfEssenceCrystals); // burns crystals.

		// If player does not have the right kind of staff or wand equipped, cannot teleport.
		Token equippedWeapon = charEquipment[_uID][GearSlot.MAIN_HAND];
		if(element[equippedWeapon] != Element.AIR || element[equippedWeapon] != Element.OMNI) revert InvalidWeaponElementType();

		// Must have required level. Gain XP, level up INT if gained enough XP. Lastly, update character's location to tele destination.
		ProficiencyInfo storage charProficiency = charAttribute[_uID][Attribute.INTELLIGENCE];
		if (charProficiency.level < _teleportSpellInfo.requiredLevel) revert Noob(); 

		charProficiency.xp += _teleportSpellInfo.xp; 

		if (xpTable[charProficiency.level + 1] <= charProficiency.xp) {
			charProficiency.level++;
			emit AttributeLevelUp(Attribute.INTELLIGENCE, charProficiency.level);
		}

		charLocation[_uID] = _teleportSpellInfo.destination;
	}

    function buyItem(Location shop, Token item, uint256 amount, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        _atLocationCheck(shop, _uID);
        if(!shopSellsItem[shop][item]) revert NotInStock();
        uint256 totalPrice = itemPrice[item].buyPrice * amount;
        _burnToken(msg.sender, uint256(Token.GOLD_COINS), totalPrice); 
        _mintToken(msg.sender, uint256(item), amount);
    }

    function sellItem(Location shop, Token item, uint256 amount, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        _atLocationCheck(shop, _uID);
        if (!shopLocation[shop]) revert NotShopLocation();
        uint256 totalPrice = itemPrice[item].sellPrice * amount;
        _burnToken(msg.sender, uint256(item), amount); 
        _mintToken(msg.sender, uint256(Token.GOLD_COINS), totalPrice);
    }

    function equipGearPiece(Token newGearPiece, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        if (balanceOf(msg.sender, uint256(newGearPiece)) == 0) revert DoNotOwnItem(); 

        IEquipmentVault(equipmentVault).transferToVault(msg.sender, uint256(newGearPiece), 1, "");

        GearInfo storage newGearInfo = gearInfo[newGearPiece]; 
        if (newGearInfo.slot == GearSlot.NULL) revert NotGear(); // Handles all uninitialized gear Tokens.

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

        charStat[_uID][Stat.ATT_POWER] += newGearInfo.attPower;
        charStat[_uID][Stat.ATT_FREQ] += newGearInfo.attFreq;
        charStat[_uID][Stat.ATT_RANGE] += newGearInfo.attRange;
        charStat[_uID][Stat.DODGE_CHANCE] += newGearInfo.dodgeChance; 
        charStat[_uID][Stat.CRIT_CHANCE] += newGearInfo.critChance;
        charStat[_uID][Stat.CRIT_POWER] += newGearInfo.critPower;
        charStat[_uID][Stat.MAGIC_POWER] += newGearInfo.magicPower;
        charStat[_uID][Stat.PROTECTION] += newGearInfo.protection;
        charStat[_uID][Stat.ACCURACY] += newGearInfo.accuracy; 
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

        charStat[_uID][Stat.ATT_POWER] -= requestedGearInfo.attPower;
        charStat[_uID][Stat.ATT_FREQ] -= requestedGearInfo.attFreq;
        charStat[_uID][Stat.ATT_RANGE] -= requestedGearInfo.attRange;
        charStat[_uID][Stat.DODGE_CHANCE] -= requestedGearInfo.dodgeChance; 
        charStat[_uID][Stat.CRIT_CHANCE] -= requestedGearInfo.critChance;
        charStat[_uID][Stat.CRIT_POWER] -= requestedGearInfo.critPower;
        charStat[_uID][Stat.MAGIC_POWER] -= requestedGearInfo.magicPower;
        charStat[_uID][Stat.PROTECTION] -= requestedGearInfo.protection;
        charStat[_uID][Stat.ACCURACY] -= requestedGearInfo.accuracy; 
    }

    function gatherResource(Resource resource, Token tool, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        if (balanceOf(msg.sender, uint256(tool)) == 0) revert DoNotOwnItem();
        
        Location playerLocation = charLocation[_uID];
        if (!areaHasResource[playerLocation][resource]) revert ResourceNotHere();

        ResourceInfo storage _resourceInfo = resourceInfo[resource];
        ToolInfo storage _toolInfo = toolInfo[tool];
        ProficiencyInfo storage charProficiency = charSkill[_uID][_toolInfo.skill];
        if (_toolInfo.skill != Skill.MINING && _toolInfo.skill != Skill.WOODCUTTING && _toolInfo.skill != Skill.FISHING) revert NotTool();
        if (_toolInfo.skill != _resourceInfo.skill) revert WrongToolForTheJob(); 
        if (charProficiency.level < _toolInfo.requiredLevel || charProficiency.level < _resourceInfo.requiredLevel) revert Noob();

        uint16 timeToGather = Calculate.resourceGatheringSpeed(_toolInfo.gatherSpeed, _resourceInfo.gatherSpeed, charProficiency.level);
        charActionFinishedAt[_uID] = uint64(block.timestamp) + timeToGather;

        charProficiency.xp += _resourceInfo.xp;

        // This might be modularized for `craftItem()` too, and maybe for combat level ups.
        if (xpTable[charProficiency.level + 1] <= charProficiency.xp) {
            charProficiency.level++;
            emit SkillLevelUp(_toolInfo.skill, charProficiency.level); 
        }

        _mintToken(msg.sender, uint256(_resourceInfo.material), 1);
    }

    function craftItem(Location craftingArea, Token outputItem, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
		_atLocationCheck(craftingArea, _uID);

		CraftingInfo storage _craftingInfo = craftingInfo[outputItem];
		ProficiencyInfo storage charProficiency = charSkill[_uID][_craftingInfo.skill];

		if (!validCraftingArea[craftingArea][_craftingInfo.skill]) revert WrongCraftingLocation();
		if (_craftingInfo.tokenOne == Token.NOTHING) revert InvalidCraftingOutput(); // Hasn't been initialized as a valid output Token crafting item.
		if (charProficiency.level < _craftingInfo.requiredLevel) revert Noob();
		
		// Burn materials.
		_burnToken(msg.sender, uint256(_craftingInfo.tokenOne), _craftingInfo.amountOne); // tokenOne always exists at this point.
		if (_craftingInfo.tokenTwo != Token.NOTHING) _burnToken(msg.sender, uint256(_craftingInfo.tokenTwo), _craftingInfo.amountTwo);
		if (_craftingInfo.tokenThree != Token.NOTHING) _burnToken(msg.sender, uint256(_craftingInfo.tokenThree), _craftingInfo.amountThree);

		charProficiency.xp += _craftingInfo.xp; // Gain XP 

        // Optional LVL up. This might be modularized for `craftItem()` too, and maybe for combat level ups and teleport level ups.
        if (xpTable[charProficiency.level + 1] <= charProficiency.xp) {
            charProficiency.level++;
            emit SkillLevelUp(_craftingInfo.skill, charProficiency.level);
        }
		
		charActionFinishedAt[_uID] = uint64(block.timestamp) + _craftingInfo.timeToProduce; // Adjust character's action time based on time taken
		_mintToken(msg.sender, uint256(outputItem), _craftingInfo.amountPerOutput); // Mint the finished product to the user.
    }

    function castBuff (BuffSpell buffSpell, bool buffSlotOne, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        
        SpellInfo storage _buffSpellInfo = buffSpellInfo[buffSpell];
        BuffSpellEffects storage _buffSpellEffects = buffSpellEffects[buffSpell];
        ProficiencyInfo storage charProficiency = charAttribute[_uID][Attribute.INTELLIGENCE];
        Token equippedWeapon = charEquipment[_uID][GearSlot.MAIN_HAND];
        
        if (element[equippedWeapon] != _buffSpellInfo.element || element[equippedWeapon] != Element.OMNI) revert InvalidWeaponElementType();
        if (charProficiency.level < _buffSpellInfo.requiredLevel) revert Noob();

        BuffSpellsApplied storage charSpellBuffs = charBuffSpellsApplied[_uID];

        if (buffSlotOne) {
            charSpellBuffs.buffSpellOne = buffSpell;
            charSpellBuffs.buffOneEndsAt = uint64(block.timestamp) + _buffSpellEffects.duration;
        } else {
            charSpellBuffs.buffSpellTwo = buffSpell;
            charSpellBuffs.buffTwoEndsAt = uint64(block.timestamp) + _buffSpellEffects.duration;
        }

        // At any point, if the buff types (stat it increases) in both slots are the same, revert.
        if (buffSpellEffects[charSpellBuffs.buffSpellOne].stat == buffSpellEffects[charSpellBuffs.buffSpellTwo].stat) revert SameBuffType();

        // burn essence crystals according to the exact spell info.
        _burnToken(msg.sender, uint256(Token.ESSENCE_CRYSTAL), _buffSpellInfo.numberOfEssenceCrystals);

        // Give XP and optional level up.
        charProficiency.xp += _buffSpellInfo.xp;

        if (xpTable[charProficiency.level + 1] <= charProficiency.xp) {
            charProficiency.level++;
            emit AttributeLevelUp(Attribute.INTELLIGENCE, charProficiency.level);
        }
    }

    function consumeItem(Token consumable, bool consumableSlotOne, uint256 _uID) external {
		_ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);

		ConsumableInfo storage _consumableInfo = consumableInfo[consumable];
		if (_consumableInfo.statOne == Stat.NONE) revert NotAConsumable(); // By default, all uninitialized tokens have `Stat.CMB_LVL`.

		// Can immediately gain HP if it was HP related. Do not re-add during combat though!
		if (_consumableInfo.statOne == Stat.HP) {
			charStat[_uID][Stat.HP] += _consumableInfo.amountOne;
			if (charStat[_uID][Stat.HP] > charStat[_uID][Stat.MAX_HP]) charStat[_uID][Stat.HP] = charStat[_uID][Stat.MAX_HP];
		}

		ConsumableBuffsApplied storage _charConsumableBuffsApplied = charConsumableBuffsApplied[_uID];

	    if (consumableSlotOne) {
            _charConsumableBuffsApplied.consumableOne = consumable;
            _charConsumableBuffsApplied.consumableOneEndsAt = uint64(block.timestamp) + _consumableInfo.duration;
        } else {
            _charConsumableBuffsApplied.consumableTwo = consumable;
            _charConsumableBuffsApplied.consumableTwoEndsAt = uint64(block.timestamp) + _consumableInfo.duration;
        }
        
		_burnToken(msg.sender, uint256(consumable), 1);
	}

    function sleep(Location inn, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        _atLocationCheck(inn, _uID);
		if (!innLocation[inn]) revert NotAnInn();
        // for combat, check if this buff has expired or not. By default (0), it is expired.
		charInnBuffExpiration[_uID] = uint64(block.timestamp) + ONE_HOUR; 
		_burnToken(msg.sender, uint256(Token.GOLD_COINS), INN_PRICE);
		charStat[_uID][Stat.HP] = charStat[_uID][Stat.MAX_HP]; 
    }




    /*

    function _died(uint256 _uID) internal {
        // In both cases, no XP should be gained of course, since you didn't kill the monster.
        charHardcore[_uID] ? _hardcoreDeath() : _normalDeath();
    }

    function _normalDeath() internal {
        charLocation[_uID] = Location.LUMBRIDGE_TOWN_SQ // respawn in lumby, will still have buffs that's fine.
    }

    function _hardcoreDeath() internal {
        // This means they can never unequip their gear, and their functionality over their character and the gear that was equipped
        // Is forever gone. They still have access to their non-gear items though.
        ownsCharacter[msg.sender][_uID] = false;
        // You could also burn their NFT too, but that is overkill and requies more logic in `_update()` for burning a character.
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

        // Set gear info (type, STR/AGIL/INT, attPower, attSpeed, dodge, critChance, critPower, magicPower, prot, accuracy, attRange, enchantment)
        gearInfo[Token.IRON_SWORD] = GearInfo(GearSlot.MAIN_HAND, false, 1, 0, 0, 10, 500, 0, 100, 1000, 0, 0, 1000, 0, Enchantment.NONE, 0, 0);
        gearInfo[Token.RING_OF_BLOOD] = GearInfo(GearSlot.MAIN_HAND, false, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, Enchantment.NONE, 0, 0);
        gearInfo[Token.IRON_2H_SWORD] = GearInfo(GearSlot.MAIN_HAND, true, 1, 0, 0, 10, 500, 0, 100, 1000, 0, 0, 1000, 0, Enchantment.NONE, 0, 0);

        // set teleport info
        teleportSpellInfo[TeleportSpell.TELEPORT_TO_LUMBRIDGE] = TeleportSpellInfo(Location.LUMBRIDGE_TOWN_SQ, 30, 200, 1);
        teleportSpellInfo[TeleportSpell.TELEPORT_TO_FALADOR] = TeleportSpellInfo(Location.FALADOR_TOWN_SQ, 40, 300, 2);
        teleportSpellInfo[TeleportSpell.TELEPORT_TO_VELRICK] = TeleportSpellInfo(Location.VELRICK_TOWN_SQ, 50, 400, 3);

        // set inn buff values
        innBuffValues[Stat.DODGE_CHANCE] = 200;
        innBuffValues[Stat.CRIT_CHANCE] = 100;
        innBuffValues[Stat.CRIT_POWER] = 1000;
        innBuffValues[Stat.ACCURACY] = 200;

        // Set staff and wand spell types.
        element[Token.AIR_STAFF] = Element.AIR;
        element[Token.WATER_STAFF] = Element.WATER;
        element[Token.EARTH_STAFF] = Element.EARTH;
        element[Token.FIRE_STAFF] = Element.FIRE;
        element[Token.OMNI_STAFF] = Element.AIR;
        element[Token.AIR_WAND] = Element.AIR;

        // Set buff spell info. (spell type, req lvl, xp, num crystals).
        buffSpellInfo[BuffSpell.STONE_SKIN] = SpellInfo(Element.EARTH, 25, 500, 3);
        buffSpellInfo[BuffSpell.IRON_SKIN] = SpellInfo(Element.EARTH, 35, 800, 5);
        buffSpellInfo[BuffSpell.SHADOW_SKIN] = SpellInfo(Element.WATER, 50, 1400, 8);
        buffSpellInfo[BuffSpell.ANCIENT_RAGE] = SpellInfo(Element.FIRE, 60, 3000, 20);
        buffSpellInfo[BuffSpell.KEEN_EYE] = SpellInfo(Element.AIR, 10, 200, 2);
        buffSpellInfo[BuffSpell.IMBUED_SOUL] = SpellInfo(Element.WATER, 1, 100, 1);

        // set buff spell effects. (Stat, duration, amount (static), percentage (dynamic)).
        buffSpellEffects[BuffSpell.STONE_SKIN] = BuffSpellEffects(Stat.PROTECTION, 1800, 50, 0);
        buffSpellEffects[BuffSpell.IRON_SKIN] = BuffSpellEffects(Stat.PROTECTION, 1800, 150, 0);
        buffSpellEffects[BuffSpell.SHADOW_SKIN] = BuffSpellEffects(Stat.DODGE_CHANCE, 900, 500, 0); // 5%
        buffSpellEffects[BuffSpell.ANCIENT_RAGE] = BuffSpellEffects(Stat.ATT_POWER, 600, 0, 2000); // 20%
        buffSpellEffects[BuffSpell.KEEN_EYE] = BuffSpellEffects(Stat.ACCURACY, 1800, 500, 0); // 5%
        buffSpellEffects[BuffSpell.IMBUED_SOUL] = BuffSpellEffects(Stat.MAGIC_POWER, 3600, 0, 1000); // 10%

        // set item consumable effects. (stat1, stat2, amnt1, pct1, amnt2, pct2, duration)
        consumableInfo[Token.HEALTH_POTION] = ConsumableInfo(Stat.HP, Stat.NONE, 50, 0, 0, 0, 0);
        consumableInfo[Token.STRENGTH_POTION] = ConsumableInfo(Stat.ATT_POWER, Stat.NONE, 0, 1000, 0, 0, 900);
        consumableInfo[Token.PROTECTION_POTION] = ConsumableInfo(Stat.PROTECTION, Stat.NONE, 20, 0, 0, 0, 900);
        consumableInfo[Token.SALMON] = ConsumableInfo(Stat.PROTECTION, Stat.DODGE_CHANCE, 20, 0, 200, 0, 600);

        // set combat spell info. (spell type, req lvl, xp, num crystals).
        combatSpellInfo[CombatSpell.AIR_BLAST] = SpellInfo(Element.AIR, 1, 200, 1);
        combatSpellInfo[CombatSpell.WATER_BLAST] = SpellInfo(Element.WATER, 5, 400, 1);
        combatSpellInfo[CombatSpell.EARTH_BLAST] = SpellInfo(Element.EARTH, 10, 800, 1);
        combatSpellInfo[CombatSpell.FIRE_BLAST] = SpellInfo(Element.FIRE, 15, 1200, 1);
        combatSpellInfo[CombatSpell.OMNI_BLAST] = SpellInfo(Element.OMNI, 25, 3000, 3);

        // set combat spell effects (attFreq, magicPower, accuracy)
        combatSpellEffects[CombatSpell.AIR_BLAST] = CombatSpellEffects(0, 20, 0);
        combatSpellEffects[CombatSpell.WATER_BLAST] = CombatSpellEffects(0, 50, 0);
        combatSpellEffects[CombatSpell.EARTH_BLAST] = CombatSpellEffects(0, 90, 0);
        combatSpellEffects[CombatSpell.FIRE_BLAST] = CombatSpellEffects(0, 160, 0);
        combatSpellEffects[CombatSpell.OMNI_BLAST] = CombatSpellEffects(0, 250, 0);

        // Set crafting info for items.. (skill, reqLvl, xp, timeToProduce, amountPerOutput, token1, token2, token3, amnt1, amnt2, amnt3)
        craftingInfo[Token.RING_OF_BLOOD] = CraftingInfo(Skill.BLACKSMITHING, 10, 500, 30, 1, Token.GOLD_COINS, Token.IRON_INGOT, Token.NOTHING, 42, 2, 0);
        craftingInfo[Token.IRON_INGOT] = CraftingInfo(Skill.BLACKSMITHING, 20, 100, 30, 1, Token.IRON_ORE, Token.NOTHING, Token.NOTHING, 2, 0, 0);

        // Set valid crafting locations.
        validCraftingArea[Location.L_INN][Skill.COOKING] = true;
        validCraftingArea[Location.L_BLACKSMITH][Skill.BLACKSMITHING] = true;
        validCraftingArea[Location.L_RANGE_SHOP][Skill.LEATHERWORKING] = true;
        validCraftingArea[Location.L_RANGE_SHOP][Skill.WOODWORKING] = true;
        validCraftingArea[Location.L_MAGE_SHOP][Skill.ALCHEMY] = true;
        validCraftingArea[Location.L_MAGE_SHOP][Skill.ENCHANTING] = true;
        validCraftingArea[Location.L_MAGE_SHOP][Skill.CLOTHWORKING] = true;

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