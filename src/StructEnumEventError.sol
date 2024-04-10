// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; 

abstract contract StructEnumEventError {

    struct GearInfo {
        GearSlot slotOne; // Most gear pieces only have one slot (Besides 2H and rings).
        GearSlot slotTwo;
        WeaponType weaponType;
        Element enchantElement;
        Stat enchantStat;
        uint8 requiredStrengthLevel;
        uint8 requiredAgilityLevel;
        uint8 requiredIntelligenceLevel;
        int16 attPower; // use power+speed to calculate dps, or power to calculate max hit.
        int16 attFreq; // lower = faster
        int16 dodgeChance; // higher = better [0, 10000] 100%
        int16 critChance; // higher = better [0, 10000] 100%
        int16 critPower; // 150 to 400 (1.1x to 4x)
        int16 magicPower; // for spells
        int16 protection; // gained from armor
        int16 accuracy; // for magic, bows, and melee
        int16 enchantAmount; // amnt based
        int16 enchantPercent; // pct based
    }

    struct XPSplit {
        uint8 strXP;
        uint8 agiXP;
        uint8 intXP;
    }

    struct EnemyStats {
        Element elementType;
        uint16 xp;
		int16 hp;
		int16 attPower; 
		int16 attFreq;  
		int16 dodgeChance; 
		int16 critChance; 
		int16 critPower; 
		int16 protection; 
		int16 accuracy;   
	}
	
	struct EnemyDrops {
		Token dropOne;
		Token dropTwo;
		Token dropThree;
		Token dropFour;
		Token dropFive;
		uint8 amountOne;
		uint8 amountTwo;
		uint8 amountThree;
		uint8 amountFour;
		uint8 amountFive;
		uint16 chanceOne;
		uint16 chanceTwo;
		uint16 chanceThree;
		uint16 chanceFour;
		uint16 chanceFive;
	}

    struct WeakStrong {
        bool isWeak;
        bool isStrong;
    }

	struct CharBattleInfo {
		Enemy enemy;
		CombatStyle combatStyle;
		CombatSpell combatSpell;
	}

	struct CombatStyleBuff {
		int16 attPower; 
        int16 attFreq; 
        int16 dodgeChance; 
        int16 critChance;
        int16 critPower; 
        int16 magicPower; 
        int16 accuracy; 
	}

    struct SpellInfo {
        Element elementType;
        uint8 requiredLevel;
        uint16 xp;
        uint8 numCrystals; 
    }

    struct TeleportSpellInfo {
        SpellInfo spellInfo;
        Location destination; 
    }

    // When you choose a spell for combat, these stats get added to your current stats.
    struct CombatSpellInfo {
        SpellInfo spellInfo;
        int16 attFreq;
        int16 magicPower;
        int16 accuracy;
    }

    struct BuffSpellInfo {
        SpellInfo spellInfo;
        Stat stat;
        uint64 duration;
        int16 amount; // static amount increase
        int16 percentage; // percentage based increase
    }

    struct CharSpellBuffs {
        BuffSpell buffSpellOne;
        BuffSpell buffSpellTwo;
        uint64 oneEndsAt;
        uint64 twoEndsAt;
    }

    struct ConsumableInfo {
        Stat statOne;
        Stat statTwo;
        int16 amountOne;
        int16 amountTwo;
        uint64 duration;
    }

    struct CharConsumableBuffs {
        Token consumableOne;
        Token consumableTwo;
        uint64 oneEndsAt;
        uint64 twoEndsAt;
    }
  
    struct ResourceInfo {
        Token material;
        Skill skill;
        uint8 requiredLevel;
        uint16 xp; 
        uint16 gatherSpeed; 
    }

    struct ToolInfo {
        Skill skill;
        uint8 requiredLevel;
        uint16 gatherSpeed;
    }

    struct CraftingInfo {
        Skill skill;
        uint8 requiredLevel;
        uint16 xp;
        uint64 timeToProduce;
        uint8 amountPerOutput;
        Token tokenOne;
        Token tokenTwo;
        Token tokenThree;
        uint8 amountOne;
        uint8 amountTwo;
        uint8 amountThree;
    }

    struct PriceInfo {
        uint256 buyPrice;
        uint256 sellPrice;
    }

    struct Coordinates {
        int256 x; // can maybe make these smaller in future
        int256 y; // can maybe make these smaller in future
    }

    struct ProficiencyInfo {
        uint8 level;
        uint32 xp;
    }

    enum Skill {MINING, BLACKSMITHING, WOODCUTTING, WOODWORKING, FISHING, COOKING, LEATHERWORKING, CLOTHWORKING, ALCHEMY, ENCHANTING}
    enum Attribute {VITALITY, STRENGTH, AGILITY, INTELLIGENCE}
    enum Stat {NONE, CMB_LVL, MAX_HP, HP, ATT_POWER, ATT_FREQ, DODGE_CHANCE, CRIT_CHANCE, CRIT_POWER, MAGIC_POWER, PROTECTION, ACCURACY}
    enum GearSlot {NONE, MAIN_HAND, OFF_HAND, HEAD, CHEST, LEGS, GLOVES, BOOTS, CLOAK, RING_ONE, RING_TWO, AMULET}
    enum BuffSpell {NONE, STONE_SKIN, IRON_SKIN, SHADOW_SKIN, ANCIENT_RAGE, KEEN_EYE, IMBUED_SOUL}
    enum TeleportSpell {TELEPORT_TO_LUMBRIDGE, TELEPORT_TO_FALADOR, TELEPORT_TO_VELRICK}
    enum CombatSpell {NONE, AIR_BLAST, WATER_BLAST, EARTH_BLAST, FIRE_BLAST, OMNI_BLAST}
    enum Element {NONE, AIR, WATER, EARTH, FIRE, OMNI} 
    enum WeaponType {NONE, SWORD, AXE, DAGGER, CURVED_SWORD, BLUNT, POLEARM, THROWN, BOW, WAND, STAFF}
    enum CombatStyle {NONE, BARBARIC, DEXTEROUS, MEDITATIVE}

    enum Resource {
        NORMAL_TREE, OAK_TREE, WILLOW_TREE, MAPLE_TREE, YEW_TREE, MAGIC_TREE,
        IRON_VEIN, COAL_VEIN, MITHRIL_VEIN, ADAMANT_VEIN, RUNITE_VEIN,
        RAW_SHRIMP, RAW_TROUT, RAW_TUNA, RAW_LOBSTER, RAW_SWORDFISH, RAW_SHARK
    }

    enum Enemy {NONE, FROG, RABBIT, BEAR, SPIDER, WOLF, THIEF, MERCENARY, THUG, SKELETON, ZOMBIE, VAMPIRE, GREEN_DRAGON, GULAK, MEHBIM, GHIVILIN}

    // The tokenized items in the game representing the ERC1155 Token id. They must match the token_metadata `{ID}.json` files.
    enum Token {
        NOTHING, ALICE, BOB, GOLD_COINS, ESSENCE_CRYSTAL,
        IRON_SWORD, IRON_2H_SWORD, IRON_BATTLEAXE,
        IRON_HATCHET, STEEL_HATCHET, IRON_PICKAXE,
        NORMAL_WOOD, OAK_WOOD, WILLOW_WOOD, MAPLE_WOOD, YEW_WOOD, MAGIC_WOOD, 
        STRENGTH_POTION, HEALTH_POTION, PROTECTION_POTION,
        RING_OF_BLOOD, IRON_SWORD_OF_FIRE, SALMON, FIRE_ORB,
        IRON_ORE, COAL_ORE, IRON_INGOT, 
        WATER_STAFF, EARTH_STAFF, FIRE_STAFF, AIR_STAFF, OMNI_STAFF, 
        ENHANCED_WATER_STAFF, ENHANCED_EARTH_STAFF, ENHANCED_FIRE_STAFF, ENHANCED_AIR_STAFF,   
        WATER_WAND, EARTH_WAND, FIRE_WAND, AIR_WAND, OMNI_WAND
    }

    enum Location {
        LUMBRIDGE_TOWN_SQ, L_BLACKSMITH, L_GENERAL_STORE, L_RANGE_SHOP, L_MAGE_SHOP, L_INN, // [0-5]
        FALADOR_TOWN_SQ, F_BLACKSMITH, F_GENERAL_STORE, F_RANGE_SHOP, F_MAGE_SHOP, F_INN, // [6-11]
        VELRICK_TOWN_SQ, V_BLACKSMITH, V_GENERAL_STORE, V_RANGE_SHOP, V_MAGE_SHOP, V_INN, // [12-17]
        FOREST_ONE, FOREST_TWO, FOREST_THREE, FOREST_FOUR, FOREST_FIVE, // [18-22]
        CAVE_ONE, CAVE_TWO, CAVE_THREE, CAVE_FOUR, CAVE_FIVE, // [23-27]
        MINE_ONE, MINE_TWO, MINE_THREE, MINE_FOUR, MINE_FIVE, // [28-32]
        SPECIAL_LOCATION_ONE, SPECIAL_LOCATION_TWO, SPECIAL_LOCATION_THREE, SPECIAL_LOCATION_FOUR, SPECIAL_LOCATION_FIVE // [33-37]
    }

    // Note: Haven't added most events yet.
    event SkillLevelUp(Skill skill, uint8 indexed level);
    event AttributeLevelUp(Attribute attribute, uint8 indexed level);
    event CombatLevelUp(int16 indexed cmblvl);
    event CharacterReleased(uint256 indexed _uID);

    error NotACharacter(); // 0x72cd097c
    error InvalidAmount(); // 0x2c5211c6
    error FailedCall(); // 0xd6bda275
    error AlreadyThere(); // 0x73c950e6
    error StillDoingAction(); // 0x5e99f373
    error NotInStock(); // 0xb4c4332c
    error NotAtLocation(); // 0x039906b7
    error NotShopLocation(); // 0x725cae1b
    error DoNotOwnItem(Token item); // ????
    error NotTool(); // 0xc1ab5181
    error WrongToolForTheJob(); // 0xeea110e5
    error Noob(); // 0x53bc8411
    error NotGear(); // 0xf0a68a55
    error WrongCraftingLocation(); // 0x291d724c
    error InvalidCraftingOutput(); // 0xd03be717
    error CannotUnequipNothing(); // 0x92746c1a
    error ItemNotEquipped(); // 0x54962c76
    error WrongElement(); // ????
    error SameBuffType(); // 0xb7b2c020
    error NotAConsumable(); // 0xcab7a8b8
    error ResourceNotHere(); // 0xa76046ac
    error NotAnInn(); // 0x13e9e663
    error NotGameContract(); // 0xd5fe8702
    error MintingTooExpensive(); // 0x01e49b9b
    error CannotTransferCharacters(); // 0x48d2e23c
    error DoesNotOwnCharacter(); // 0x1c2d9d38
    error CombatTooExpensive(); // ???
    error EnemyNotHere(); // ???
    error NoSpellSelected(); // ???
    error InvalidStyle(); // ???
    error NoRandomness(); // ???
    error NotFrozen(); // ???
    error AlreadyHasRandomness(); // ???
    error StillPendingRandomness(); // ???
}