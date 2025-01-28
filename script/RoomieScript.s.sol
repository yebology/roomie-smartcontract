// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Script} from "../lib/forge-std/src/Script.sol";
import {Roomie} from "../src/Roomie.sol";

contract RoomieScript is Script {
    //
    function run() external returns (Roomie) {
        vm.startBroadcast();
        Roomie roomie = new Roomie();
        vm.stopBroadcast();

        return roomie;
    }
    //
}
