// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
//import {console2} from "forge-std/console2.sol";
import {Raffle} from "../src/Raffle.sol";
import {ERC20Mock} from "@openzeppelin/mocks/ERC20Mock.sol";
import {ERC721Mock} from "@openzeppelin/mocks/ERC721Mock.sol";
import {ERC1155Mock} from "@openzeppelin/mocks/ERC1155Mock.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {MockLinkToken} from "@chainlink/contracts/src/v0.8/mocks/MockLinkToken.sol";
import {TokenTransferor} from "../src/TokenTransferor.sol";

contract RaffleTest is Test {
    Raffle public raffleContract;
    ERC20Mock public mock20;
    ERC721Mock public mock721;
    ERC1155Mock public mock1155;
    VRFCoordinatorV2Mock public mockVRF;
    MockLinkToken public mockLink;
    //address public employeerAddress;
    TokenTransferor public ccip;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");

    /// Structs/enums from Raffle ///
    enum RaffleType {
        ERC1155,
        ERC721,
        ERC20
    }

    enum Status {
        CREATED, // create raffle has been called
        STARTED, // prize of raffle has been "staked" in contract
        DRAWING, // upkeep is true, VRF is called
        ENDED // winner was picked and prize was sent to winner
    }

    // enum Status {
    //     PENDING,
    //     DRAWING,
    //     ENDING
    // }

 
    // mumbai vrf info 
    // 6612
    // 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f gaslane
    // 500000
    // 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed vrf


function setUp() public {
    // crete tokens
    mock20 = new ERC20Mock("ERC20Token", "COIN", address(this), type(uint256).max);
    mock721 = new ERC721Mock("Name", "NFT");
    mock1155 = new ERC1155Mock("URI");
    mockLink = new MockLinkToken();


    // create vrf instance and subId
    mockVRF = new VRFCoordinatorV2Mock(10, 1);
    uint64 subId = mockVRF.createSubscription();

    // create raffle instance
    raffleContract = new Raffle(subId, bytes32(0), 500000, address(mockVRF));    

    // add raffle as consumer and fund for vrf
    mockVRF.addConsumer(subId, address(raffleContract));
    mockVRF.fundSubscription(subId, 1000000000000000000);

    vm.deal(user1, 1 ether);
    vm.deal(user2, 1 ether);
    vm.deal(user3, 1 ether);

}

//////////////////////////////////////////
/// Helper functions to create reffles ///
//////////////////////////////////////////
function createERC20RaffleType(/*RaffleType, uint256, address, uint256, uint256, uint256*/) public returns (bytes32 raffleId) {
    return raffleId = raffleContract.createRaffle(Raffle.RaffleType.ERC20, (block.timestamp + 1 hours ), address(mock20), 0, 20, 0);
}

function createERC20RaffleTypeWithFee(/*RaffleType, uint256, address, uint256, uint256, uint256*/) public returns (bytes32 raffleId) {
    return raffleId = raffleContract.createRaffle(Raffle.RaffleType.ERC20, (block.timestamp + 1 hours ), address(mock20), 0, 20, 1000000000000000000);
}

function createERC20RaffleStaked(/*RaffleType, uint256, address, uint256, uint256, uint256*/) public returns (bytes32 raffleId) {
    raffleId = raffleContract.createRaffle(Raffle.RaffleType.ERC20, (block.timestamp + 1 hours ), address(mock20), 0, 20, 0);
    mock20.approve(address(raffleContract), 20);
    raffleContract.stakePrize(raffleId);
    return raffleId;
}

function createERC20RaffleTypeWithFeeStaked(/*RaffleType, uint256, address, uint256, uint256, uint256*/) public returns (bytes32 raffleId) {
    raffleId = raffleContract.createRaffle(Raffle.RaffleType.ERC20, (block.timestamp + 1 hours ), address(mock20), 0, 20, 1000000000000000000);
    mock20.approve(address(raffleContract), 20);
    raffleContract.stakePrize(raffleId);
    return raffleId;
}

function createERC721RaffleType(/*RaffleType, uint256, address, uint256, uint256, uint256*/) public returns (bytes32 raffleId) {
    return raffleContract.createRaffle(Raffle.RaffleType.ERC721, (block.timestamp + 1 hours ), address(mock721), 1, 1, 0);
}

function createERC1155RaffleType(/*RaffleType, uint256, address, uint256, uint256, uint256*/) public returns (bytes32 raffleId) {
    return raffleContract.createRaffle(Raffle.RaffleType.ERC1155, (block.timestamp + 1 hours ), address(mock1155), 1, 1, 0);
}

function createERC1155MultipleRaffleType(/*RaffleType, uint256, address, uint256, uint256, uint256*/) public returns (bytes32 raffleId) {
    return raffleContract.createRaffle(Raffle.RaffleType.ERC1155, (block.timestamp + 1 hours ), address(mock1155), 1, 22, 0);
}

//////////////////////////
/// Test Create Raffle ///
//////////////////////////

function test_CreateRaffle() public {
    bytes32 raffleId = raffleContract.createRaffle(Raffle.RaffleType.ERC20, (block.timestamp + 1 hours ), address(mock20), 0, 20, 0);

    Raffle.RaffleInfo memory raffleInfo = raffleContract.getRaffleInfo(raffleId);


    assertEq(raffleInfo.id, keccak256(abi.encodePacked(block.timestamp, address(this))));
    assertEq(raffleInfo.randomNumber, 0);
    assertEq(raffleInfo.randomNumberAvailable, false);
    assertEq(raffleInfo.winner, address(0));
    assertEq(raffleInfo.prize, address(mock20));
    assertEq(raffleInfo.prizeId, 0);
    assertEq(raffleInfo.prizeAmount, 20);
    assertEq(raffleInfo.entryFee, 0);
   // assertEq(raffleInfo.status, Status.CREATED);
}

////////////////////////////////
/// Transfer To Raffle Tests ///
////////////////////////////////
function test_stakePrizeToRaffleWithERC20() public {
    address raffleCreator = makeAddr("raffleCreator");
    deal(address(mock20), raffleCreator, 21);
    
    vm.startPrank(raffleCreator);
    bytes32 raffleId = createERC20RaffleType();
    mock20.approve(address(raffleContract), 20);

    raffleContract.stakePrize(raffleId);

    assertEq(mock20.balanceOf(address(raffleContract)), 20);
    assertEq(mock20.balanceOf(raffleCreator), 1);

}

function test_stakePrizeToRaffleWithERC721() public {
    address raffleCreator = makeAddr("raffleCreator");
    mock721.mint(raffleCreator, 1);
    
    vm.startPrank(raffleCreator);
    bytes32 raffleId = createERC721RaffleType();
    mock721.setApprovalForAll(address(raffleContract), true);

    raffleContract.stakePrize(raffleId);

    assertEq(mock721.balanceOf(address(raffleContract)), 1);
    assertEq(mock721.balanceOf(raffleCreator), 0);
}

function test_stakePrizeToRaffleWithERC1155() public {
    address raffleCreator = makeAddr("raffleCreator");
    mock1155.mint(raffleCreator, 1, 1, "");
    
    vm.startPrank(raffleCreator);
    bytes32 raffleId = createERC1155RaffleType();
    mock1155.setApprovalForAll(address(raffleContract), true);

    raffleContract.stakePrize(raffleId);

    assertEq(mock1155.balanceOf(address(raffleContract), 1), 1);
    assertEq(mock1155.balanceOf(address(raffleCreator), 1), 0);
}

function test_stakePrizeToRaffleWithERC1155Batch() public {
    address raffleCreator = makeAddr("raffleCreator");
    mock1155.mint(raffleCreator, 1, 22, "");
    assertEq(mock1155.balanceOf(raffleCreator, 1), 22);

    vm.startPrank(raffleCreator);
    bytes32 raffleId = createERC1155MultipleRaffleType();
    mock1155.setApprovalForAll(address(raffleContract), true);

    raffleContract.stakePrize(raffleId);

    assertEq(mock1155.balanceOf(address(raffleContract), 1), 22);
    assertEq(mock1155.balanceOf(address(raffleCreator), 1), 0);

}

///////////////////////////////
/// Test Enter Raffle Funcs ///
///////////////////////////////

function test_enterRaffleERC20() public {
    bytes32 raffleId = createERC20RaffleStaked();

    vm.prank(user1);
    raffleContract.enterRaffle(raffleId);

    address[] memory entrantArray = raffleContract.getRaffleEntrantsArray(raffleId);

    assertEq(entrantArray[0], user1);

}

function test_enterRaffleERC20WithFee() public {
    bytes32 raffleId = createERC20RaffleTypeWithFeeStaked();

    vm.prank(user1);
    raffleContract.enterRaffle{value: 1 ether}(raffleId);

    address[] memory entrantArray = raffleContract.getRaffleEntrantsArray(raffleId);

    assertEq(entrantArray[0], user1);
}

////////////////////////
/// Test End Raffles ///
////////////////////////
// //@todo need to mock automation and vrf to test properly
// function test_endRaffle() public {
//     bytes32 raffleId = createERC20RaffleStaked();

//     uint256[] memory randomWords = new uint256[](1);


//     mockVRF.fulfillRandomWordsWithOverride(requestId, address(raffleContract), randomWords);

// }

////////////////////////////////
/// Test OnlyOwner Functions ///
////////////////////////////////
function test_fuzzOnlyOwnerCanChangeGasLimit(address caller) public {
    vm.assume(caller != address(0) && caller != raffleContract.owner());

    assertEq(raffleContract.getCurrentGasLimit(), 500000);

    vm.prank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    raffleContract.changeGasLimit(100000);

}

function test_onlyOwnerCanChangeGasLimit() public {
    assertEq(raffleContract.getCurrentGasLimit(), 500000);

    raffleContract.changeGasLimit(100000);

    assertEq(raffleContract.getCurrentGasLimit(), 100000);
}

function test_fuzzOnlyOnwerCanWithdrawEthFees(address caller) public {
    vm.assume (caller != address(0) && caller != raffleContract.owner());

    vm.prank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    raffleContract.withdrawEthFees(caller);
}

function test_fuzzOnlyOnwerCanWithdrawErc721(address caller) public {
    vm.assume (caller != address(0) && caller != raffleContract.owner());

    vm.prank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    raffleContract.withdrawERC721(caller, address(mock721), 1);
}

function test_fuzzOnlyOwnerCanWithdrawErc20Fees(address caller) public {
    vm.assume (caller != address(0) && caller != raffleContract.owner());

    vm.prank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    raffleContract.withdrawERC20TokenFees(caller, address(mock20));
}

function test_fuzzOnlyOnwerCanWithdrawErc1155(address caller) public {
    vm.assume (caller != address(0) && caller != raffleContract.owner());

    vm.prank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    raffleContract.withdrawERC1155(caller, address(mock1155), 1, 1);
}

function test_fuzzOnlyOwnerCanAddUserToRaffle(address caller) public {
    vm.assume (caller != address(0) && caller != raffleContract.owner());

    bytes32 raffleId = createERC20RaffleType();

    vm.prank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    raffleContract.addToRaffle(user1, raffleId);
}

function test_fuzzOwnerAddsUserToRaffle(address _usr) public {
    vm.assume(_usr != address(0));
    bytes32 raffleId = raffleContract.createRaffle(Raffle.RaffleType.ERC20, (block.timestamp + 1 hours ), address(mock20), 0, 20, 0);

    mock20.approve(address(raffleContract), 20);
    raffleContract.stakePrize(raffleId);

    console2.logBytes32(raffleId);

    raffleContract.addToRaffle(_usr, raffleId);

    address[] memory entrantArray = raffleContract.getRaffleEntrantsArray(raffleId);

    assertEq(entrantArray[0], _usr);
}

}