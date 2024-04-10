// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library Calculate {

    function distance(int256 x1, int256 y1, int256 x2, int256 y2) internal pure returns (uint64) {
        // 1 unit of distance = 1 second of travel time
        int256 xDistance = x1 - x2;
        int256 yDistance = y1 - y2;
        uint256 xDistanceSquared = uint256(xDistance * xDistance); // always positive anyway
        uint256 yDistanceSquared = uint256(yDistance * yDistance); // always positive anyway
        uint256 hypotenuseSquared = xDistanceSquared + yDistanceSquared;
        uint64 travelDistance = uint64(Math.sqrt(hypotenuseSquared, Math.Rounding.Ceil)); // safe downcast
        return travelDistance;
    }

    function resourceGatheringSpeed(uint16 toolGatherSpeed, uint16 resourceGatherSpeed, uint8 skillLevel) internal pure returns (uint16) {
        uint16 timeToGather = uint16(toolGatherSpeed + resourceGatherSpeed + skillLevel); // safe downcast
        return timeToGather;
    }

    function combatLevel(uint8 vitalityLevel, uint8 strengthLevel, uint8 agilityLevel, uint8 intelligenceLevel) internal pure returns (int8) {
        int8 _combatLevel = int8((vitalityLevel + strengthLevel + agilityLevel + intelligenceLevel) / 4);
        return _combatLevel;
    }

    function damagePerHit(int16 power, int16 targetProtection) internal pure returns (int16) {
        int16 damage = power - targetProtection;
        if (damage < 0) damage = 0;
        return damage;
    }

}