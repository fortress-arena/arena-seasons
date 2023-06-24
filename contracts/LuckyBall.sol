// SPDX-License-Identifier: MIT
/**
 * @title LuckBall Event Contract
 * @author Atomrigs Lab
 *
 **/

pragma solidity ^0.8.9;

//import "@openzeppelin/contracts/access/Ownable.sol";
//import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract LuckyBall is VRFConsumerBaseV2{

    uint private _ballIds;
    uint private _seasonIds;
    uint private _revealGroupIds;    
    address private _owner;
    address private _operator;
    bool public isActive = false;
    uint[] public ballGroups;
    address[] public addrGroups;
    uint public ballCount = 0;
    struct Season {
        uint seasonId;
        uint startBallGroupPos;
        uint endBallGroupPos;
        uint winningBallId;
        uint winningCode;
    }

    //chainlink 
    VRFCoordinatorV2Interface COORDINATOR;
    uint64 s_subscriptionId = 5320;
    address vrfCoordinator = 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed;
    bytes32 s_keyHash = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f;
    uint32 callbackGasLimit = 40000;
    uint16 requestConfirmations = 3;
    uint32 numWords =  1;
    uint256 public lastRequestId;

    //address linkToken = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;

    struct RequestStatus {
        bool exists; // whether a requestId exists        
        bool isSeasonPick; //True if this random is for picking up the season BallId winner 
        uint seed;
    }
    mapping(uint => RequestStatus) public s_requests; /* requestId --> requestStatus */   
    //
    mapping(address => uint256) private _nonces;
    mapping(uint => Season) public seasons;
    mapping(address => mapping(uint => uint[])) public userBallGroups; //user addr => seasonId => ballGroupPos
    mapping(uint => uint) public revealGroups;
    mapping(uint => uint) public revealGroupSeeds; // revealGroup => revealSeed 
    mapping(address => uint) public newRevealPos;
    mapping(address => mapping(uint => uint)) public userBallCounts; //userAddr => seasonId => count

    event BallIssued(address recipient, uint qty);
    event RevealRequested(address requestor);
    event SeasonStarted();
    event SeasonClosed();
    event Revealed(uint revealGroup);
    event WinnerPicked(uint season, uint ballId);

    modifier onlyOperators() {
        require(_operator == msg.sender || _owner == msg.sender, "LuckyBall: caller is not the operator address!");
        _;
    } 
    modifier onlyOwner() {
        require(_owner == msg.sender, "LuckyBall: caller is not the owner address!");
        _;
    }       

    constructor() 
        VRFConsumerBaseV2(vrfCoordinator) {
        _revealGroupIds++;
        _owner = msg.sender;
        _operator = msg.sender;
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        //s_owner = msg.sender;
    }

    function nonces(address user) public view returns (uint256) {
        return _nonces[user];
    }     

    function setOperator(address _newOperator) public onlyOwner returns (bool) {
        _operator = _newOperator;
        return true;
    }

    function getCurrentSeasionId() public view returns (uint) {
        return _seasonIds;
    }

    function getCurrentBallGroupPos() public view returns (uint) {
        return ballGroups.length;
    }

    function getCurrentRevealGroupId() public view returns (uint) {
        return _revealGroupIds;
    }     

    function startSeason() external onlyOperators() returns (uint) {
        _seasonIds++;
        uint seasonId = getCurrentSeasionId();
        seasons[seasonId] = 
                Season(seasonId, 
                        getCurrentBallGroupPos(), 
                        uint(0), 
                        uint(0),
                        generateWinningCode());

        return seasonId;
    }

    function isSeasonActive() public view returns (bool) {
        if(seasons[getCurrentSeasionId()].winningBallId > 0) {
            return false;
        }
        if (getCurrentSeasionId() == uint(0)) {
            return false;
        }
        return true;
    }    

    function issueBalls(address[] calldata _tos, uint[] calldata _qty) public onlyOperators() returns (bool) {
        require(_tos.length == _qty.length, "LuckBall: address and qty counts do not match");
        require(isSeasonActive(), "Season is not active");
        for(uint i=0; i<_tos.length; i++) {
            require(_qty[i] > 0, "LuckBall: qty should be bigger than 0");
            ballCount += _qty[i];
            ballGroups.push(ballCount);
            addrGroups.push(_tos[i]);
            userBallGroups[_tos[i]][getCurrentSeasionId()].push(ballGroups.length-1);
            userBallCounts[_tos[i]][getCurrentSeasionId()] += _qty[i];
            emit BallIssued(_tos[i], _qty[i]);
        } 
        return true;       
    }

    function issueTest() public {
        address a = 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4;
        ballCount += 100;
        ballGroups.push(ballCount);
        addrGroups.push(a);
        userBallGroups[a][getCurrentSeasionId()].push(ballGroups.length-1);
        userBallCounts[a][getCurrentSeasionId()] += 100;
        emit BallIssued(a, 100);
    }

    function ownerOf(uint ballId) public view returns (address) {
        if (ballId == 0) {
            return address(0);
        }
        for(uint i=0; i < ballGroups.length; i++) {
            if(ballId <= ballGroups[i]) {
                return addrGroups[i];
            }
        }
        return address(0);
    }         

    function generateWinningCode() internal view returns (uint) {
        return extractCode(uint(keccak256(abi.encodePacked(blockhash(block.number -1), block.timestamp))));        
    }

    function endSeason() external returns (bool) {
        seasons[getCurrentSeasionId()].endBallGroupPos = ballGroups.length-1;
        requestWinningBallId(); 
        return true;
    }

    function requestWinningBallId() public pure returns (bool) {
        return true;
    }

    function setWinningBallId(uint winner) public onlyOperators() returns (bool) {
        seasons[getCurrentSeasionId()].winningBallId = winner;
        return true;
        
    }

    function extractCode(uint n) public pure returns (uint) {
        uint r = n % 1000000;
        if (r < 100000) { r += 100000; }
        return r;
    } 

    function requestReveal() public returns (bool) {
        return _requestReveal(msg.sender);
    }

    function _requestReveal(address _addr) private returns (bool) {
        uint[] memory myGroups = userBallGroups[_addr][getCurrentSeasionId()];
        uint revealGroupId = getCurrentRevealGroupId();

        if (myGroups.length == 0) {
            return true;
        }
        uint newPos = newRevealPos[_addr];
        if (myGroups.length >= newPos) {
            for (uint i=newPos; i<myGroups.length; i++) {
                revealGroups[myGroups[i]] = revealGroupId;
            }
            newRevealPos[_addr] = myGroups.length+1;
        }
        emit RevealRequested(_addr);
        return true;
    }

    function getRevealGroup(uint ballId) public view returns (uint) {
        return revealGroups[getBallGroupPos(ballId)];
    }

    function getBallGroupPos(uint ballId) public view returns (uint) {
        require (ballId > 0 && ballId <= ballCount, "LuckyBall: ballId is out of range");
        require (ballGroups.length > 0, "LuckBall: No ball issued");
    
        for (uint i=ballGroups.length-1; i >= 0; i--) {
            uint start;
            if (i == 0) {
                start = 1;
            } else {
                start = ballGroups[i-1]+1;
            }
            uint end = ballGroups[i];

            if (ballId <= end && ballId >= start) {
                return i;
            }
            continue;
        }
        revert("BallId is not found");
    } 

    function setRevealGroupSeed(uint randSeed) internal {
        revealGroupSeeds[getCurrentRevealGroupId()] = randSeed;
        _revealGroupIds++;
    }

    function setSeasonWinner(uint randSeed) internal {
        Season storage season = seasons[getCurrentSeasionId()];
        uint startBallId;
        uint lastBallId = ballGroups[season.endBallGroupPos];
        if (season.startBallGroupPos == uint(0)) {
            startBallId = 1;
        } else {
            startBallId = ballGroups[season.startBallGroupPos-1] + 1;
        }
        uint seasonBallCount = lastBallId - startBallId + 1;
        season.winningBallId = startBallId + (randSeed % seasonBallCount); 
    }

    function getBallCode(uint ballId) public view returns (uint) {
        uint randSeed = revealGroupSeeds[getRevealGroup(ballId)];
        if (randSeed > uint(0)) {
            return extractCode(uint(keccak256(abi.encodePacked(randSeed, ballId))));
        }
        return uint(0);
    }

    function getBalls(address _addr, uint _seasonId) public view returns (uint[] memory) {
        uint[] memory myGroups = userBallGroups[_addr][_seasonId];
        Season memory season = seasons[_seasonId];
        uint seasonTopPos = season.endBallGroupPos;
        uint[] memory ballIds = new uint[](userBallCounts[_addr][_seasonId]);

        if (seasonTopPos == uint(0)) {
            seasonTopPos = ballGroups.length-1;
        }
        uint pos = 0;
        for (uint i=0; i < myGroups.length; i++) {
            uint end = ballGroups[myGroups[i]];
            uint start;
            if (myGroups[i] == uint(0)) {
                start = 1;    
            } else {
                start = ballGroups[myGroups[i] - 1] + 1;
            }
            for (uint j=start; j<=end; j++) {
                ballIds[pos] = j;
                pos++;
            }                           

        }
        return ballIds;
    }

    function getBalls() public view returns(uint[] memory) {
        return getBalls(msg.sender, getCurrentSeasionId());
    }

    function getHash(
        uint chainId,
        address _this, 
        address user, 
        uint deadline,
        uint nonce,
        string memory method) 
        public pure 
        returns (bytes32) {

        return keccak256(abi.encodePacked(chainId, _this, user, deadline, nonce, method));
    }

    function verifySig(address addr, bytes32 _hash, uint8 v, bytes32 r, bytes32 s) 
        public pure 
        returns (bool) {
        return ecrecover(_hash, v, r, s) == addr;
    }

    function getChainId() public view returns (uint) {
        uint chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;        
    }


    function relayRequestReveal(        
        address user,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s) 
        public returns (bool) {
        
        require (deadline >= block.timestamp, "LuckyBall: expired deadline");

        uint nonce = _nonces[user]++;
        uint chainId = getChainId();
        bytes32 _hash = getHash(
            chainId,
            address(this), 
            user, 
            deadline,
            nonce,
            "relayRequestReveal"
        );
        require (verifySig(user, _hash, v, r, s), "LuckyBall: sig does not match"); 
        _requestReveal(user);
        emit RevealRequested(user);
        return true;
    }

    function requestRandomSeed(bool _isSeasonPick) private returns (uint) {
        uint requestId = COORDINATOR.requestRandomWords(
            s_keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        lastRequestId = requestId;
        s_requests[requestId] = RequestStatus(true, _isSeasonPick, 0);
        return requestId;
        //emit DiceRolled(requestId, roller);        
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        s_requests[requestId].seed = randomWords[0];
        if (s_requests[requestId].isSeasonPick) {

        } else {
            setRevealGroupSeed(randomWords[0]);
        }
    }
}