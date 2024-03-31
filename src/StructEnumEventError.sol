// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; 

abstract contract StructEnumEventError {

    struct Stats {
        uint8 combatLevel; // [1-100]
        uint16 maxHP; // [10, 1337] as the max. Based on vitality.
        int16 currentHP; // Might be easier to make this an int, so if it's negative or 0, you die.
        uint16 attackPower; // use power+speed to calculate dps, or power to calculate max hit.
        int16 attackSpeed; // lower = faster
        int16 dodgeChance; // higher = better [0, 10000] 100%
        uint16 critChance; // higher = better [0, 10000] 100%
        uint16 critPower; // 150 to 400 (1.1x to 4x)
        uint16 magicPower; // for spells
        uint16 protection; // gained from armor
        int16 accuracy; // for magic, bows, and melee
        int8 attackRange; // maximum attack distance
    }

    struct Coordinates {
        int256 x; // can maybe make these smaller in future
        int256 y; // can maybe make these smaller in future
    }

    struct ProficiencyInfo {
        uint8 level;
        uint32 xp;
    }

    struct GearInfo {
        GearSlot slot;
        uint8 requiredStrengthLevel;
        uint8 requiredAgilityLevel;
        uint8 requiredIntelligenceLevel;
        uint16 attackPower; // use power+speed to calculate dps, or power to calculate max hit.
        int16 attackSpeed; // lower = faster
        int16 dodgeChance; // higher = better [0, 10000] 100%
        uint16 critChance; // higher = better [0, 10000] 100%
        uint16 critPower; // 150 to 400 (1.1x to 4x)
        uint16 magicPower; // for spells
        uint16 protection; // gained from armor
        int16 accuracy; // for magic, bows, and melee
        int8 attackRange; // maximum attack distance
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

    struct PriceInfo {
        uint256 buyPrice;
        uint256 sellPrice;
    }

    enum GearSlot {NULL, MAIN_HAND, OFF_HAND, HEAD, CHEST, LEGS, GLOVES, BOOTS, CLOAK, RING_ONE, RING_TWO, AMULET}
    enum Skill {MINING, BLACKSMITHING, WOODCUTTING, WOODWORKING, FISHING, COOKING, LEATHERWORKING, CLOTHWORKING, ALCHEMY, ENCHANTING}
    enum Attribute {VITALITY, STRENGTH, AGILITY, INTELLIGENCE}

    enum Resource {
        NORMAL_TREE, OAK_TREE, WILLOW_TREE, MAPLE_TREE, YEW_TREE, MAGIC_TREE,
        IRON_VEIN, COAL_VEIN, MITHRIL_VEIN, ADAMANT_VEIN, RUNITE_VEIN,
        RAW_SHRIMP, RAW_TROUT, RAW_TUNA, RAW_LOBSTER, RAW_SWORDFISH, RAW_SHARK
    }

    // The tokenized items in the game representing the ERC1155 Token id. They must match the token_metadata `{ID}.json` files.
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
        COAL_ORE // 19 (not implemented URI yet)
    }

    enum Location {
        LUMBRIDGE_TOWN_SQ, // 0
        L_FURNACE, // 1
        L_ANVIL, // 2
        L_SPINNING_WHEEL, // 3
        L_GENERAL_STORE, // 4
        L_HERBALIST, // 5
        L_TANNING_RACK, // 6
        L_MELEE_SHOP, // 7
        L_RANGE_SHOP, // 8
        L_MAGE_SHOP, // 9
        L_INN, // 10
        FALADOR_TOWN_SQ, // 11
        F_FURNACE, // 12
        F_ANVIL, // 13
        F_SPINNING_WHEEL, // 14
        F_GENERAL_STORE, // 15
        F_HERBALIST, // 16
        F_TANNING_RACK, // 17
        F_MELEE_SHOP, // 18
        F_RANGE_SHOP, // 19
        F_MAGE_SHOP, // 20
        F_INN, // 21
        VELRICK_TOWN_SQ, // 22
        V_FURNACE, // 23
        V_ANVIL, // 24
        V_SPINNING_WHEEL, // 25 
        V_GENERAL_STORE, // 26
        V_HERBALIST, // 27
        V_TANNING_RACK, // 28
        V_MELEE_SHOP, // 29
        V_RANGE_SHOP, // 30
        V_MAGE_SHOP, // 31
        V_INN, // 32
        FOREST_ONE, // 33
        FOREST_TWO, // 34
        FOREST_THREE, // 35
        FOREST_FOUR, // 36 
        FOREST_FIVE, // 37
        CAVE_ONE, // 38
        CAVE_TWO, // 39
        CAVE_THREE, // 40
        CAVE_FOUR, // 41
        CAVE_FIVE, // 42
        MINE_ONE, // 43
        MINE_TWO, // 44
        MINE_THREE, // 45
        MINE_FOUR, // 46
        MINE_FIVE, // 47
        SPECIAL_LOCATION_ONE, // 48
        SPECIAL_LOCATION_TWO, // 49
        SPECIAL_LOCATION_THREE, // 50
        SPECIAL_LOCATION_FOUR, // 51
        SPECIAL_LOCATION_FIVE // 52
    }

    error NotACharacter(); // 0x72cd097c
    error InvalidAmount(); // 0x2c5211c6
    error FailedCall(); // 0xd6bda275
    error AlreadyThere(); // 0x73c950e6
    error StillDoingAction(); // 0x5e99f373
    error NotTeleportLocation(); // 0x5e6e5ab4
    error NotInStock(); // 0xb4c4332c
    error NotAtLocation(); // 0x039906b7
    error NotEnoughGold(); // 0x3a2298cd
    error NotShopLocation(); // 0x725cae1b
    error DoNotOwnItem(); // 0x62b51396
    error InvalidTool(); //
    error WrongToolForTheJob(); // 0xeea110e5
    error Noob(); // 0x53bc8411
    error NotGear(); // 0xf0a68a55
    error CannotUnequipNothing(); // 0x92746c1a
    error ItemNotEquipped(); // 0x54962c76
    error AlreadyEquipped(); // 0x2e53a303
    error NotGameContract(); // 0xd5fe8702
    error MintingTooExpensive(); // 0x01e49b9b
    error CannotTransferCharacters(); // 0x48d2e23c
    error DoesNotOwnCharacter(); // 0x1c2d9d38

    event SkillLevelUp(Skill skill, uint8 indexed level);

    /*
    struct ItemInfo {
        // Will need this for potions and stuff
    }
    */

    //enum Monsters {NOTHING, FROG, RABBIT, BEAR, SPIDER, WOLF, THIEF, MERCENARY, THUG, SKELETON, ZOMBIE, VAMPIRE, GREEN_DRAGON}
    //enum Bosses {NOTHING, GULAK, JASTIK, ULTAIR, MEBHIM, GHIVILIN}
}