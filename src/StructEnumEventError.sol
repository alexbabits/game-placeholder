// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; 

abstract contract StructEnumEventError {

    struct GearInfo {
        GearSlot slot;
        bool twoHand; // Does it require both mainHand and offHand gear slot to equip?
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
        int16 attRange; // maximum attack distance
        Enchantment enchantment;
        int16 enchantAmount;
        int16 enchantPercent;
    }

    struct TeleportSpellInfo {
        Location destination;
        uint8 requiredLevel;
        uint16 xp;
        uint8 numberOfEssenceCrystals;
    }

    // Only for buff and combat spells, teleport spells can handle everything in their own struct.
    struct SpellInfo {
        Element element;
        uint8 requiredLevel;
        uint16 xp;
        uint8 numberOfEssenceCrystals;
    }

    struct BuffSpellEffects {
        Stat stat;
        uint64 duration;
        int16 amount; // static amount increase
        int16 percentage; // percentage based increase
    }

    struct BuffSpellsApplied {
        BuffSpell buffSpellOne;
        BuffSpell buffSpellTwo;
        uint64 buffOneEndsAt;
        uint64 buffTwoEndsAt;
    }

    struct ConsumableInfo {
        Stat statOne;
        Stat statTwo;
        int16 amountOne;
        int16 percentageOne;
        int16 amountTwo;
        int16 percentageTwo;
        uint64 duration;
    }

    struct ConsumableBuffsApplied {
        Token consumableOne;
        Token consumableTwo;
        uint64 consumableOneEndsAt;
        uint64 consumableTwoEndsAt;
    }

    // attackRange for combat spells is already handled in GearInfo via the `wand` or `staff` equipment info that's already applied. When you choose a spell for combat, these stats get added to your current stats.
    struct CombatSpellEffects {
        int16 attFreq;
        int16 magicPower;
        int16 accuracy;
    }

    struct ProficiencyInfo {
        uint8 level;
        uint32 xp;
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

    enum Skill {MINING, BLACKSMITHING, WOODCUTTING, WOODWORKING, FISHING, COOKING, LEATHERWORKING, CLOTHWORKING, ALCHEMY, ENCHANTING}
    enum Attribute {VITALITY, STRENGTH, AGILITY, INTELLIGENCE}
    enum Stat {NONE, CMB_LVL, MAX_HP, HP, ATT_POWER, ATT_FREQ, ATT_RANGE, DODGE_CHANCE, CRIT_CHANCE, CRIT_POWER, MAGIC_POWER, PROTECTION, ACCURACY}
    enum GearSlot {NULL, MAIN_HAND, OFF_HAND, HEAD, CHEST, LEGS, GLOVES, BOOTS, CLOAK, RING_ONE, RING_TWO, AMULET}

    enum Enchantment {NONE, AIR, WATER, EARTH, FIRE, OMNI, LIFE_LEECH, ATT_POWER, CRIT_CHANCE, CRIT_POWER, MAGIC_POWER, ACCURACY}

    enum BuffSpell {NONE, STONE_SKIN, IRON_SKIN, SHADOW_SKIN, ANCIENT_RAGE, KEEN_EYE, IMBUED_SOUL}
    enum TeleportSpell {TELEPORT_TO_LUMBRIDGE, TELEPORT_TO_FALADOR, TELEPORT_TO_VELRICK}
    enum CombatSpell {AIR_BLAST, WATER_BLAST, EARTH_BLAST, FIRE_BLAST, OMNI_BLAST}
    enum Element {NONE, AIR, WATER, EARTH, FIRE, OMNI} 

    enum Resource {
        NORMAL_TREE, OAK_TREE, WILLOW_TREE, MAPLE_TREE, YEW_TREE, MAGIC_TREE,
        IRON_VEIN, COAL_VEIN, MITHRIL_VEIN, ADAMANT_VEIN, RUNITE_VEIN,
        RAW_SHRIMP, RAW_TROUT, RAW_TUNA, RAW_LOBSTER, RAW_SWORDFISH, RAW_SHARK
    }

    // The tokenized items in the game representing the ERC1155 Token id. They must match the token_metadata `{ID}.json` files.
    // (I can format these better, "grouping" them horizontal for less space)
    enum Token {
        NOTHING, // 0
        ALICE, // 1
        BOB, // 2
        GOLD_COINS, // 3
        IRON_SWORD, // 4
        IRON_2H_SWORD, // 5
        IRON_BATTLEAXE, // 6
        IRON_HATCHET, // 7
        STEEL_HATCHET, // 8
        NORMAL_WOOD, // 9
        OAK_WOOD, // 10
        WILLOW_WOOD, // 11
        MAPLE_WOOD, // 12
        YEW_WOOD, // 13
        MAGIC_WOOD, // 14
        STRENGTH_POTION, // 15
        IRON_PICKAXE, // 16 (not implemented URI yet)
        RING_OF_BLOOD, // 17 (not implemented URI yet)
        IRON_ORE, // 18 (not implemented URI yet)
        COAL_ORE, // 19 (not implemented URI yet)
        HEALTH_POTION, // 20 (not implemented URI yet)
        PROTECTION_POTION, // 21 (not implemented URI yet)
        IRON_INGOT, // 22 (not implemented URI yet)
        ESSENCE_CRYSTAL, // 23 (not implemented URI yet)
        FIRE_STAFF, // 24 (not implemented URI yet)
        WATER_STAFF, // 25 (not implemented URI yet)
        EARTH_STAFF, // 26 (not implemented URI yet)
        AIR_STAFF, // 27 (not implemented URI yet)
        OMNI_STAFF, // 28 (not implemented URI yet)
        ENHANCED_FIRE_STAFF, // 29 (not implemented URI yet)
        ENHANCED_WATER_STAFF, // 30 (not implemented URI yet)
        ENHANCED_EARTH_STAFF, // 31 (not implemented URI yet)
        ENHANCED_AIR_STAFF, // 32 (not implemented URI yet)
        AIR_WAND, // 33 (not implemented URI yet)
        SALMON // 34 (not implemented URI yet)
    }

    // (I can format these better, "grouping" them horizontal for less space)
    enum Location {
        LUMBRIDGE_TOWN_SQ, // 0
        L_BLACKSMITH, // 1
        L_GENERAL_STORE, // 2
        L_RANGE_SHOP, // 3
        L_MAGE_SHOP, // 4
        L_INN, // 5
        FALADOR_TOWN_SQ, // 6
        F_BLACKSMITH, // 7
        F_GENERAL_STORE, // 8
        F_RANGE_SHOP, // 9
        F_MAGE_SHOP, // 10
        F_INN, // 11
        VELRICK_TOWN_SQ, // 12
        V_BLACKSMITH, // 13
        V_GENERAL_STORE, // 14
        V_RANGE_SHOP, // 15
        V_MAGE_SHOP, // 16
        V_INN, // 17
        FOREST_ONE, // 18
        FOREST_TWO, // 19
        FOREST_THREE, // 20
        FOREST_FOUR, // 21 
        FOREST_FIVE, // 22
        CAVE_ONE, // 23
        CAVE_TWO, // 24
        CAVE_THREE, // 25
        CAVE_FOUR, // 26
        CAVE_FIVE, // 27
        MINE_ONE, // 28
        MINE_TWO, // 29
        MINE_THREE, // 30
        MINE_FOUR, // 31
        MINE_FIVE, // 32
        SPECIAL_LOCATION_ONE, // 33
        SPECIAL_LOCATION_TWO, // 34
        SPECIAL_LOCATION_THREE, // 35
        SPECIAL_LOCATION_FOUR, // 36
        SPECIAL_LOCATION_FIVE // 37
    }

    error NotACharacter(); // 0x72cd097c
    error InvalidAmount(); // 0x2c5211c6
    error FailedCall(); // 0xd6bda275
    error AlreadyThere(); // 0x73c950e6
    error StillDoingAction(); // 0x5e99f373
    error NotInStock(); // 0xb4c4332c
    error NotAtLocation(); // 0x039906b7
    error NotShopLocation(); // 0x725cae1b
    error DoNotOwnItem(); // 0x62b51396
    error NotTool(); // 0xc1ab5181
    error WrongToolForTheJob(); // 0xeea110e5
    error Noob(); // 0x53bc8411
    error NotGear(); // 0xf0a68a55
    error WrongCraftingLocation(); // 0x291d724c
    error InvalidCraftingOutput(); // 0xd03be717
    error CannotUnequipNothing(); // 0x92746c1a
    error ItemNotEquipped(); // 0x54962c76
    error AlreadyEquipped(); // 0x2e53a303
    error InvalidWeaponElementType(); // 0x14229251
    error SameBuffType(); // 0xb7b2c020
    error NotAConsumable(); // 0xcab7a8b8
    error ResourceNotHere(); // 0xa76046ac
    error NotAnInn(); // 0x13e9e663
    error NotGameContract(); // 0xd5fe8702
    error MintingTooExpensive(); // 0x01e49b9b
    error CannotTransferCharacters(); // 0x48d2e23c
    error DoesNotOwnCharacter(); // 0x1c2d9d38

    event SkillLevelUp(Skill skill, uint8 indexed level);
    event AttributeLevelUp(Attribute attribute, uint8 indexed level);
    
    //event CombatLevelUp(Stat stat, uint8 indexed level);
    //enum Monsters {NOTHING, FROG, RABBIT, BEAR, SPIDER, WOLF, THIEF, MERCENARY, THUG, SKELETON, ZOMBIE, VAMPIRE, GREEN_DRAGON}
    //enum Bosses {NOTHING, GULAK, JASTIK, ULTAIR, MEBHIM, GHIVILIN}
}