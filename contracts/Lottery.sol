// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFV2WrapperConsumerBase.sol";


contract VRFv2DirectFundingConsumer is
    VRFV2WrapperConsumerBase,
    ConfirmedOwner
{
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(
        uint256 requestId,
        uint256[] randomWords,
        uint256 payment
    );

    struct RequestStatus {
        uint256 paid; // amount paid in link
        bool fulfilled; // whether the request has been successfully fulfilled
        uint256[] randomWords;
    }

    mapping(uint256 => RequestStatus)
        public s_requests; /* requestId --> requestStatus */

    uint256[] public requestIds;
    uint256 public lastRequestId;
    uint256[] public lastResult;
    uint32 callbackGasLimit = 130000;
    uint16 requestConfirmations = 3;
    uint32 numWords = 1;

    uint public totalAmount;

    uint public lotteryId;
    address payable public lotteryOwner;
    address payable[] public players;
    mapping(uint => address payable) public lotteryHistory;

    // Address LINK - hardcoded for Sepolia
    address linkAddress = 0x779877A7B0D9E8603169DdbD7836e478b4624789;

    // address WRAPPER - hardcoded for Sepolia
    address wrapperAddress = 0xab18414CD93297B0d12ac29E63Ca20f515b3DB46;


    event WinnerPicked(uint index, address winnerAddress);

    /// You have to pay 400 gwei to participate in the lottery!
    error NotEnoughEther();

    /// Can be done only by the owner
    error NotOwner();

    modifier MoneyAreSent() {
        if (msg.value < 400 * 100000000) 
            revert NotEnoughEther();
        _;
        
    }

    modifier OnlyOwner() {
        if (msg.sender != lotteryOwner) 
            revert NotOwner();
        _;  
    }

    constructor()
        ConfirmedOwner(msg.sender)
        VRFV2WrapperConsumerBase(linkAddress, wrapperAddress)

    {
            lotteryOwner = payable(msg.sender);
            lotteryId = 1;
            totalAmount = 0;
    }

  

    function enter() public payable MoneyAreSent {
        // address of a player entering lottery
        players.push(payable(msg.sender));
        totalAmount += msg.value;
    }

    function deposit() payable external {
    
    }

    receive() external payable{}


    function rewardWinner(uint winnerIndex) internal  {
        players[winnerIndex].transfer(totalAmount);
        lotteryHistory[lotteryId] = players[winnerIndex];
        lotteryId += 1;
        
        // New players addresses array with 0 length
        players = new address payable[](0);
    }

    function pickWinner()
        external
        OnlyOwner
        returns (uint256 requestId)
    {
        requestId = requestRandomness(
            callbackGasLimit,
            requestConfirmations,
            numWords
        );
        s_requests[requestId] = RequestStatus({
            paid: VRF_V2_WRAPPER.calculateRequestPrice(callbackGasLimit),
            randomWords: new uint256[](0),
            fulfilled: false
        });
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        return requestId;
    }


    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(s_requests[_requestId].paid > 0, "request not found");

        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        emit RequestFulfilled(
            _requestId,
            _randomWords,
            s_requests[_requestId].paid
        );

        
        if (_randomWords.length > 0) {
            uint winnerIndex = _randomWords[0] % (players.length + 1);
            rewardWinner(winnerIndex);  
            emit WinnerPicked(winnerIndex, players[winnerIndex]);      
        }
    }


    function withdrawLink() public OnlyOwner {
        LinkTokenInterface link = LinkTokenInterface(linkAddress);
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }

    function withdrawEth() public OnlyOwner {
         selfdestruct(lotteryOwner);
    }
}
