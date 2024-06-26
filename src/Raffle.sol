//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ITokenTransferor} from "./interfaces/ITokenTransferor.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {IERC1155} from "@openzeppelin/token/ERC1155/IERC1155.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/security/ReentrancyGuard.sol";

// current raffle contract live on testnet VRF & Automation working 0xEb1458F95C07aa91ABfc7A1Baf03080ff44FA350

contract Raffle is Ownable, ReentrancyGuard, AutomationCompatibleInterface, VRFConsumerBaseV2 {
    
    //////////////
    /// ERRORS ///
    //////////////

    error Raffle__InvalidRaffle(bytes32 _raffleId);
    error Raffle__AlreadyEntered(address _usr);
    error Raffle__RaffleClosed();
    error Raffle__RaffleStillOpen();
    error Raffle__RandomNumberNotAvailable(bytes32 _raffleId);
    error Raffle__InvalidRaffleState(Status _status);
    error Raffle__InvalidEndTime();
    error Raffle__InvalidGasLimit();

    //////////////
    /// EVENTS ///
    //////////////

    event RequestSent(uint256 requestId);
    event AddedToRaffle(address usr, bytes32 raffleId);
    event RaffleCreated(bytes32 raffleId, uint256 endTime);
    event RaffleStarted(bytes32 raffleId);
    event RaffleEnded(bytes32 raffleId, address winner);

    
    event RequestFulfilled(
        uint256 requestId,
        uint256[] randomWords,
        bytes32 raffleId
    );

    ////////////////////
    // State Variable //
    ////////////////////

    /// requestId --> requestStatus 
    mapping(uint256 => RequestStatus) public s_requests; 

    /// mapping of vrf requestId to vrfInfo struct
    mapping(uint256 => vrfInfo) public chainlinkRaffleInfo;

    /// raffleId --> raffleInfo
    mapping(bytes32 => RaffleInfo) public raffle;

    /// raffleId --> entrants
    mapping(bytes32 => address[]) public raffleEntrants;

    /// mapping of raffleId to address to index in entrants array of that raffles entrants[]
    mapping (bytes32 => mapping(address => uint256)) public raffleEntryIndex;

    /// mapping of raffle creator to their raffleIds
    mapping (bytes32 => address) public raffleCreator;

    // array of address that have entered a raffle
    address[] public entrantsArray;
    bytes32[] public raffleIds;

    struct RaffleInfo {
        Status status;
        RaffleType raffleType;
        bytes32 id; // uniqueId for each raffle @todo test is using a uint would be cheaper / better / is it safer?
        uint256 endTime; // ending timestamp 
        uint256 randomNumber; // random number from VRF to pick winner from array
        address prize; // address of the raffle prize
        uint256 prizeId; // Id of raffle prize if necessary
        uint256 prizeAmount; // amount of prize if necessary
        uint256 entryFee; // fee to enter raffle if necessary
        bool randomNumberAvailable; // has the contract recieved a number from Chainlink
        address winner; // winner of the raffle
    }

    struct RequestStatus {
        bool fulfilled; // whether the request has been successfully fulfilled
        bool exists; // whether a requestId exists
        uint256[] randomWords;
    }

    struct vrfInfo {
        bytes32 id; // raffle id
        uint256 size; // size of entry array
    }

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

    /////////////////////
    /// VRF Variables ///
    /////////////////////

    uint256 public lastRequestId;

    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;

    // Your VRF V2 coordinator subscription ID.
    uint64 private immutable i_subscriptionId;

    bytes32 private immutable i_gasLane;
    uint32 private gasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 5;
    uint8 private constant NUM_WORDS = 1;

    /////////////////////////
    /// Automation Struct ///
    /////////////////////////

    /////////////////
    /// Modifiers /// 
    /////////////////

    constructor(uint64 subscriptionId, bytes32 gasLane, uint32 callbackGasLimit, address vrfCoordinatorV2)
            //address payable destinationWallet
            VRFConsumerBaseV2(vrfCoordinatorV2) {
                i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
                i_subscriptionId = subscriptionId;
                i_gasLane = gasLane;
                gasLimit = callbackGasLimit;
            }
    
    receive() external payable {}

    ////////////////////////////////
    /// Withdraw Funcs For Owner ///
    ////////////////////////////////

    function withdrawEthFees(address _to) external onlyOwner {
        uint256 amount = address(this).balance;
        (bool sent, ) = _to.call{value: amount}("");
        require(sent, "Failed to send Ether");
    }

    function withdrawERC20TokenFees(address _to, address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        (bool sent) = IERC20(_token).transfer(_to, amount);
        require(sent, "Failed ERC20 Token Transfer");
    }

    function withdrawERC721(address _to, address _token, uint256 _tokenId) external onlyOwner {
        IERC721(_token).safeTransferFrom(address(this), _to, _tokenId);
    }

    function withdrawERC1155(address _to, address _token, uint256 _tokenId, uint256 _amount) external onlyOwner {
        IERC1155(_token).safeTransferFrom(address(this), _to, _tokenId, _amount, "");
    }

    //////////////////////////
    ///// VRFv2 functions ////
    //////////////////////////

    // this function is called be performUpkeep once a raffle has met the conditions for ending.
    // It will request a random number from the VRF and save the raffleId and the number of entries in the raffle in a map.
    // If a request is successful, the callback function, fulfillRandomWords will be called.
    // @param _id is the raffleID
    // @param _entriesSize is the number of entries in the raffle
    // @return requestId is the requestId generated by chainlink
    function _requestRandomWords(
            bytes32 _raffleId
            // need to calc uint256 _entriesSize
        ) internal returns (uint256 requestId) {
            // Will revert if subscription is not set and funded.
            requestId = i_vrfCoordinator.requestRandomWords(
                i_gasLane,
                i_subscriptionId,
                REQUEST_CONFIRMATIONS,
                gasLimit,
                NUM_WORDS
            );
            s_requests[requestId] = RequestStatus({
                randomWords: new uint256[](0),
                exists: true,
                fulfilled: false
            });

            lastRequestId = requestId;

            uint256 numOfEntries = raffleEntrants[_raffleId].length - 1;

            // result is the requestId generated by chainlink. It is saved in a map linked to the param id
            chainlinkRaffleInfo[requestId] = vrfInfo({
                id: _raffleId,
                size: numOfEntries
            });
            emit RequestSent(requestId);
            return requestId;
    }

    // This is the callback function called by the VRF when the random number is ready.
    // It will emit an event with the original raffleId and the random number.
    /// @param _requestId is the requestId generated by chainlink
    /// @param _randomWords is the random number generated by the VRF
    function fulfillRandomWords(
        uint256 _requestId, 
        uint256[] memory _randomWords
    ) internal override {
        require(s_requests[_requestId].exists, "request not found");
        
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
            
           
            // grabs RaffleInfo struct from raffle mapping.
            // uses chainlinkRaffleInfo[_requestId].id as the index which is a bytes32 raffleId
            RaffleInfo storage raffleInfo = raffle[chainlinkRaffleInfo[_requestId].id];

            raffleInfo.randomNumber =
            //@note do I need the + 1?
                (_randomWords[0] % chainlinkRaffleInfo[_requestId].size) +
                1;
            raffleInfo.randomNumberAvailable = true;


            emit RequestFulfilled(
                _requestId,
                _randomWords,
                chainlinkRaffleInfo[_requestId].id
            );   

        // call the winning function / send what was wone to winner
        endRaffle(raffleInfo.id);
    }

    //////////////////
    /// Automation ///
    //////////////////
    /**
     * @dev This is the function that the Chainlink Keeper nodes call
     * they look for `upkeepNeeded` to return True.
     * the following should be true for this to return true: the raffle has ended
     */
    function checkUpkeep(bytes memory /* checkData */) public view override returns (bool upkeepNeeded, bytes memory performData){
        for (uint256 i = 0; i < raffleIds.length; i++) {
            bytes32 raffleId = raffleIds[i];

            RaffleInfo storage raffleInfo = raffle[raffleId];
            upkeepNeeded = (raffleInfo.endTime < block.timestamp); 
            if (upkeepNeeded) {
                performData = abi.encode(raffleId);
                break;
            }
        }
    }

    /**
     * @dev Once `checkUpkeep` is returning `true`, this function is called
     * and it kicks off a Chainlink VRFv2 call to get a random number.
     */
    function performUpkeep(bytes calldata performData) external override {
        bytes32 raffleId = abi.decode(performData, (bytes32));
        RaffleInfo storage raffleInfo = raffle[raffleId];

        (bool upkeepNeeded, ) = checkUpkeep("");
        require(upkeepNeeded, "Upkeep not needed");
        require(raffleInfo.status == Status.STARTED, "Raffle in wrong status");
        //require(raffle.entriesLength > 0, "Raffle has no entries");
        require(raffleInfo.endTime < block.timestamp, "Raffle not expired or sold out yet");

        raffleInfo.status = Status.DRAWING;
        _requestRandomWords(raffleId);
    }

    ////////////////////
    /// Raffle Funcs ///
    ////////////////////

    function createRaffle(RaffleType _raffleType, uint256 _endTime, address _prize, uint256 _prizeId, uint256 _prizeAmount, uint256 _entryFee) external returns (bytes32 raffleId) {
        //@note how can I make ID more random? Can this just be a unit? Does it need to be random?
        if (_endTime < block.timestamp + 1 hours) {
            revert Raffle__InvalidEndTime();
        }

        raffleId = keccak256(abi.encodePacked(block.timestamp, msg.sender));

        RaffleInfo memory newRaffle = RaffleInfo({
            status: Status.CREATED,
            raffleType: _raffleType,
            id: raffleId,
            endTime: _endTime,
            randomNumber: 0,
            randomNumberAvailable: false,
            winner: address(0),
            prize: _prize,
            prizeId: _prizeId,
            prizeAmount: _prizeAmount,
            entryFee: _entryFee
        });

        raffle[raffleId] = newRaffle;
        raffleIds.push(raffleId);
        
        raffleCreator[raffleId] = msg.sender;


        emit RaffleCreated(raffleId, newRaffle.endTime);

    }

    //@todo make an only raffle starter modifier?
    function stakePrize(bytes32 _raffleId) external {
        // handle approvals
        _transferPrizeToRaffle(_raffleId);

        RaffleInfo storage raffleInfo = raffle[_raffleId];
        raffleInfo.status = Status.STARTED;

        emit RaffleStarted(_raffleId);

    }

    /**
     * @dev Allows the owner to add a user to a raffle
     * @param _usr The address of the user to add
     * @param _raffleId The id of the raffle to add the user to
     */
    function addToRaffle(address _usr, bytes32 _raffleId) external onlyOwner{
        RaffleInfo memory raffleInfo = raffle[_raffleId];
       
        if(raffleInfo.status != Status.STARTED) {
            revert Raffle__InvalidRaffle(_raffleId);
        }

        if(block.timestamp >= raffleInfo.endTime){
            revert Raffle__RaffleClosed();
        }
        // check if _usr is in the raffle
        if(raffleEntryIndex[_raffleId][_usr] != 0) {
            revert Raffle__AlreadyEntered(_usr);
        }

        // Add the user to the raffle
        raffleEntrants[_raffleId].push(_usr);

        // Get the index of the newly added user  - use .length to accout for 0 index 
        //@audit 0 index should never be used - invariant
        uint256 index = raffleEntrants[_raffleId].length;
        raffleEntryIndex[_raffleId][_usr] = index;

        emit AddedToRaffle(_usr, _raffleId);
    }

    /**
     * @dev Allows a user to enter a raffle. 
     * A user can only enter a raffle once
     * @param _raffleId The id of the raffle to enter
     */
    function enterRaffle(bytes32 _raffleId) external payable {
        RaffleInfo memory raffleInfo = raffle[_raffleId];

        if(raffleInfo.status != Status.STARTED) {
            revert Raffle__InvalidRaffle(_raffleId);
        }

        if(block.timestamp >= raffleInfo.endTime){
            revert Raffle__RaffleClosed();
        }

        if(raffleInfo.entryFee > 0 && msg.value != raffleInfo.entryFee) {
            require(msg.value == raffleInfo.entryFee, "Must send entry fee");
        }

        // check if _usr is in the raffle
        if(raffleEntryIndex[_raffleId][msg.sender] != 0) {
            revert Raffle__AlreadyEntered(msg.sender);
        }



        raffleEntrants[_raffleId].push(msg.sender);

        // Get the index of the newly added user  - use .length to accout for 0 index 
        uint256 index = raffleEntrants[_raffleId].length;
        raffleEntryIndex[_raffleId][msg.sender] = index;

        emit AddedToRaffle(msg.sender, _raffleId);

    }

    /**
     * @dev This func calls VRF to get a random number
    //  */
    // function pickWinner(bytes32 _raffleId) public returns (uint256 requestId){
    //     RaffleInfo memory raffleInfo = raffle[_raffleId];
    //     //entrants = raffleEntrants[_raffleId];

    //     raffleInfo.status = Status.DRAWING;
    //     // if(raffleInfo.status != Status.PENDING) {
    //     //     revert InvalidRaffle(_raffleId);
    //     // }
    //     if(block.timestamp < raffleInfo.endTime){
    //         revert Raffle__RaffleStillOpen();
    //     }

    //     requestId = _requestRandomWords(_raffleId);
    // }


    /**
     * @dev Ends the raffle and picks a winner.
     * This function should be called from the fulfillRandomWords callback function 
     * @param _raffleId The id of the raffle to end
     */
    //@todo add access control
    function endRaffle(bytes32 _raffleId) public returns (address winner) {
        // memory or storage
        RaffleInfo storage raffleInfo = raffle[_raffleId];
        
        if(block.timestamp < raffleInfo.endTime){
            revert Raffle__RaffleStillOpen();
        }

        if(raffleInfo.randomNumberAvailable == false){
            revert Raffle__RandomNumberNotAvailable(_raffleId);
        }

        if(raffleInfo.status != Status.DRAWING) {
            revert Raffle__InvalidRaffleState(raffleInfo.status);
        }

        entrantsArray = raffleEntrants[_raffleId];

        raffleInfo.winner = address(entrantsArray[raffleInfo.randomNumber]);

        _transferPrizeToWinner(_raffleId);

        raffleInfo.status = Status.ENDED;

        emit RaffleEnded(_raffleId, raffleInfo.winner);

        return raffleInfo.winner;
    }


    /////////////////////////////////////////////////////////////
    /// Helper funcs to move prizes in out of Raffle contract ///
    /////////////////////////////////////////////////////////////

    function _transferPrizeToWinner(bytes32 _raffleId) internal {
        RaffleInfo memory raffleInfo = raffle[_raffleId];

        if(raffleInfo.raffleType == RaffleType.ERC1155 && raffleInfo.prizeAmount == 1) {
                IERC1155(raffleInfo.prize).safeTransferFrom(address(this), raffleInfo.winner, raffleInfo.prizeId, raffleInfo.prizeAmount, "");
            } else if(raffleInfo.raffleType == RaffleType.ERC1155 && raffleInfo.prizeAmount > 1) {
                    uint256[] memory ids = new uint256[](raffleInfo.prizeAmount);
                    uint256[] memory amounts = new uint256[](raffleInfo.prizeAmount);

                for (uint256 i = 0; i < raffleInfo.prizeId; ++i) {
                    ids[i] = raffleInfo.prizeId; // Set the tokenId for each
                    amounts[i] = raffleInfo.prizeAmount; // Assuming each tokenId has an amount of 1
                }

                IERC1155(raffleInfo.prize).safeBatchTransferFrom(address(this), raffleInfo.winner, ids, amounts, "");
            }
            
            if(raffleInfo.raffleType == RaffleType.ERC721) {
                IERC721(raffleInfo.prize).safeTransferFrom(address(this), raffleInfo.winner, raffleInfo.prizeId, "");
            } else if(raffleInfo.raffleType == RaffleType.ERC20) {
                IERC20(raffleInfo.prize).transfer(raffleInfo.winner, raffleInfo.prizeAmount);
            }
    }

    function _transferPrizeToRaffle(bytes32 _raffleId) internal {
        RaffleInfo memory raffleInfo = raffle[_raffleId];

        if(raffleInfo.status != Status.CREATED) {
            revert Raffle__InvalidRaffleState(raffleInfo.status);
        }

        if(raffleInfo.raffleType == RaffleType.ERC1155 && raffleInfo.prizeAmount == 1) {
            IERC1155(raffleInfo.prize).safeTransferFrom(msg.sender, address(this), raffleInfo.prizeId, raffleInfo.prizeAmount, "");
        } else if(raffleInfo.raffleType == RaffleType.ERC1155 && raffleInfo.prizeAmount > 1) {
                uint256[] memory ids = new uint256[](raffleInfo.prizeAmount);
                uint256[] memory amounts = new uint256[](raffleInfo.prizeAmount);

            for (uint256 i = 0; i < raffleInfo.prizeId; ++i) {
                ids[i] = raffleInfo.prizeId; // Set the tokenId for each
                amounts[i] = raffleInfo.prizeAmount; // Assuming each tokenId has an amount of 1
            }

            IERC1155(raffleInfo.prize).safeBatchTransferFrom(msg.sender, address(this), ids, amounts, "");
        }
        
        if(raffleInfo.raffleType == RaffleType.ERC721) {
            IERC721(raffleInfo.prize).safeTransferFrom(msg.sender, address(this), raffleInfo.prizeId);
        }
        if(raffleInfo.raffleType == RaffleType.ERC20) {
            IERC20(raffleInfo.prize).transferFrom(msg.sender, address(this), raffleInfo.prizeAmount);
        }


    }

    /**
     * @dev Allows the owner to change the gas limit for the VRF callback
     * @param _newGasLimit The new gas limit
     */
    function changeGasLimit(uint32 _newGasLimit) external onlyOwner {
        if(_newGasLimit < 0) {revert Raffle__InvalidGasLimit();} 
        gasLimit = _newGasLimit;
    }
    //////////////////////////////
    /// safeTransfer receivers ///
    //////////////////////////////

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    ///////////////////////////
    /// Getter / View Funcs ///
    ///////////////////////////

    function getRaffleInfo(bytes32 _raffleId) public view returns(RaffleInfo memory) {
        return raffle[_raffleId];
    }

    function getRaffleEntrantsArray(bytes32 _raffleId) public view returns (address[] memory){
        return raffleEntrants[_raffleId];
    }

    function getRaffleCreator(bytes32 _raffleId) public view returns (address) {
        return raffleCreator[_raffleId];
    }

    function getCurrentGasLimit() public view returns (uint32) {
        return gasLimit;
    }

}