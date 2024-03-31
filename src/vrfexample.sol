// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VRFCoordinatorV2Interface} from "@chainlink/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
/*
contract vrfexample is VRFConsumerBaseV2 {

    VRFCoordinatorV2Interface COORDINATOR; // VRF interface
    bytes32 public keyHash; // VRF gas lane option
    uint64 public subscriptionId; // VRF subscription ID
    uint32 public callbackGasLimit; // VRF gas limit for `fulfillRandomWords()` callback execution.
    uint16 public requestConfirmations; // VRF number of block confirmations to prevent re-orgs.

    constructor(
        address owner, 
        uint256 initialSupply,
        uint64 _subscriptionId, 
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        address _vrfCoordinator, 
    ) 
        ERC20("Free Play Example", "fpEXAMPLE")
        VRFConsumerBaseV2(_vrfCoordinator)
        Ownable(owner)
    {
        //setSubscriptionId(_subscriptionId);
        //setKeyHash(_keyHash);
        //setCallbackGasLimit(_callbackGasLimit);
        //setRequestConfirmations(_requestConfirmations);
        //COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        //_mint(owner, initialSupply); // Note: DO NOT mint any tokens upon deployment if making a Wrapper FP token. 
    }

}
*/