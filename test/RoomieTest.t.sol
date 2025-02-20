// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Roomie} from "../src/Roomie.sol";
import {RoomieScript} from "../script/RoomieScript.s.sol";
import {console} from "../lib/forge-std/src/console.sol";

contract RoomieTest is Test {
    //
    Roomie private roomie;

    address private constant BOB = address(1);
    address private constant ALICE = address(2);
    address private constant CHARLIE = address(3);

    bytes32 private constant LODGE_ID = bytes32(abi.encodePacked("81291238c"));
    bytes32 private constant ORDER_ID = bytes32(abi.encodePacked("78asasd67"));
    bytes32 private constant CASE_ID = bytes32(abi.encodePacked("sadjasa99"));

    string private constant TOKEN_URI = "bksandua7ad";
    uint256 private constant TOKEN_ID = 100;
    uint256 private constant OTHER_TOKEN_ID = 101;
    uint256 private constant TOKEN_TO_MINTED = 10;
    uint256 private constant TOKEN_PRICE = 1 ether;

    uint256 private constant STAY_DAYS_A = 2;
    uint256 private constant STAY_DAYS_B = 1;

    uint256 private constant BOB_STAKING_AMOUNT = TOKEN_TO_MINTED * TOKEN_PRICE;
    uint256 private constant ALICE_STAKING_AMOUNT = STAY_DAYS_A * TOKEN_PRICE;

    function setUp() public {
        RoomieScript roomieScript = new RoomieScript();
        roomie = roomieScript.run();
    }

    function testSuccessfullyRegisteredLodge() public {
        vm.startPrank(BOB);
        roomie.registerLodge(LODGE_ID);
        vm.stopPrank();
    }

    function testRevertIfLodgeAlreadyRegistered() public {
        testSuccessfullyRegisteredLodge();

        vm.startPrank(BOB);
        vm.expectRevert(Roomie.LodgeAlreadyRegistered.selector);
        roomie.registerLodge(LODGE_ID);
        vm.stopPrank();
    }

    function testSuccessfullyRegisterToken() public {
        testSuccessfullyRegisteredLodge();

        vm.startPrank(BOB);
        roomie.registerToken(LODGE_ID, TOKEN_URI, TOKEN_ID, TOKEN_PRICE);
        vm.stopPrank();

        bytes32 actualLodgeToken = roomie.tokenDetail(TOKEN_ID).lodgeId;
        uint256 actualTokenPrice = roomie.tokenDetail(TOKEN_ID).price;

        assert(LODGE_ID == actualLodgeToken);
        assertEq(TOKEN_PRICE, actualTokenPrice);
    }

    function testRevertIfInvalidHostAuthorization() public {
        testSuccessfullyRegisterToken();

        vm.startPrank(ALICE);
        vm.expectRevert(Roomie.InvalidAuthorization.selector);
        roomie.registerToken(LODGE_ID, TOKEN_URI, TOKEN_ID, TOKEN_PRICE);
        vm.stopPrank();
    }

    function testRevertIfTokenAlreadyExistence() public {
        testSuccessfullyRegisterToken();

        vm.startPrank(BOB);
        vm.expectRevert(Roomie.TokenAlreadyExistence.selector);
        roomie.registerToken(LODGE_ID, TOKEN_URI, TOKEN_ID, TOKEN_PRICE);
        vm.stopPrank();
    }

    function testSuccesfullyMintToken() public {
        testSuccessfullyRegisterToken();

        hoax(BOB, BOB_STAKING_AMOUNT);
        roomie.mint{value: BOB_STAKING_AMOUNT}(LODGE_ID, TOKEN_ID, TOKEN_TO_MINTED, bytes(""));

        uint256 actualTokenBalance = roomie.balanceOf(address(roomie), TOKEN_ID);
        uint256 actualSupply = roomie.tokenDetail(TOKEN_ID).supply;
        uint256 actualEthBalance = address(roomie).balance;

        assertEq(TOKEN_TO_MINTED, actualTokenBalance);
        assertEq(BOB_STAKING_AMOUNT, actualEthBalance);
        assertEq(TOKEN_TO_MINTED, actualSupply);
    }

    function testRevertIfInvalidTokenOwnership() public {
        testSuccessfullyRegisterToken();

        hoax(BOB, BOB_STAKING_AMOUNT);
        vm.expectRevert(Roomie.InvalidTokenOwnership.selector);
        roomie.mint{value: BOB_STAKING_AMOUNT}(LODGE_ID, OTHER_TOKEN_ID, TOKEN_TO_MINTED, bytes(""));
    }

    function testRevertIfInvalidStakingAmount() public {
        testSuccessfullyRegisterToken();

        hoax(BOB, BOB_STAKING_AMOUNT);
        vm.expectRevert(Roomie.InvalidStakingAmount.selector);
        roomie.mint{value: BOB_STAKING_AMOUNT - 0.0000001 ether}(LODGE_ID, TOKEN_ID, TOKEN_TO_MINTED, bytes(""));
    }

    function testSuccessfullyReserve() public {
        testSuccesfullyMintToken();

        uint256 checkInTimestamp = block.timestamp;

        hoax(ALICE, ALICE_STAKING_AMOUNT);
        roomie.reserve{value: ALICE_STAKING_AMOUNT}(LODGE_ID, ORDER_ID, TOKEN_ID, STAY_DAYS_A, checkInTimestamp);

        address actualCustomer = roomie.orderDetail(ORDER_ID).customer;
        bytes32 lodgeId = roomie.orderDetail(ORDER_ID).lodgeId;
        uint256 tokenId = roomie.orderDetail(ORDER_ID).tokenId;
        uint256 actualCheckInTimestamp = roomie.orderDetail(ORDER_ID).checkIn;
        uint256 actualCheckOutTimestamp = roomie.orderDetail(ORDER_ID).checkOut;
        uint256 actualStayDuration = roomie.orderDetail(ORDER_ID).duration;

        assert(ALICE == actualCustomer);
        assertEq(LODGE_ID, lodgeId);
        assertEq(TOKEN_ID, tokenId);
        assertEq(checkInTimestamp, actualCheckInTimestamp);
        assertEq(actualCheckOutTimestamp, 0);
        assertEq(STAY_DAYS_A, actualStayDuration);
    }

    function testSuccessfullyCheckIn() public {
        testSuccessfullyReserve();

        vm.startPrank(ALICE);
        roomie.checkIn(ORDER_ID);
        vm.stopPrank();

        bool actualCustomerAlreadyCheckIn = roomie.orderDetail(ORDER_ID).alreadyCheckIn;

        assert(true == actualCustomerAlreadyCheckIn);
    }

    function testRevertIfInvalidUserAuthorization() public {
        testSuccessfullyReserve();

        vm.startPrank(BOB);
        vm.expectRevert(Roomie.InvalidAuthorization.selector);
        roomie.checkIn(ORDER_ID);
        vm.stopPrank();
    }

    function testSuccessfullyCheckOut() public {
        testSuccessfullyCheckIn();

        vm.startPrank(ALICE);
        vm.warp(block.timestamp + 2 days);
        roomie.checkOut(ORDER_ID, TOKEN_ID);
        vm.stopPrank();

        uint256 actualBurnSupply = roomie.tokenDetail(TOKEN_ID).burn;

        assertEq(STAY_DAYS_A, actualBurnSupply);
    }

    function testSuccessfullyWithdrawFromCustomerCheckOut() public {
        testSuccessfullyCheckOut();

        uint256 expectedSmartContractBalanceBefore = (TOKEN_PRICE * TOKEN_TO_MINTED) + (TOKEN_PRICE * 2);
        uint256 actualSmartContractBalanceBefore = address(roomie).balance;

        vm.startPrank(BOB);
        vm.warp(block.timestamp + 2 days);
        roomie.withdrawFromCustomerCheckOut(LODGE_ID, ORDER_ID, TOKEN_ID);
        vm.stopPrank();

        uint256 expectedBobBalance = TOKEN_PRICE * 4;
        uint256 actualBobBalance = address(BOB).balance;

        uint256 expectedSmartContractBalanceAfter = (TOKEN_PRICE * TOKEN_TO_MINTED) + 2 ether - expectedBobBalance;
        uint256 actualSmartContractBalanceAfter = address(roomie).balance;

        assertEq(expectedSmartContractBalanceBefore, actualSmartContractBalanceBefore);
        assertEq(expectedSmartContractBalanceAfter, actualSmartContractBalanceAfter);
        assertEq(expectedBobBalance, actualBobBalance);
    }

    function testSuccessfullyOpenCase() public {
        testSuccessfullyCheckIn();

        vm.startPrank(ALICE);
        roomie.openCase(CASE_ID, ORDER_ID, LODGE_ID);
        vm.stopPrank();

        bytes32 problematicOrder = roomie.caseDetail(CASE_ID).orderId;
        uint256 caseOrderCreated = roomie.caseDetail(CASE_ID).createdTimestamp;

        assert(problematicOrder == ORDER_ID);
        assert(block.timestamp == caseOrderCreated);
    }

    function testSuccessfullyVoteOnCase() public {
        testSuccessfullyOpenCase();

        vm.startPrank(CHARLIE);
        roomie.voteOnCase(CASE_ID, 0);
        vm.stopPrank();

        uint256 hostVote = roomie.caseDetail(CASE_ID).hostVote;
        uint256 customerVote = roomie.caseDetail(CASE_ID).customerVote;

        assert(hostVote == 1);
        assert(customerVote == 0);
    }

    function testSuccessfullyWithdrawForCaseWinner() public {
        testSuccessfullyVoteOnCase();

        vm.startPrank(BOB);
        vm.warp(block.timestamp + 7 days);
        roomie.withdrawForCaseWinner(CASE_ID, ORDER_ID, TOKEN_ID);
        vm.stopPrank();

        uint256 expectedBobBalance = TOKEN_PRICE * 4;
        uint256 actualBobBalance = address(BOB).balance;

        assertEq(expectedBobBalance, actualBobBalance);
    }

    // function testRevertIfInvalidTimeWhileCheckOut() public {
    //     testSuccessfullyCheckIn();

    //     vm.startPrank(BOB);
    //     vm.warp(block.timestamp + 1 days);
    //     vm.expectRevert(Roomie.InvalidTime.selector);
    //     roomie.checkOut(LODGE_ID, ORDER_ID, TOKEN_ID);
    //     vm.stopPrank();
    // }

    function testSuccessfullyGetURI() public {
        testSuccessfullyRegisterToken();

        string memory actualURI = roomie.uri(TOKEN_ID);
        string memory expectedURI = string(abi.encodePacked("https://gateway.pinata.cloud/ipfs/", TOKEN_URI));

        assert(keccak256(abi.encodePacked(actualURI)) == keccak256(abi.encodePacked(expectedURI)));
    }

    //
}
