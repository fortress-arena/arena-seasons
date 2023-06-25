// SPDX-License-Identifier: MIT
/**
 * @title LuckBall Event Contract
 * @author Atomrigs Lab
 *
 * Supports ChainLink VRF_V2
 * Using EIP712 signTypedData_v4 for relay signature verification
 **/

pragma solidity ^0.8.18;

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
    uint64 s_subscriptionId = 5320; //https://vrf.chain.link/
    address vrfCoordinator = 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed; //Mumbai 
    bytes32 s_keyHash = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f;
    uint32 callbackGasLimit = 40000;
    uint16 requestConfirmations = 3;
    uint32 numWords =  1;
    uint256 public lastRequestId;

    struct RequestStatus {
        bool exists; // whether a requestId exists        
        bool isSeasonPick; //True if this random is for picking up the season BallId winner 
        uint seed;
    }
    mapping(uint => RequestStatus) public s_requests; /* requestId --> requestStatus */   
    //

    //EIP 712 related
    bytes32 public DOMAIN_SEPARATOR;
    mapping (address => uint) private _nonces;
    //

    mapping(uint => Season) public seasons;
    mapping(address => mapping(uint => uint[])) public userBallGroups; //user addr => seasonId => ballGroupPos
    mapping(uint => uint) public revealGroups;
    mapping(uint => uint) public revealGroupSeeds; // revealGroup => revealSeed 
    mapping(address => uint) public newRevealPos;
    mapping(address => mapping(uint => uint)) public userBallCounts; //userAddr => seasonId => count

    event BallIssued(address recipient, uint qty);
    event RevealRequested(address requestor);
    event SeasonStarted();
    event SeasonEnded();
    event CodeSeedRevealed(uint revealGroup);
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
        _setDomainSeparator(); //EIP712
    }

    // EIP 712 and Relay functions
    function nonces(address user) public view returns (uint256) {
        return _nonces[user];
    }   

    function getDomainInfo() public view returns (string memory, string memory, uint, address) {
        string memory name = "LuckyBall_Relay";
        string memory version = "1";
        uint chainId = block.chainid;
        address verifyingContract = address(this);
        return (name, version, chainId, verifyingContract);
    }

    function getRelayMessageTypes() public pure returns (string memory) {
      string memory dataTypes = "Relay(address owner,uint256 deadline,uint256 nonce)";
      return dataTypes;      
    }

    function _setDomainSeparator() internal {
        string memory EIP712_DOMAIN_TYPE = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
        ( string memory name, string memory version, uint chainId, address verifyingContract ) = getDomainInfo();
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(abi.encodePacked(EIP712_DOMAIN_TYPE)),
                keccak256(abi.encodePacked(name)),
                keccak256(abi.encodePacked(version)),
                chainId,
                verifyingContract
            )
        );
    }

    function getEIP712Hash(address _user, uint _deadline, uint _nonce) public view returns (bytes32) {
        string memory MESSAGE_TYPE = getRelayMessageTypes();
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01", // backslash is needed to escape the character
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        keccak256(abi.encodePacked(MESSAGE_TYPE)),
                        _user,
                        _deadline,
                        _nonce
                    )
                )
            )
        );
        return hash;
    }

    function verifySig(address _user, uint _deadline, uint _nonce,  uint8 v, bytes32 r,bytes32 s) public view returns (bool) {
        bytes32 hash = getEIP712Hash(_user, _deadline, _nonce);
        if (v < 27) {
          v += 27;
        }
        return _user == ecrecover(hash, v, r, s);
    }

    //


    function setOperator(address _newOperator) public onlyOwner returns (bool) {
        _operator = _newOperator;
        return true;
    }

    function getOperator() public view returns (address) {
        return _operator;
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

        emit SeasonStarted();
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
        require(isSeasonActive(), "LuckyBall: Season is not active");
        for(uint i=0; i<_tos.length; i++) {
            require(_qty[i] > 0, "LuckyBall: qty should be bigger than 0");
            ballCount += _qty[i];
            ballGroups.push(ballCount);
            addrGroups.push(_tos[i]);
            userBallGroups[_tos[i]][getCurrentSeasionId()].push(ballGroups.length-1);
            userBallCounts[_tos[i]][getCurrentSeasionId()] += _qty[i];
            emit BallIssued(_tos[i], _qty[i]);
        } 
        return true;       
    }

    function getUserBallGroups(address addr, uint seasonId) public view returns (uint[] memory) {
        uint[] memory myGroups = userBallGroups[addr][seasonId];
        return myGroups;
    }

    function issueTest() public onlyOperators() {
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

    function setWinningBallId(uint winner) public onlyOperators() returns (bool) {
        seasons[getCurrentSeasionId()].winningBallId = winner;
        return true;
        
    }

    function extractCode(uint n) internal pure returns (uint) {
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
            return false;
        }
        uint newPos = newRevealPos[_addr];
        if (myGroups.length >= newPos) {
            for (uint i=newPos; i<myGroups.length; i++) {
                revealGroups[myGroups[i]] = revealGroupId;
            }
            newRevealPos[_addr] = myGroups.length;
            return true;
        }
        emit RevealRequested(_addr);
        return false;
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

    function relayRequestReveal(        
        address user,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s) 
        public returns (bool) {

        uint nonce = _nonces[user]++;
        require(deadline >= block.timestamp, "LuckyBall: expired deadline");
        require(verifySig(user, deadline, nonce, v, r, s), "LuckyBall: user sig does not match");
        
        _requestReveal(user);
        emit RevealRequested(user);
        return true;
    }

    function relayRequestRevealBatch(
        address[] calldata users,
        uint[] calldata deadlines,
        uint8[] calldata vs,
        bytes32[] calldata rs,
        bytes32[] calldata ss) 
        public returns(bool) {
        
        for(uint i=0; i<users.length; i++) {
            relayRequestReveal(users[i],deadlines[i], vs[i], rs[i], ss[i]);
        }
        return true;
    }

    function endSeason() external onlyOperators() returns (bool) {
        if (ballGroups.length > 0) {
            uint endBallGroupPos = ballGroups.length-1;
            uint startBallGroupPos = seasons[getCurrentSeasionId()].startBallGroupPos;
            if (endBallGroupPos - startBallGroupPos > 0) {
                seasons[getCurrentSeasionId()].endBallGroupPos = endBallGroupPos;
                requestRandomSeed(true); 
                return true;
            }
        }
        return false;
    }

    function setRevealGroupSeed(uint randSeed) private {
        revealGroupSeeds[getCurrentRevealGroupId()] = randSeed;
        emit CodeSeedRevealed(getCurrentRevealGroupId());        
        _revealGroupIds++;
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
        emit SeasonEnded();
    }    

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        s_requests[requestId].seed = randomWords[0];
        if (s_requests[requestId].isSeasonPick) {
            setSeasonWinner(randomWords[0]);
        } else {
            setRevealGroupSeed(randomWords[0]);
        }
    }
}