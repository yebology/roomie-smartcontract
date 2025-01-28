// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Roomie} from "../src/Roomie.sol";
import {RoomieScript} from "../script/RoomieScript.s.sol";

contract RoomieTest is Test {
    //
    Roomie private roomie;

    function setUp() public {
        RoomieScript roomieScript = new RoomieScript();
        roomie = roomieScript.run();
    }

    function testSuccessfullyMintToken() public {}
    //
}
