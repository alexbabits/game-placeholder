// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155URIStorage} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IEquipmentVault} from "./IEquipmentVault.sol";
import {Calculate} from "./Calculate.sol";
import {StructEnumEventError} from "./StructEnumEventError.sol";

import {VRFCoordinatorV2Interface} from "@chainlink/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/src/v0.8/vrf/VRFConsumerBaseV2.sol";

// Contains all the logic for the game.
contract Game is ERC1155, ERC1155URIStorage, Ownable, StructEnumEventError, VRFConsumerBaseV2 {

    VRFCoordinatorV2Interface coordinator; // VRF interface
    bytes32 private keyHash; // VRF gas lane option
    uint64 private subscriptionId; // VRF subscription ID
    uint32 private callbackGasLimit; // VRF gas limit for `fulfillRandomWords()` callback execution.
    uint16 private requestConfirmations; // VRF number of block confirmations to prevent re-orgs.

    uint256 private uID; // Global unique character mint counter
    uint64 private characterSalePrice;
    uint64 private combatPrice;
    uint64 immutable MAX_CHARACTER_PRICE = 5e18;
    uint64 immutable MAX_COMBAT_PRICE = 1e18;
    uint8 immutable INN_PRICE = 30;
    uint16 immutable INN_BUFF_DURATION = 3600;

    address private funding;
    address private equipmentVault;
    
    int16 immutable PCT_25 = 2500;
    int16 immutable PCT_50 = 5000;
    int16 immutable PCT_100 = 10000;
    
    mapping(uint8 => uint32) private xpTable; // Level --> total XP required for that level  

    mapping(Location => Coordinates) private coordinates; // Location --> (X,Y) coordinates
    mapping(Location => bool) private shopLocation; // Location --> Store exists here?
    mapping(Location => bool) private innLocation; // Location --> Inn exists here?
    mapping(Location => mapping(Resource => bool)) private areaHasResource; // Does the area have this resource?
    mapping(Location => mapping(Enemy => bool)) private areaHasEnemy; // Does the area have this enemy?
    mapping(Location => mapping(Token => bool)) private shopSellsItem; // Does the shop sell this item?
    mapping(Location => mapping(Skill => bool)) private validCraftingArea; // Does this area allow this skill to be done?

    mapping(Token => PriceInfo) private itemPrice; // Item --> Buy and sell price in gold coins.
    mapping(Token => GearInfo) private gearInfo; // Item --> Gear Info (for equipment)
    mapping(Token => ConsumableInfo) private consumableInfo; // item --> consumable info
    mapping(Token => ToolInfo) private toolInfo; // Item --> Tool Info (for skilling tools)
    mapping(Token => CraftingInfo) private craftingInfo; // Item --> Crafting Info (for crafting any output product)
    mapping(Token => Element) private element; // (Staff/Wand) --> element type.
    mapping(Resource => ResourceInfo) private resourceInfo; // Resource --> Resource Info
    
    mapping(Stat => int16) private innBuffValue; // buff values for sleeping at an inn.
    mapping(BuffSpell => BuffSpellInfo) private buffSpellInfo; // Spell buff -> it's info
    mapping(CombatSpell => CombatSpellInfo) private combatSpellInfo; // combat spell -> it's info
    mapping(TeleportSpell => TeleportSpellInfo) private teleportSpellInfo; // tele spell -> it's info
    mapping(WeaponType => mapping(CombatStyle => XPSplit)) private xpSplit; // weapon type --> combat style chosen --> xp split given
    mapping(CombatStyle => CombatStyleBuff) private combatStyleBuff; // style --> it's buff info
    mapping(Element => mapping(Element => WeakStrong)) private weakStrong; // Element <--> Element --> weakness and strength table
    mapping(Enemy => EnemyStats) private enemyStats; // enemy --> its stats
	mapping(Enemy => EnemyDrops) private enemyDrops; // enemy --> its drops

    mapping(address => mapping(uint256 => bool)) private ownsCharacter; // Does this address own this character (uID)?

    mapping(uint256 => Token) private charToken; // Token of this character (ALICE or BOB).
    mapping(uint256 => bool) private charHardcore; // is this a hardcore character? (per-character basis)
    mapping(uint256 => Location) private charLocation; // current location of this character.
    mapping(uint256 => mapping(Skill => ProficiencyInfo)) private charSkill; // char --> skill --> proficiency info
    mapping(uint256 => mapping(Attribute => ProficiencyInfo)) private charAttribute; // char --> attr --> proficiency info
    mapping(uint256 => mapping(Stat => int16)) private charStat; // char --> specific stat --> value
    mapping(uint256 => mapping(Stat => int16)) private charBattleStat; // Char --> Stat --> value
    mapping(uint256 => mapping(GearSlot => Token)) private charEquipment; // char --> specific gear slot --> what they have equipped there
    mapping(uint256 => CharSpellBuffs) private charSpellBuffs; // char --> magic buffs currently applied
    mapping(uint256 => CharConsumableBuffs) private charConsumableBuffs; // char --> consumable buffs
    mapping(uint256 => uint64) private charInnBuffExpiration; // char --> inn buff expiration time.
    mapping(uint256 => uint64) private charActionFinishedAt; // char --> time when an action is finished.
    mapping(uint256 => CombatStyle) private charCombatStyle; // char --> combat style
    mapping(uint256 => CombatSpell) private charCombatSpell; // char --> combat spell.
    mapping(uint256 => CharBattleInfo) private charBattleInfo; // maps all their snapshotted battle info after initiating combat.
    mapping(uint256 => uint256) private requestIdToChar; // req ID --> char
    mapping(uint256 => uint64) private charRequestTime; // char --> req time for initiate combat.
	mapping(uint256 => uint16[]) private charRandomWords; // char --> their random words for combat


    constructor(
        address initialOwner, 
        address _funding, 
        address _equipmentVault,
        uint64 _subscriptionId,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        address _vrfCoordinator
    ) 
        ERC1155("") Ownable(initialOwner) 
        VRFConsumerBaseV2(_vrfCoordinator)
    {
        funding = _funding;
        equipmentVault = _equipmentVault;
        _setGameData(); 
        setVRFData(_subscriptionId, _keyHash, _callbackGasLimit, _requestConfirmations);   
        coordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
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
        charStat[_uID][Stat.DODGE_CHANCE] = 200;
        charStat[_uID][Stat.CRIT_CHANCE] = 200;
        charStat[_uID][Stat.CRIT_POWER] = 15000;
        charStat[_uID][Stat.MAGIC_POWER] = 0;
        charStat[_uID][Stat.PROTECTION] = 0;
        charStat[_uID][Stat.ACCURACY] = 8000;

        /**
         * To keep contract size low, the default initialization values for some  
         * character specific mappings are sufficient and do not need to be explicitly set:

         * `charEquipment[_uID][GearSlot.EACH_SLOT] = Token.NOTHING;`
         * `charActionFinishedAt[_uID] = 0;` // 0 = Free to do anything upon character creation
         * `charInnBuffExpiration[_uID] = 0;` // 0 = expiration in the past, no buff granted.
         * `charSpellBuffs[_uID] = CharSpellBuffs(BuffSpell.NONE, BuffSpell.NONE, 0, 0);` 
         * `charConsumableBuffs[_uID] = CharConsumableBuffs(Token.NOTHING, Token.NOTHING, 0, 0);`
         * `charCombatStyle[_uID] = CombatStyle.NONE;`
         * `charCombatSpell[_uID] = CombatSpell.NONE;`
         * `charBattleInfo[_uID] = CharBattleInfo(Enemy.NONE, CombatStyle.NONE, CombatSpell.NONE);`
         * `requestIdToChar[reqId] = 0`
         * `charRequestTime[_uID] = 0`
         * `charRandomWords[] = 0`

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
        
		TeleportSpellInfo storage _teleportSpellInfo = teleportSpellInfo[teleportSpell]; 
		if (charLocation[_uID] == _teleportSpellInfo.destination) revert AlreadyThere();
		_burnToken(msg.sender, uint256(Token.ESSENCE_CRYSTAL), _teleportSpellInfo.spellInfo.numCrystals); 

		// If player does not have the right kind of staff or wand equipped, cannot teleport.
		Token equippedWeapon = charEquipment[_uID][GearSlot.MAIN_HAND];
		if(element[equippedWeapon] != Element.AIR && element[equippedWeapon] != Element.OMNI) revert WrongElement();

		// Must have required level. Gain XP, level up INT if gained enough XP. Lastly, update character's location to tele destination.
		ProficiencyInfo storage charProficiency = charAttribute[_uID][Attribute.INTELLIGENCE];
		if (charProficiency.level < _teleportSpellInfo.spellInfo.requiredLevel) revert Noob(); 

		charProficiency.xp += _teleportSpellInfo.spellInfo.xp; 

		if (xpTable[charProficiency.level + 1] <= charProficiency.xp) {
			charProficiency.level++;
            charStat[_uID][Stat.MAGIC_POWER] += 5;
            charStat[_uID][Stat.ACCURACY] += 10;
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

    function equipGearPiece(Token newGearPiece, bool ringSlotOne, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        if (balanceOf(msg.sender, uint256(newGearPiece)) == 0) revert DoNotOwnItem(newGearPiece); 
        // If player equips an identical gear piece, they still unequip the old one and equip the new one.
        GearInfo storage newGearInfo = gearInfo[newGearPiece]; 
        if (newGearInfo.slotOne == GearSlot.NONE) revert NotGear();
        if (
            charAttribute[_uID][Attribute.STRENGTH].level < newGearInfo.requiredStrengthLevel || 
            charAttribute[_uID][Attribute.AGILITY].level < newGearInfo.requiredAgilityLevel ||
            charAttribute[_uID][Attribute.INTELLIGENCE].level < newGearInfo.requiredIntelligenceLevel
        ) revert Noob(); 

        IEquipmentVault(equipmentVault).transferToVault(msg.sender, uint256(newGearPiece), 1, "");

        Token oldMainHand = charEquipment[_uID][GearSlot.MAIN_HAND];
	    Token oldOffHand = charEquipment[_uID][GearSlot.OFF_HAND];
	    
        // Player wants to equip a 2H weapon. Unequip mainHand and/or offHand, then equip 2H weapon.
        // 2H weapon: slotOne = GearSlot.MAIN_HAND. slotTwo = GearSlot.OFF_HAND
        if (newGearInfo.slotTwo == GearSlot.OFF_HAND) {
            if (oldMainHand != Token.NOTHING) unequipGearPiece(oldMainHand, GearSlot.MAIN_HAND, _uID);
            if (oldOffHand != Token.NOTHING) unequipGearPiece(oldOffHand, GearSlot.OFF_HAND, _uID);
            charEquipment[_uID][GearSlot.MAIN_HAND] = newGearPiece;

		// Player wants to equip an offHand and currently has a 2H equipped. Unequip the 2H and equip the offHand.
        } else if (newGearInfo.slotOne == GearSlot.OFF_HAND && gearInfo[oldMainHand].slotTwo == GearSlot.OFF_HAND){
       	    unequipGearPiece(oldMainHand, GearSlot.MAIN_HAND, _uID);
	        charEquipment[_uID][GearSlot.OFF_HAND] = newGearPiece; 

		// Player wants to equip a ring. Find the desired slot, unequip oldRing if needed, and equip the new ring.
        // Ring: slotOne = GearSlot.RING_ONE. slotTwo = GearSlot.RING_TWO
        } else if (newGearInfo.slotOne == GearSlot.RING_ONE) {
			GearSlot desiredSlot = ringSlotOne ? GearSlot.RING_ONE : GearSlot.RING_TWO;
			Token oldRing = charEquipment[_uID][desiredSlot];
			if (oldRing != Token.NOTHING) unequipGearPiece(oldRing, desiredSlot, _uID);
			charEquipment[_uID][desiredSlot] = newGearPiece;

		// In all other cases we match the gear slot, unequip the gear if needed, and equip the new gear piece.
        // Everything else: slotOne = GearSlot.(MAIN_HAND, OFF_HAND, AMULET, HELMET, ...). slotTwo = GearSlot.NONE
		} else {
			Token oldSlotMatch = charEquipment[_uID][newGearInfo.slotOne];
			if (oldSlotMatch != Token.NOTHING) unequipGearPiece(oldSlotMatch, newGearInfo.slotOne, _uID);
			charEquipment[_uID][newGearInfo.slotOne] = newGearPiece; 
		}

        charStat[_uID][Stat.ATT_POWER] += newGearInfo.attPower;
        charStat[_uID][Stat.ATT_FREQ] += newGearInfo.attFreq;
        charStat[_uID][Stat.DODGE_CHANCE] += newGearInfo.dodgeChance; 
        charStat[_uID][Stat.CRIT_CHANCE] += newGearInfo.critChance;
        charStat[_uID][Stat.CRIT_POWER] += newGearInfo.critPower;
        charStat[_uID][Stat.MAGIC_POWER] += newGearInfo.magicPower;
        charStat[_uID][Stat.PROTECTION] += newGearInfo.protection;
        charStat[_uID][Stat.ACCURACY] += newGearInfo.accuracy; 
    }

    // A specific `slot` param was needed for the rings edgecases, and maybe for 2H's?
    function unequipGearPiece(Token requestedGearPiece, GearSlot slot, uint256 _uID) public {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        if (requestedGearPiece == Token.NOTHING) revert CannotUnequipNothing();
        if (charEquipment[_uID][slot] != requestedGearPiece) revert ItemNotEquipped(); // This handles all the edge cases (MUST BE EXACT MATCH!)
        charEquipment[_uID][slot] = Token.NOTHING;
        
        GearInfo storage requestedGearInfo = gearInfo[requestedGearPiece];
        charStat[_uID][Stat.ATT_POWER] -= requestedGearInfo.attPower;
        charStat[_uID][Stat.ATT_FREQ] -= requestedGearInfo.attFreq;
        charStat[_uID][Stat.DODGE_CHANCE] -= requestedGearInfo.dodgeChance; 
        charStat[_uID][Stat.CRIT_CHANCE] -= requestedGearInfo.critChance;
        charStat[_uID][Stat.CRIT_POWER] -= requestedGearInfo.critPower;
        charStat[_uID][Stat.MAGIC_POWER] -= requestedGearInfo.magicPower;
        charStat[_uID][Stat.PROTECTION] -= requestedGearInfo.protection;
        charStat[_uID][Stat.ACCURACY] -= requestedGearInfo.accuracy; 

        IEquipmentVault(equipmentVault).transferFromVault(msg.sender, uint256(requestedGearPiece), 1, "");
    }

    function gatherResource(Resource resource, Token tool, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        if (balanceOf(msg.sender, uint256(tool)) == 0) revert DoNotOwnItem(tool);
        if (!areaHasResource[charLocation[_uID]][resource]) revert ResourceNotHere();

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
        
        BuffSpellInfo storage _buffSpellInfo = buffSpellInfo[buffSpell];
        ProficiencyInfo storage charProficiency = charAttribute[_uID][Attribute.INTELLIGENCE];
        Token equippedWeapon = charEquipment[_uID][GearSlot.MAIN_HAND];
        
        if (element[equippedWeapon] != _buffSpellInfo.spellInfo.elementType && element[equippedWeapon] != Element.OMNI) revert WrongElement();
        if (charProficiency.level < _buffSpellInfo.spellInfo.requiredLevel) revert Noob();

        CharSpellBuffs storage _charSpellBuffs = charSpellBuffs[_uID];

        if (buffSlotOne) {
            _charSpellBuffs.buffSpellOne = buffSpell;
            _charSpellBuffs.oneEndsAt = uint64(block.timestamp) + _buffSpellInfo.duration;
        } else {
            _charSpellBuffs.buffSpellTwo = buffSpell;
            _charSpellBuffs.twoEndsAt = uint64(block.timestamp) + _buffSpellInfo.duration;
        }

        // If the buff types (stat that the buff increases) in both slots are the same, revert.
        if (buffSpellInfo[_charSpellBuffs.buffSpellOne].stat == buffSpellInfo[_charSpellBuffs.buffSpellTwo].stat) revert SameBuffType();

        _burnToken(msg.sender, uint256(Token.ESSENCE_CRYSTAL), _buffSpellInfo.spellInfo.numCrystals); // burn crystals for spell

        // Give XP and optional level up.
        charProficiency.xp += _buffSpellInfo.spellInfo.xp;

        if (xpTable[charProficiency.level + 1] <= charProficiency.xp) {
            charProficiency.level++;
            charStat[_uID][Stat.MAGIC_POWER] += 5;
            charStat[_uID][Stat.ACCURACY] += 10;
            emit AttributeLevelUp(Attribute.INTELLIGENCE, charProficiency.level);
        }
    }

    function consumeItem(Token consumable, bool consumableSlotOne, uint256 _uID) external {
		_ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);

		ConsumableInfo storage _consumableInfo = consumableInfo[consumable];
		if (_consumableInfo.statOne == Stat.NONE) revert NotAConsumable();
        _burnToken(msg.sender, uint256(consumable), 1);

		// Immediately gain HP if it was HP related, and don't add it as a consumable if it was just HP.
		if (_consumableInfo.statOne == Stat.HP && _consumableInfo.duration == 0) {
			charStat[_uID][Stat.HP] += _consumableInfo.amountOne;
			if (charStat[_uID][Stat.HP] > charStat[_uID][Stat.MAX_HP]) charStat[_uID][Stat.HP] = charStat[_uID][Stat.MAX_HP];
            return;
        }

		CharConsumableBuffs storage _charConsumableBuffs = charConsumableBuffs[_uID];

	    if (consumableSlotOne) {
            _charConsumableBuffs.consumableOne = consumable;
            _charConsumableBuffs.oneEndsAt = uint64(block.timestamp) + _consumableInfo.duration;
        } else {
            _charConsumableBuffs.consumableTwo = consumable;
            _charConsumableBuffs.twoEndsAt = uint64(block.timestamp) + _consumableInfo.duration;
        }
	}

    function sleep(Location inn, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        _atLocationCheck(inn, _uID);
		if (!innLocation[inn]) revert NotAnInn();
        // for combat, check if this buff has expired or not. By default (0), it is expired.
		charInnBuffExpiration[_uID] = uint64(block.timestamp) + INN_BUFF_DURATION; 
		_burnToken(msg.sender, uint256(Token.GOLD_COINS), INN_PRICE);
		charStat[_uID][Stat.HP] = charStat[_uID][Stat.MAX_HP]; 
    }

    function chooseCombatStyle(CombatStyle _combatStyle, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID);
        charCombatStyle[_uID] = _combatStyle;
    }

    // We only check INT proficiency here. Weapon type match, element type match, & crystal check is during `initiateCombat()`.
    // This means as long as we have the INT level, we can select the spell beforehand, even if not geared properly yet.
    function chooseCombatSpell(CombatSpell _combatSpell, uint256 _uID) external {
        _ownsCharacterCheck(msg.sender, _uID);
        _doingSomethingCheck(_uID); 
        ProficiencyInfo storage charProficiency = charAttribute[_uID][Attribute.INTELLIGENCE];
        CombatSpellInfo storage _combatSpellInfo = combatSpellInfo[_combatSpell];
        if (charProficiency.level < _combatSpellInfo.spellInfo.requiredLevel) revert Noob();
        charCombatSpell[_uID] = _combatSpell;
    }

	// Calculates the finalized snapshot of the character stats that will be used with the random words.
	function initiateCombat(Enemy _enemy, uint256 _uID) external payable {
		_ownsCharacterCheck(msg.sender, _uID);
		_doingSomethingCheck(_uID);
		if (!areaHasEnemy[charLocation[_uID]][_enemy]) revert EnemyNotHere();
		(bool success, ) = funding.call{value: combatPrice}(""); // 0.05 MATIC
		if(!success) revert FailedCall();

		CharBattleInfo storage _charBattleInfo = charBattleInfo[_uID];
        CombatStyle _charCombatStyle = charCombatStyle[_uID];

		_charBattleInfo.enemy = _enemy;
		_charBattleInfo.combatStyle = _charCombatStyle;
		_charBattleInfo.combatSpell = CombatSpell.NONE; // If using magic, we set during magic checks later. 
		
		// First start from a clean slate by setting/resetting battle stats to their current unbuffed stats.
		// This acts as a snapshot of their current gear w/o buffs/enchants. They cannot unequip gear once combat initiated.
		charBattleStat[_uID][Stat.HP] =  charStat[_uID][Stat.HP]; 
		charBattleStat[_uID][Stat.ATT_POWER] = charStat[_uID][Stat.ATT_POWER]; 
		charBattleStat[_uID][Stat.ATT_FREQ] = charStat[_uID][Stat.ATT_FREQ];
		charBattleStat[_uID][Stat.DODGE_CHANCE] = charStat[_uID][Stat.DODGE_CHANCE];
		charBattleStat[_uID][Stat.CRIT_CHANCE] = charStat[_uID][Stat.CRIT_CHANCE]; 
		charBattleStat[_uID][Stat.CRIT_POWER] = charStat[_uID][Stat.CRIT_POWER]; 
		charBattleStat[_uID][Stat.MAGIC_POWER] = charStat[_uID][Stat.MAGIC_POWER]; 
		charBattleStat[_uID][Stat.PROTECTION] = charStat[_uID][Stat.PROTECTION]; 
		charBattleStat[_uID][Stat.ACCURACY] = charStat[_uID][Stat.ACCURACY]; 

        _applyInnBuffs(_uID);
        _applyConsumableBuffs(_uID);
        _applySpellBuffs(_uID);
        _applyCombatStyleBuffs(_uID);
        _applyEnchantmentBuffs(_enemy, _uID);

        GearInfo storage mainHand = gearInfo[charEquipment[_uID][GearSlot.MAIN_HAND]];
        
		// If the player is using magic, save the spell they are using.
		if (mainHand.weaponType == WeaponType.STAFF || mainHand.weaponType == WeaponType.WAND) {
			CombatSpell _combatSpell = charCombatSpell[_uID];
			CombatSpellInfo storage _combatSpellInfo = combatSpellInfo[_combatSpell];
			Element combatSpellElement = _combatSpellInfo.spellInfo.elementType;
			Element weaponElement = element[charEquipment[_uID][GearSlot.MAIN_HAND]];

			if (_combatSpell == CombatSpell.NONE) revert NoSpellSelected();
			if (weaponElement != combatSpellElement && weaponElement != Element.OMNI) revert WrongElement();
			if (_charCombatStyle == CombatStyle.BARBARIC || _charCombatStyle == CombatStyle.DEXTEROUS) revert InvalidStyle();

			_burnToken(msg.sender, uint256(Token.ESSENCE_CRYSTAL), _combatSpellInfo.spellInfo.numCrystals);
			
            charBattleStat[_uID][Stat.ATT_FREQ] += _combatSpellInfo.attFreq;
            charBattleStat[_uID][Stat.MAGIC_POWER] += _combatSpellInfo.magicPower; // Always static increment from the spell itself.
            charBattleStat[_uID][Stat.ACCURACY] += _combatSpellInfo.accuracy;

            EnemyStats storage _enemyStats = enemyStats[_enemy];
           	if (weakStrong[_enemyStats.elementType][combatSpellElement].isWeak) {
			    charBattleStat[_uID][Stat.MAGIC_POWER] += ((charBattleStat[_uID][Stat.MAGIC_POWER] * PCT_25) / PCT_100);
		    } else if (weakStrong[_enemyStats.elementType][combatSpellElement].isStrong) {
			    charBattleStat[_uID][Stat.MAGIC_POWER] -= ((charBattleStat[_uID][Stat.MAGIC_POWER] * PCT_25) / PCT_100);
		    } 
            _charBattleInfo.combatSpell = _combatSpell;
		}

		// Request the randomness needed for combat and loot. 
		uint256 _requestId = coordinator.requestRandomWords(
			keyHash,
			subscriptionId,
			requestConfirmations,
			callbackGasLimit,
			9 // numWords. (4 for dodge & crit chance for player and enemy, 5 for loot slots).
			//`extraArgs` needed for v2.5. (`bytes calldata extraArgs` param)
		);

		requestIdToChar[_requestId] = _uID; // needed during fulfillment to match reqID to a character
        charRequestTime[_uID] = uint64(block.timestamp);
		charActionFinishedAt[_uID] = type(uint64).max; // freeze character indefinitely until they finalize combat.
	}

    function _applyInnBuffs(uint256 _uID) internal {
		if (block.timestamp < charInnBuffExpiration[_uID]) {
			charBattleStat[_uID][Stat.DODGE_CHANCE] += innBuffValue[Stat.DODGE_CHANCE];
			charBattleStat[_uID][Stat.CRIT_CHANCE] += innBuffValue[Stat.CRIT_CHANCE];
	        charBattleStat[_uID][Stat.CRIT_POWER] += innBuffValue[Stat.CRIT_POWER];
	        charBattleStat[_uID][Stat.ACCURACY] += innBuffValue[Stat.ACCURACY];
		}
    }

    function _applyConsumableBuffs(uint256 _uID) internal {
        CharConsumableBuffs storage _charConsumableBuffs = charConsumableBuffs[_uID];
        if (_charConsumableBuffs.oneEndsAt > block.timestamp) {
            ConsumableInfo storage _consumableInfo = consumableInfo[_charConsumableBuffs.consumableOne];
            charBattleStat[_uID][_consumableInfo.statOne] += _consumableInfo.amountOne;
            if (_consumableInfo.statTwo != Stat.NONE) charBattleStat[_uID][_consumableInfo.statTwo] += _consumableInfo.amountTwo;
        }
        if (_charConsumableBuffs.twoEndsAt > block.timestamp) {
            ConsumableInfo storage _consumableInfo = consumableInfo[_charConsumableBuffs.consumableTwo];
            charBattleStat[_uID][_consumableInfo.statOne] += _consumableInfo.amountOne;
            if (_consumableInfo.statTwo != Stat.NONE) charBattleStat[_uID][_consumableInfo.statTwo] += _consumableInfo.amountTwo;
        }
    }

    function _applySpellBuffs(uint256 _uID) internal {
        // Non-zero buff amount means it's static amount based, else the buff is percentage based.
		CharSpellBuffs storage _charSpellBuffs = charSpellBuffs[_uID];

		if (_charSpellBuffs.oneEndsAt > block.timestamp) {
			BuffSpellInfo storage _buffSpellOne = buffSpellInfo[_charSpellBuffs.buffSpellOne];
			if (_buffSpellOne.amount != 0) {
				charBattleStat[_uID][_buffSpellOne.stat] += _buffSpellOne.amount;
			} else if (_buffSpellOne.percentage != 0) {
				int16 current = charBattleStat[_uID][_buffSpellOne.stat];
				charBattleStat[_uID][_buffSpellOne.stat] = current + ((current * _buffSpellOne.percentage) / PCT_100);
			}	
		}

		if (_charSpellBuffs.twoEndsAt > block.timestamp) {
			BuffSpellInfo storage _buffSpellTwo = buffSpellInfo[_charSpellBuffs.buffSpellTwo];
			if (_buffSpellTwo.amount != 0) {
				charBattleStat[_uID][_buffSpellTwo.stat] += _buffSpellTwo.amount;
			} else if (_buffSpellTwo.percentage != 0) {
				int16 current = charBattleStat[_uID][_buffSpellTwo.stat];
				charBattleStat[_uID][_buffSpellTwo.stat] = current + ((current * _buffSpellTwo.percentage) / PCT_100);
			}	
		}
    }

    function _applyCombatStyleBuffs(uint256 _uID) internal {
		CombatStyleBuff storage _combatStyleBuff = combatStyleBuff[charCombatStyle[_uID]]; // not time sensitive

		if (charCombatStyle[_uID] != CombatStyle.NONE) {
			int16 currentAttPower = charBattleStat[_uID][Stat.ATT_POWER]; // always percentage based
			int16 currentMagPower = charBattleStat[_uID][Stat.MAGIC_POWER]; // always percentage based
			charBattleStat[_uID][Stat.ATT_POWER] = currentAttPower + ((currentAttPower * _combatStyleBuff.attPower) / PCT_100);
			charBattleStat[_uID][Stat.ATT_FREQ] += _combatStyleBuff.attFreq;
			charBattleStat[_uID][Stat.DODGE_CHANCE] += _combatStyleBuff.dodgeChance;
			charBattleStat[_uID][Stat.CRIT_CHANCE] += _combatStyleBuff.critChance;
			charBattleStat[_uID][Stat.CRIT_POWER] += _combatStyleBuff.critPower;
			charBattleStat[_uID][Stat.MAGIC_POWER] = currentMagPower + ((currentMagPower * _combatStyleBuff.magicPower) / PCT_100);
			charBattleStat[_uID][Stat.ACCURACY] += _combatStyleBuff.accuracy;
		}
    }

    function _applyEnchantmentBuffs(Enemy _enemy, uint256 _uID) internal {
        GearInfo storage mainHand = gearInfo[charEquipment[_uID][GearSlot.MAIN_HAND]];
        GearInfo storage amulet = gearInfo[charEquipment[_uID][GearSlot.AMULET]];
		GearInfo storage ringOne = gearInfo[charEquipment[_uID][GearSlot.RING_ONE]];
		GearInfo storage ringTwo = gearInfo[charEquipment[_uID][GearSlot.RING_TWO]];
        EnemyStats storage _enemyStats = enemyStats[_enemy];

        if (weakStrong[_enemyStats.elementType][mainHand.enchantElement].isWeak) {
			charBattleStat[_uID][Stat.ATT_POWER] += ((charBattleStat[_uID][Stat.ATT_POWER] * PCT_25) / PCT_100);
		} else if (weakStrong[_enemyStats.elementType][mainHand.enchantElement].isStrong) {
			charBattleStat[_uID][Stat.ATT_POWER] -= ((charBattleStat[_uID][Stat.ATT_POWER] * PCT_25) / PCT_100);
		}   

        if (mainHand.enchantAmount != 0) {
			charBattleStat[_uID][mainHand.enchantStat] += mainHand.enchantAmount;
		} else if (mainHand.enchantPercent != 0) {
			int16 current = charBattleStat[_uID][mainHand.enchantStat];
			charBattleStat[_uID][mainHand.enchantStat] += current + ((current * ringTwo.enchantPercent) / PCT_100);
		}

		if (amulet.enchantAmount != 0) {
			charBattleStat[_uID][amulet.enchantStat] += amulet.enchantAmount;
		} else if (amulet.enchantPercent != 0) {
			int16 current = charBattleStat[_uID][amulet.enchantStat];
			charBattleStat[_uID][amulet.enchantStat] = current + ((current * amulet.enchantPercent) / PCT_100);
		}

		if (ringOne.enchantAmount != 0) {
			charBattleStat[_uID][ringOne.enchantStat] += ringOne.enchantAmount;
		} else if (ringOne.enchantPercent != 0) {
			int16 current = charBattleStat[_uID][ringOne.enchantStat];
			charBattleStat[_uID][ringOne.enchantStat] = current + ((current * ringOne.enchantPercent) / PCT_100);
		}

		if (ringTwo.enchantAmount != 0) {
			charBattleStat[_uID][ringTwo.enchantStat] += ringTwo.enchantAmount;
		} else if (ringTwo.enchantPercent != 0) {
			int16 current = charBattleStat[_uID][ringOne.enchantStat];
			charBattleStat[_uID][ringTwo.enchantStat] = current + ((current * ringTwo.enchantPercent) / PCT_100);
		}
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 char = requestIdToChar[requestId];
        uint16[] memory digestedRandomWords = new uint16[](randomWords.length);
        for (uint256 i = 0; i < randomWords.length; ++i) {
            digestedRandomWords[i] = uint16((randomWords[i] % 10000) + 1);  // [1, 10000] inclusive
		}
        charRandomWords[char] = digestedRandomWords;
	}

	// Calculates the aftermath of the battle with the randomness. 
	function finalizeCombat(uint256 _uID) external {
		_ownsCharacterCheck(msg.sender, _uID);
        (uint256 charDamage, uint256 enemyDamage) = _calculateDamage(_uID);
        int256 tickDifference = _calculateTicks(_uID, charDamage, enemyDamage);

        if (tickDifference > 0) {
            _applyDamageTaken(_uID, tickDifference, enemyDamage);
            _lootDrops(_uID);
            _giveCombatXP(_uID);
        } else {
            if (charHardcore[_uID]) {
                ownsCharacter[msg.sender][_uID] = false;
            } else {
                charLocation[_uID] = Location.LUMBRIDGE_TOWN_SQ;
            }
        }

        charActionFinishedAt[_uID] = uint64(block.timestamp); // Always unfreeze. The HC death function removes player ownership anyway.
		delete charRandomWords[_uID]; // Must delete the array of random words.
		// No need to delete `charBattleStat` because we explicitly reset it back each time in `initiateCombat()`.
		// No need to delete `charBattleInfo` because we explicitly reset it back each time in `initiateCombat()`.
    }

    function _calculateDamage(uint256 _uID) internal returns (uint256, uint256) {
		uint16[] storage rand = charRandomWords[_uID];
		if (rand[0] == 0) revert NoRandomness(); // can call this function whenever you want as long as you have random words.

        CharBattleInfo storage _charBattleInfo = charBattleInfo[_uID];
		EnemyStats storage eStats = enemyStats[_charBattleInfo.enemy];

        int16 charAttPower = charBattleStat[_uID][Stat.ATT_POWER];
        int16 charMagicPower = charBattleStat[_uID][Stat.MAGIC_POWER];

        if (int16(rand[0]) >= eStats.accuracy - charBattleStat[_uID][Stat.DODGE_CHANCE]) {
            eStats.attPower -= (eStats.attPower * PCT_50) / PCT_100; // enemy missed
        }
	    if (int16(rand[1]) <= eStats.critChance) {
            eStats.attPower += (eStats.attPower * (eStats.critPower - PCT_100)) / PCT_100; // enemy crit
        }

        if (_charBattleInfo.combatSpell == CombatSpell.NONE) {
            // char crit
			if (int16(rand[2]) <= charBattleStat[_uID][Stat.CRIT_CHANCE]) {
                charAttPower += (charAttPower * (charBattleStat[_uID][Stat.CRIT_POWER] - PCT_100)) / PCT_100;
            }
			if (int16(rand[3]) >= charBattleStat[_uID][Stat.ACCURACY] - eStats.dodgeChance) {
                charAttPower -= (charAttPower * PCT_50) / PCT_100; // char missed
            }
		} else {
            // char crit
			if (int16(rand[2]) <= charBattleStat[_uID][Stat.CRIT_CHANCE]) {
                charMagicPower += (charMagicPower * (charBattleStat[_uID][Stat.CRIT_POWER] - PCT_100)) / PCT_100; 
            }
			if (int16(rand[3]) >= charBattleStat[_uID][Stat.ACCURACY] - eStats.dodgeChance) {
                charMagicPower -= (charMagicPower * PCT_50) / PCT_100; // char missed
            }
		}

        uint256 charDamage;
        if (_charBattleInfo.combatSpell == CombatSpell.NONE) {
			charDamage = SafeCast.toUint256(Calculate.damagePerHit(charAttPower, eStats.protection));
		} else {
			charDamage = SafeCast.toUint256(Calculate.damagePerHit(charMagicPower, eStats.protection));
		}
		uint256 enemyDamage = SafeCast.toUint256(Calculate.damagePerHit(eStats.attPower, charBattleStat[_uID][Stat.PROTECTION]));

        return (charDamage, enemyDamage);
    }

    function _calculateTicks(uint256 _uID, uint256 charDamage, uint256 enemyDamage) internal view returns (int256) {
        CharBattleInfo storage _charBattleInfo = charBattleInfo[_uID];
		EnemyStats storage eStats = enemyStats[_charBattleInfo.enemy];

		uint256 hitsUntilEnemyDead = Math.ceilDiv(SafeCast.toUint256(eStats.hp), charDamage); // 250/60 = 5 
		uint256 hitsUntilCharDead = Math.ceilDiv(SafeCast.toUint256(charBattleStat[_uID][Stat.HP]), enemyDamage);  // 350/4 = 9

        // 5 * 10,000 = 50,000 ticks until death
		int256 ticksUntilEnemyDead = int256(hitsUntilEnemyDead * SafeCast.toUint256(charBattleStat[_uID][Stat.ATT_FREQ])); 
        // 9 * 12,000 = 108,000 ticks until death.
		int256 ticksUntilCharDead = int256(hitsUntilCharDead * SafeCast.toUint256(eStats.attFreq)); 
		int256 tickDifference = ticksUntilCharDead - ticksUntilEnemyDead; // 108,000 - 50,000 = 58,000.
        return tickDifference;
    }

    function _applyDamageTaken(uint256 _uID, int256 tickDifference, uint256 enemyDamage) internal {
        CharBattleInfo storage _charBattleInfo = charBattleInfo[_uID];
		EnemyStats storage eStats = enemyStats[_charBattleInfo.enemy];
        uint256 numHits = uint256(tickDifference / eStats.attFreq); // How many hits did the enemy get in? 58,000 / 12,000 = 4.
        uint16 damageTaken = SafeCast.toUint16(numHits * enemyDamage); // How much damage did those hits do? 4 * 40 = 160.
        charStat[_uID][Stat.HP] -= int16(damageTaken);
    }

    function _lootDrops(uint256 _uID) internal {
        uint16[] storage rand = charRandomWords[_uID];
        CharBattleInfo storage _charBattleInfo = charBattleInfo[_uID];
        EnemyDrops storage eDrops = enemyDrops[_charBattleInfo.enemy];

        // Monster drops 
        if (rand[4] <= eDrops.chanceOne && eDrops.dropOne != Token.NOTHING) {
            _mintToken(msg.sender, uint256(eDrops.dropOne), eDrops.amountOne);
        }
        if (rand[5] <= eDrops.chanceTwo && eDrops.dropTwo != Token.NOTHING) {
            _mintToken(msg.sender, uint256(eDrops.dropTwo), eDrops.amountTwo);
        }
        if (rand[6] <= eDrops.chanceThree && eDrops.dropThree != Token.NOTHING) {
            _mintToken(msg.sender, uint256(eDrops.dropThree), eDrops.amountThree);
        }
        if (rand[7] <= eDrops.chanceFour && eDrops.dropFour != Token.NOTHING) {
            _mintToken(msg.sender, uint256(eDrops.dropFour), eDrops.amountFour);
        }
        if (rand[8] <= eDrops.chanceFive && eDrops.dropFive != Token.NOTHING) {
            _mintToken(msg.sender, uint256(eDrops.dropFive), eDrops.amountFive);
        }
    }

    function _giveCombatXP(uint256 _uID) internal {
        GearInfo storage weaponInfo = gearInfo[charEquipment[_uID][GearSlot.MAIN_HAND]];
        XPSplit storage xpValue = xpSplit[weaponInfo.weaponType][charCombatStyle[_uID]];

        CharBattleInfo storage _charBattleInfo = charBattleInfo[_uID];
		EnemyStats storage eStats = enemyStats[_charBattleInfo.enemy];

        ProficiencyInfo storage vitProficiency = charAttribute[_uID][Attribute.VITALITY];
        ProficiencyInfo storage strProficiency = charAttribute[_uID][Attribute.STRENGTH];
        ProficiencyInfo storage agiProficiency = charAttribute[_uID][Attribute.AGILITY];
        ProficiencyInfo storage intProficiency = charAttribute[_uID][Attribute.INTELLIGENCE];

        vitProficiency.xp += eStats.xp / 3; 
        strProficiency.xp += (eStats.xp * xpValue.strXP) / 100; 
        agiProficiency.xp += (eStats.xp * xpValue.agiXP) / 100;
        intProficiency.xp += (eStats.xp * xpValue.intXP) / 100;
        
        if (xpTable[vitProficiency.level + 1] <= vitProficiency.xp) {
            vitProficiency.level++;
            charStat[_uID][Stat.MAX_HP] += 10;
            charStat[_uID][Stat.PROTECTION] += 5;
            emit AttributeLevelUp(Attribute.VITALITY, vitProficiency.level);
        }

        if (xpTable[strProficiency.level + 1] <= strProficiency.xp) {
            strProficiency.level++;
            charStat[_uID][Stat.ATT_POWER] += 5;
            charStat[_uID][Stat.CRIT_POWER] += 100;
            emit AttributeLevelUp(Attribute.STRENGTH, strProficiency.level);
        }

        if (xpTable[agiProficiency.level + 1] <= agiProficiency.xp) {
            agiProficiency.level++;
            charStat[_uID][Stat.ATT_FREQ] -= 20;
            charStat[_uID][Stat.DODGE_CHANCE] += 20;
            charStat[_uID][Stat.CRIT_CHANCE] += 20;
            emit AttributeLevelUp(Attribute.AGILITY, agiProficiency.level);
        }

        if (xpTable[intProficiency.level + 1] <= intProficiency.xp) {
            intProficiency.level++;
            charStat[_uID][Stat.MAGIC_POWER] += 5;
            charStat[_uID][Stat.ACCURACY] += 10;
            emit AttributeLevelUp(Attribute.INTELLIGENCE, intProficiency.level);
        }

        int16 oldCmbLvl = charStat[_uID][Stat.CMB_LVL];
        int16 newCmbLvl = Calculate.combatLevel(vitProficiency.level, strProficiency.level, agiProficiency.level, intProficiency.level);
        if (newCmbLvl > oldCmbLvl) {
            charStat[_uID][Stat.CMB_LVL] = newCmbLvl;
            emit CombatLevelUp(newCmbLvl);
        }
    }

	function fixStuckCharacter(uint256 _uID) external {
		_ownsCharacterCheck(msg.sender, _uID);
		if (charActionFinishedAt[_uID] != type(uint64).max) revert NotFrozen();
		uint16[] storage rand = charRandomWords[_uID];
		if (rand[0] != 0) revert AlreadyHasRandomness();
		if (block.timestamp > charRequestTime[_uID] + 93600) revert StillPendingRandomness();
		charActionFinishedAt[_uID] = uint64(block.timestamp);
		emit CharacterReleased(_uID);
	}

    function _setGameData() internal {

        // Set Character Minting Price & Combat Price (Native gas token amount)
        characterSalePrice = 5e18;
        combatPrice = 5e16;

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

        // Set tool info (hatchets, pickaxes, etc.) (skill, reqLvl, gatherSpeed)
        toolInfo[Token.IRON_HATCHET] = ToolInfo(Skill.WOODCUTTING, 1, 10); // maybe make 10000 = 100% speed
        toolInfo[Token.STEEL_HATCHET] = ToolInfo(Skill.WOODCUTTING, 15, 15);
        toolInfo[Token.IRON_PICKAXE] = ToolInfo(Skill.MINING, 1, 10);

        // Set gear info (slotOne, slotTwo, weapon type, enchantElement, enchantStat, STR/AGIL/INT ...
        // (... attPower, attSpeed, dodge, critChance, critPower, magicPower, prot, accuracy, enchant pct, enchant amnt)
        // Elemental enchantments have no amnt or pct. Wands and staves cannot have elemental enchantments.
        gearInfo[Token.IRON_SWORD] = GearInfo(
            GearSlot.MAIN_HAND, GearSlot.NONE, WeaponType.SWORD, Element.NONE, Stat.NONE, 1, 1, 1, 10, 500, 0, 100, 1000, 0, 0, 1000, 0, 0);

        gearInfo[Token.RING_OF_BLOOD] = GearInfo(
            GearSlot.RING_ONE, GearSlot.RING_TWO, WeaponType.NONE, Element.NONE, Stat.ATT_POWER, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 500);

        gearInfo[Token.IRON_2H_SWORD] = GearInfo(
            GearSlot.MAIN_HAND, GearSlot.OFF_HAND, WeaponType.SWORD, Element.NONE, Stat.NONE, 1, 1, 1, 10, 500, 0, 100, 1000, 0, 0, 1000, 0, 0);

        // Set staff and wand spell types.
        element[Token.WATER_STAFF] = Element.WATER;
        element[Token.EARTH_STAFF] = Element.EARTH;
        element[Token.FIRE_STAFF] = Element.FIRE;
        element[Token.AIR_STAFF] = Element.AIR;
        element[Token.AIR_WAND] = Element.AIR;
        element[Token.OMNI_STAFF] = Element.OMNI;

        // Set combat spell info. (All tiers have same power, monster weaknesses effect daamge though. omni requires more crystal bc its lazy)
        combatSpellInfo[CombatSpell.WATER_BLAST] = CombatSpellInfo({
            spellInfo: SpellInfo({elementType: Element.WATER, requiredLevel: 1, xp: 200, numCrystals: 1}), attFreq: 0, magicPower: 60, accuracy: 0
        });
        combatSpellInfo[CombatSpell.EARTH_BLAST] = CombatSpellInfo({
            spellInfo: SpellInfo({elementType: Element.EARTH, requiredLevel: 5, xp: 400, numCrystals: 1}), attFreq: 0, magicPower: 60, accuracy: 0
        });
        combatSpellInfo[CombatSpell.FIRE_BLAST] = CombatSpellInfo({
            spellInfo: SpellInfo({elementType: Element.FIRE, requiredLevel: 10, xp: 800, numCrystals: 1}), attFreq: 0, magicPower: 60, accuracy: 0
        });
        combatSpellInfo[CombatSpell.AIR_BLAST] = CombatSpellInfo({
            spellInfo: SpellInfo({elementType: Element.AIR, requiredLevel: 15, xp: 1200, numCrystals: 1}), attFreq: 0, magicPower: 60, accuracy: 0
        });
        combatSpellInfo[CombatSpell.OMNI_BLAST] = CombatSpellInfo({
            spellInfo: SpellInfo({elementType: Element.OMNI, requiredLevel: 25, xp: 3000, numCrystals: 2}), attFreq: 0, magicPower: 60, accuracy: 0
        });

        // Set teleport spell info.
        teleportSpellInfo[TeleportSpell.TELEPORT_TO_LUMBRIDGE] = TeleportSpellInfo({
            spellInfo: SpellInfo({elementType: Element.AIR, requiredLevel: 30, xp: 200, numCrystals: 1}), destination: Location.LUMBRIDGE_TOWN_SQ
        });
        teleportSpellInfo[TeleportSpell.TELEPORT_TO_FALADOR] = TeleportSpellInfo({
            spellInfo: SpellInfo({elementType: Element.AIR, requiredLevel: 40, xp: 300, numCrystals: 2}), destination: Location.FALADOR_TOWN_SQ
        });
        teleportSpellInfo[TeleportSpell.TELEPORT_TO_VELRICK] = TeleportSpellInfo({
            spellInfo: SpellInfo({elementType: Element.AIR, requiredLevel: 50, xp: 400, numCrystals: 3}), destination: Location.VELRICK_TOWN_SQ
        });

        // Set buff spell info.
        buffSpellInfo[BuffSpell.IMBUED_SOUL] = BuffSpellInfo({
            spellInfo: SpellInfo({elementType: Element.WATER, requiredLevel: 5, xp: 100, numCrystals: 1}),
            stat: Stat.MAGIC_POWER, duration: 3600, amount: 0, percentage: 1000
        });
        buffSpellInfo[BuffSpell.KEEN_EYE] = BuffSpellInfo({
            spellInfo: SpellInfo({elementType: Element.AIR, requiredLevel: 10, xp: 200, numCrystals: 2}),
            stat: Stat.ACCURACY, duration: 1800, amount: 500, percentage: 0
        });
        buffSpellInfo[BuffSpell.STONE_SKIN] = BuffSpellInfo({
            spellInfo: SpellInfo({elementType: Element.EARTH, requiredLevel: 25, xp: 500, numCrystals: 3}),
            stat: Stat.PROTECTION, duration: 1800, amount: 50, percentage: 0
        });
        buffSpellInfo[BuffSpell.IRON_SKIN] = BuffSpellInfo({
            spellInfo: SpellInfo({elementType: Element.EARTH, requiredLevel: 35, xp: 800, numCrystals: 5}),
            stat: Stat.PROTECTION, duration: 1800, amount: 150, percentage: 0
        });
        buffSpellInfo[BuffSpell.SHADOW_SKIN] = BuffSpellInfo({
            spellInfo: SpellInfo({elementType: Element.WATER, requiredLevel: 50, xp: 1400, numCrystals: 8}),
            stat: Stat.DODGE_CHANCE, duration: 900, amount: 500, percentage: 0
        });
        buffSpellInfo[BuffSpell.ANCIENT_RAGE] = BuffSpellInfo({
            spellInfo: SpellInfo({elementType: Element.FIRE, requiredLevel: 60, xp: 3000, numCrystals: 20}),
            stat: Stat.ATT_POWER, duration: 600, amount: 0, percentage: 2000
        });

        // set item consumable effects. (stat1, stat2, amnt1, amnt2, duration). (Always static even if attPower or magicPower).
        consumableInfo[Token.HEALTH_POTION] = ConsumableInfo(Stat.HP, Stat.NONE, 50, 0, 0);
        consumableInfo[Token.STRENGTH_POTION] = ConsumableInfo(Stat.ATT_POWER, Stat.NONE, 1000, 0, 900);
        consumableInfo[Token.PROTECTION_POTION] = ConsumableInfo(Stat.PROTECTION, Stat.NONE, 20, 0, 900);
        consumableInfo[Token.SALMON] = ConsumableInfo(Stat.PROTECTION, Stat.DODGE_CHANCE, 10, 200, 600);

        // set inn buff values
        innBuffValue[Stat.DODGE_CHANCE] = 200;
        innBuffValue[Stat.CRIT_CHANCE] = 100;
        innBuffValue[Stat.CRIT_POWER] = 1000;
        innBuffValue[Stat.ACCURACY] = 200;

		// Set combat xp based on weapon and combat style (STR, AGI, INT)
		xpSplit[WeaponType.SWORD][CombatStyle.NONE] = XPSplit(100, 0, 0);
		xpSplit[WeaponType.SWORD][CombatStyle.BARBARIC] = XPSplit(150, 0, 0);
		xpSplit[WeaponType.SWORD][CombatStyle.DEXTEROUS] = XPSplit(75, 25, 0);
		xpSplit[WeaponType.SWORD][CombatStyle.MEDITATIVE] = XPSplit(75, 0, 25);

		xpSplit[WeaponType.AXE][CombatStyle.NONE] = XPSplit(100, 0, 0);
		xpSplit[WeaponType.AXE][CombatStyle.BARBARIC] = XPSplit(150, 0, 0);
		xpSplit[WeaponType.AXE][CombatStyle.DEXTEROUS] = XPSplit(75, 25, 0);
		xpSplit[WeaponType.AXE][CombatStyle.MEDITATIVE] = XPSplit(75, 0, 25);

		xpSplit[WeaponType.BLUNT][CombatStyle.NONE] = XPSplit(100, 0, 0);
		xpSplit[WeaponType.BLUNT][CombatStyle.BARBARIC] = XPSplit(150, 0, 0);
		xpSplit[WeaponType.BLUNT][CombatStyle.DEXTEROUS] = XPSplit(75, 25, 0);
		xpSplit[WeaponType.BLUNT][CombatStyle.MEDITATIVE] = XPSplit(75, 0, 25);

		xpSplit[WeaponType.POLEARM][CombatStyle.NONE] = XPSplit(50, 50, 0);
		xpSplit[WeaponType.POLEARM][CombatStyle.BARBARIC] = XPSplit(100, 0, 0);
		xpSplit[WeaponType.POLEARM][CombatStyle.DEXTEROUS] = XPSplit(0, 100, 0);
		xpSplit[WeaponType.POLEARM][CombatStyle.MEDITATIVE] = XPSplit(33, 33, 33);

		xpSplit[WeaponType.DAGGER][CombatStyle.NONE] = XPSplit(0, 100, 0);
		xpSplit[WeaponType.DAGGER][CombatStyle.BARBARIC] = XPSplit(25, 75, 0);
		xpSplit[WeaponType.DAGGER][CombatStyle.DEXTEROUS] = XPSplit(0, 150, 0);
		xpSplit[WeaponType.DAGGER][CombatStyle.MEDITATIVE] = XPSplit(0, 75, 25);

		xpSplit[WeaponType.CURVED_SWORD][CombatStyle.NONE] = XPSplit(0, 100, 0);
		xpSplit[WeaponType.CURVED_SWORD][CombatStyle.BARBARIC] = XPSplit(25, 75, 0);
		xpSplit[WeaponType.CURVED_SWORD][CombatStyle.DEXTEROUS] = XPSplit(0, 150, 0);
		xpSplit[WeaponType.CURVED_SWORD][CombatStyle.MEDITATIVE] = XPSplit(0, 75, 25);

		xpSplit[WeaponType.THROWN][CombatStyle.NONE] = XPSplit(0, 100, 0);
		xpSplit[WeaponType.THROWN][CombatStyle.BARBARIC] = XPSplit(25, 75, 0);
		xpSplit[WeaponType.THROWN][CombatStyle.DEXTEROUS] = XPSplit(0, 150, 0);
		xpSplit[WeaponType.THROWN][CombatStyle.MEDITATIVE] = XPSplit(0, 75, 25);
		
		xpSplit[WeaponType.BOW][CombatStyle.NONE] = XPSplit(0, 100, 0);
		xpSplit[WeaponType.BOW][CombatStyle.BARBARIC] = XPSplit(25, 75, 0);
		xpSplit[WeaponType.BOW][CombatStyle.DEXTEROUS] = XPSplit(0, 150, 0);
		xpSplit[WeaponType.BOW][CombatStyle.MEDITATIVE] = XPSplit(0, 75, 25);

		xpSplit[WeaponType.WAND][CombatStyle.NONE] = XPSplit(0, 0, 100);
		xpSplit[WeaponType.WAND][CombatStyle.BARBARIC] = XPSplit(0, 0, 0);
		xpSplit[WeaponType.WAND][CombatStyle.DEXTEROUS] = XPSplit(0, 0, 0);
		xpSplit[WeaponType.WAND][CombatStyle.MEDITATIVE] = XPSplit(0, 0, 150);

		xpSplit[WeaponType.STAFF][CombatStyle.NONE] = XPSplit(0, 0, 100);
		xpSplit[WeaponType.STAFF][CombatStyle.BARBARIC] = XPSplit(0, 0, 0);
		xpSplit[WeaponType.STAFF][CombatStyle.DEXTEROUS] = XPSplit(0, 0, 0);
		xpSplit[WeaponType.STAFF][CombatStyle.MEDITATIVE] = XPSplit(0, 0, 150);

		// Enemy Stats (elementType, xp, hp, attPower, attFreq, dodge, critChance, critPower, protection, accuracy)
		enemyStats[Enemy.FROG] = EnemyStats(Element.WATER, 50, 50, 10, 20000, 500, 300, 12000, 3, 9500);

		// Enemy Drops (drops, amounts, chances)
		enemyDrops[Enemy.FROG] = EnemyDrops(
			Token.WATER_STAFF, Token.WATER_WAND, Token.IRON_HATCHET, Token.NOTHING, Token.NOTHING,
			1, 1, 1, 0, 0, 500, 500, 1000, 0, 0
        );

        // Set combatStyleBuffs
   		// (attPower %, attFreq (- is faster, + is slower), dodgeChance, critChance, critPower, magicPower %, accuracy)
		combatStyleBuff[CombatStyle.BARBARIC] = CombatStyleBuff(1500, 500, -500, -500, 2500, 0, -1000);
		combatStyleBuff[CombatStyle.DEXTEROUS] = CombatStyleBuff(-1000, -500, 500, 1000, -1500, 0, 500);
		combatStyleBuff[CombatStyle.MEDITATIVE] = CombatStyleBuff(-5000, 1000, 0, 0, 0, 2500, 1000);     

        // Set weakness/strength table
        weakStrong[Element.WATER][Element.AIR] = WeakStrong(true, false); 
		weakStrong[Element.EARTH][Element.FIRE] = WeakStrong(true, false);
		weakStrong[Element.FIRE][Element.WATER] = WeakStrong(true, false);
		weakStrong[Element.AIR][Element.EARTH] = WeakStrong(true, false);

		weakStrong[Element.WATER][Element.FIRE] = WeakStrong(false, true);
		weakStrong[Element.EARTH][Element.AIR] = WeakStrong(false, true);
		weakStrong[Element.FIRE][Element.EARTH] = WeakStrong(false, true);
		weakStrong[Element.AIR][Element.WATER] = WeakStrong(false, true);


        // Set crafting info for items. (skill, reqLvl, xp, timeToProduce, amountPerOutput, token1, token2, token3, amnt1, amnt2, amnt3)
        craftingInfo[Token.IRON_SWORD] = CraftingInfo(
            Skill.BLACKSMITHING, 15, 500, 30, 1, Token.GOLD_COINS, Token.IRON_INGOT, Token.NOTHING, 42, 2, 0
        );
        craftingInfo[Token.IRON_INGOT] = CraftingInfo(
            Skill.BLACKSMITHING, 10, 100, 30, 1, Token.IRON_ORE, Token.NOTHING, Token.NOTHING, 2, 0, 0
        );
        craftingInfo[Token.IRON_SWORD_OF_FIRE] = CraftingInfo(
            Skill.ENCHANTING, 10, 500, 10, 1, Token.ESSENCE_CRYSTAL, Token.FIRE_ORB, Token.NOTHING, 5, 1, 0
        );

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
    
    function changeCharacterMintingPrice(uint64 newPrice) external onlyOwner {
        if (newPrice > MAX_CHARACTER_PRICE) revert MintingTooExpensive();
        characterSalePrice = newPrice; // Good for holiday discounts, price never increases beyond maximum.
    }

    function changeCombatPrice(uint64 newPrice) external onlyOwner {
        if (newPrice > MAX_COMBAT_PRICE) revert CombatTooExpensive();
        combatPrice = newPrice;
    }

    function setURIWithID(uint256 tokenID, string memory tokenURI) external onlyOwner {
        _setURI(tokenID, tokenURI); // See ERC1155URIStorage._setURI(). (NOT ERC1155._setURI()?)
    }

    function setBaseURI(string memory baseURI) external onlyOwner {
        _setBaseURI(baseURI); // See ERC1155URIStorage._setBaseURI().
    }

    function setVRFData(
        uint64 _subscriptionId, 
        bytes32 _keyHash, 
        uint32 _callbackGasLimit, 
        uint16 _requestConfirmations
    ) 
        public onlyOwner 
    {
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
    } 

    // ------------ OPTIONAL & REQUIRED OVERRIDES ------------

    // Test that we cannot transfer characters.
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