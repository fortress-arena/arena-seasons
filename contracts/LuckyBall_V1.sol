// SPDX-License-Identifier: MIT
/**
 * @title LuckyBall Event Contract
 * @author Atomrigs Lab
 *
 * Supports ChainLink VRF_V2
 * Using EIP712 signTypedData_v4 for relay signature verification
 **/

pragma solidity ^0.8.18;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract LuckyBall2 is VRFConsumerBaseV2{

    uint32 private _ballId;
    uint16 private _seasonId;
    uint32 private _revealGroupId;    
    address private _owner;
    address private _operator;

    //uint[] public ballGroups;
    //address[] public addrGroups;
    uint32 public ballCount;
    bool public revealNeeded;

    struct BallGroup {
        uint32 endBallId;
        address owner;
    }

    struct Season {
        uint16 seasonId;
        uint32 startBallId;
        uint32 endBallId;
        uint32 winningBallId;
        uint32 winningCode;
    }

    BallGroup[] public ballGroups;

    //chainlink 
    VRFCoordinatorV2Interface immutable COORDINATOR;
    uint64 immutable s_subscriptionId; //= 5320; //https://vrf.chain.link/
    //address immutable vrfCoordinator; //= 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed; //Mumbai 
    bytes32 immutable s_keyHash; // = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f;
    uint32 constant callbackGasLimit = 400000;
    uint16 constant requestConfirmations = 3;
    uint32 constant numWords =  1;
    uint256 public lastRequestId;

    struct RequestStatus {
        bool exists; // whether a requestId exists        
        bool isSeasonPick; //True if this random is for picking up the season BallId winner 
        uint256 seed;
    }
    mapping(uint256 => RequestStatus) public s_requests; /* requestId --> requestStatus */   
    //

    //EIP 712 related
    bytes32 public DOMAIN_SEPARATOR;
    mapping (address => uint256) private _nonces;
    //

    mapping(uint16 => Season) public seasons;
    mapping(address => mapping(uint16 => uint32[])) public userBallGroups; //user addr => seasonId => ballGroupPos
    mapping(uint32 => uint32) public revealGroups; //ballId => revealGroupId
    mapping(uint32 => uint256) public revealGroupSeeds; // revealGroupId => revealSeed 
    mapping(address => uint32) public newRevealPos;
    //mapping(address => mapping(uint16 => uint32)) public userBallCounts; //userAddr => seasonId => count
    mapping(uint32 => uint32[]) public ballPosByRevealGroup; // revealGroupId => [ballPos]

    event BallIssued(uint16 seasonId, address indexed recipient, uint32 qty, uint32 endBallId);
    event RevealRequested(uint16 seasonId, uint32 revealGroupId, address indexed requestor);
    event SeasonStarted(uint16 seasonId);
    event SeasonEnded(uint16 seasonId);
    event CodeSeedRevealed(uint16 seasonId, uint32 revealGroupId);
    event WinnerPicked(uint16 indexed seasonId, uint32 ballId);
    event OwnerTransfered(address owner);
    event SetOperator(address operator);

    modifier onlyOperators() {
        require(_operator == msg.sender || _owner == msg.sender, "LuckyBall: caller is not the operator address!");
        _;
    } 
    modifier onlyOwner() {
        require(_owner == msg.sender, "LuckyBall: caller is not the owner address!");
        _;
    }       

    constructor(
        uint64 subscriptionId,
        address vrfCoordinator,
        bytes32 keyHash
    ) VRFConsumerBaseV2(vrfCoordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        s_keyHash = keyHash;
        s_subscriptionId = subscriptionId;
        _revealGroupId++;
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
        uint256 chainId = block.chainid;
        address verifyingContract = address(this);
        return (name, version, chainId, verifyingContract);
    }

    function getRelayMessageTypes() public pure returns (string memory) {
        string memory dataTypes = "Relay(address owner,uint256 deadline,uint256 nonce)";
        return dataTypes;      
    }

    function _setDomainSeparator() internal {
        string memory EIP712_DOMAIN_TYPE = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
        ( string memory name, string memory version, uint256 chainId, address verifyingContract ) = getDomainInfo();
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

    function getEIP712Hash(address _user, uint256 _deadline, uint256 _nonce) public view returns (bytes32) {
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

    function verifySig(address _user, uint256 _deadline, uint256 _nonce,  uint8 v, bytes32 r, bytes32 s) public view returns (bool) {
        bytes32 hash = getEIP712Hash(_user, _deadline, _nonce);
        if (v < 27) {
          v += 27;
        }
        return _user == ecrecover(hash, v, r, s);
    }

    //

    function transferOwner(address _newOwner) external onlyOwner {
        _owner = _newOwner;
        emit OwnerTransfered(_newOwner);
    }

    function setOperator(address _newOperator) external onlyOwner {
        _operator = _newOperator;
        emit SetOperator(_newOperator);
    }

    function getOwner() public view returns (address) {
        return _owner;
    }    

    function getOperator() public view returns (address) {
        return _operator;
    }

    function getCurrentSeasonId() public view returns (uint16) {
        return _seasonId;
    }

    function getCurrentBallGroupPos() public view returns (uint32) {
        return uint32(ballGroups.length);
    }

    function getCurrentRevealGroupId() public view returns (uint32) {
        return _revealGroupId;
    }     

    function startSeason() external onlyOperators() {
        if (_seasonId > 0 && seasons[_seasonId].winningBallId == 0) {
            revert('LuckyBall: the current season should be ended first');
        }        
        _seasonId++;
        uint32 start;
        if (ballGroups.length == 0) {
            start = 1;    
        } else {
            start = ballGroups[getCurrentBallGroupPos()-1].endBallId + 1;
        }    

        seasons[_seasonId] = 
                Season(_seasonId, 
                        start, 
                        0, 
                        0,
                        generateWinningCode());

        emit SeasonStarted(_seasonId);
    }

    function isSeasonActive() public view returns (bool) {
        if(seasons[_seasonId].winningBallId > 0) {
            return false;
        }
        if (_seasonId == uint(0)) {
            return false;
        }
        return true;
    }    

    function issueBalls(address[] calldata _tos, uint32[] calldata _qty) external onlyOperators() returns (bool) {
        require(_tos.length == _qty.length, "LuckBall: address and qty counts do not match");
        require(isSeasonActive(), "LuckyBall: Season is not active");
        uint16 length = uint16(_tos.length); 
        unchecked {
            for(uint16 i=0; i<length; ++i) {
                address to = _tos[i];
                uint32 qty = _qty[i];
                require(qty > 0, "LuckyBall: qty should be bigger than 0");
                ballCount += qty;
                ballGroups.push(BallGroup(ballCount, to));
                userBallGroups[to][_seasonId].push(uint32(ballGroups.length-1));
                emit BallIssued(_seasonId, to, qty, ballCount);
            } 
        }
        return true;       
    }

    function getUserBallCount(address user, uint16 seasonId) public view returns (uint32) {
        uint32[] memory groupPos = userBallGroups[user][seasonId];
        uint32 count;
        uint16 length = uint16(groupPos.length);
        unchecked {
            for(uint16 i=0; i<length; ++i) {
                BallGroup memory group = ballGroups[groupPos[i]];
                uint32 start;
                //uint32 end;
                if (groupPos[i]==0) {
                    start = 0;
                } else {
                    start = ballGroups[groupPos[i]-1].endBallId; 
                }
                count += group.endBallId - start; 
            }
        }
        return count;
    }

    function ownerOf(uint32 ballId) public view returns (address) {
        if (ballId == 0) {
            return address(0);
        }
        for(uint32 i=0; i < ballGroups.length; ++i) {
            if(ballId <= ballGroups[i].endBallId) {
                return ballGroups[i].owner;
            }
        }
        return address(0);
    }         

    function generateWinningCode() internal view returns (uint32) {
        return extractCode(uint256(keccak256(abi.encodePacked(blockhash(block.number -1), block.timestamp))));        
    }

    function extractCode(uint256 n) internal pure returns (uint32) {
        uint256 r = n % 1000000;
        if (r < 100000) { r += 100000; }
        return uint32(r);
    } 

    function requestReveal() external returns (bool) {
        return _requestReveal(msg.sender);
    }

    function _requestReveal(address _addr) internal returns (bool) {
        uint32[] memory myGroups = userBallGroups[_addr][_seasonId];
        uint32 myLength = uint32(myGroups.length);
        uint32 newPos = newRevealPos[_addr];
        require(myLength > 0, "LuckyBall: No balls to reveal");
        require(myLength > newPos, "LuckyBall: No new balls to reveal");
        unchecked {
            for (uint32 i=newPos; i<myLength; ++i) {
                revealGroups[myGroups[i]] = _revealGroupId;
                ballPosByRevealGroup[_revealGroupId].push(myGroups[i]);
            }          
        }  
        newRevealPos[_addr] = myLength;

        if (!revealNeeded) {
            revealNeeded = true;
        }
        emit RevealRequested(_seasonId, _revealGroupId, _addr);
        return false;
    }

    function getRevealGroup(uint32 ballId) public view returns (uint32) {
        return revealGroups[getBallGroupPos(ballId)];
    }

    function getBallGroupPos(uint32 ballId) public view returns (uint32) {
        uint32 groupLength = uint32(ballGroups.length);
        require (ballId > 0 && ballId <= ballCount, "LuckyBall: ballId is out of range");
        require (groupLength > 0, "LuckyBall: No ball issued");
        unchecked {
            for (uint32 i=groupLength-1; i >= 0; --i) {
                uint32 start;
                if (i == 0) {
                    start = 1;
                } else {
                    start = ballGroups[i-1].endBallId + 1;
                }
                uint32 end = ballGroups[i].endBallId;

                if (ballId <= end && ballId >= start) {
                    return i;
                }
                continue;
            }
        }
        revert("LuckyBall: BallId is not found");
    } 

    function getBallCode(uint32 ballId) public view returns (uint32) {
        uint256 randSeed = revealGroupSeeds[getRevealGroup(ballId)];
        if (randSeed > 0) {
            return extractCode(uint(keccak256(abi.encodePacked(randSeed, ballId))));
        }
        return uint32(0);
    }

    function getBalls(address addr, uint16 seasonId) public view returns (uint32[] memory) {
        uint32[] memory myGroups = userBallGroups[addr][seasonId];
        uint32[] memory ballIds = new uint32[](getUserBallCount(addr, seasonId));

        uint256 pos = 0;
        unchecked {
            for (uint256 i=0; i < myGroups.length; ++i) {
                uint32 end = ballGroups[myGroups[i]].endBallId;
                uint32 start;
                if (myGroups[i] == 0) {
                    start = 1;    
                } else {
                    start = ballGroups[myGroups[i] - 1].endBallId + 1;
                }
                for (uint32 j=start; j<=end; ++j) {
                    ballIds[pos] = j;
                    ++pos;
                }                           
            }
        }
        return ballIds;
    }

    function getBalls() public view returns(uint32[] memory) {
        return getBalls(msg.sender, _seasonId);
    }

    function getBallsByRevealGroup(uint32 revealGroupId) public view returns (uint32[] memory) {
        uint32[] memory ballPos = ballPosByRevealGroup[revealGroupId];
        uint256 posLength = ballPos.length;
        uint32 groupBallCount;
        unchecked {
            for (uint256 i=0; i < posLength; i++) {
                uint32 start;
                uint32 end = ballGroups[ballPos[i]].endBallId;
                if (ballPos[i] == 0) {
                    start = 1;
                } else {
                    start = ballGroups[ballPos[i] - 1].endBallId + 1; 
                }
                groupBallCount += (end - start + 1);
            }
            uint32[] memory ballIds = new uint32[](groupBallCount);
            uint256 pos = 0;
            for (uint256 i=0; i < posLength; i++) {
                uint32 end = ballGroups[ballPos[i]].endBallId;            
                uint32 start;
                if (ballPos[i] == 0) {
                    start = 1;
                } else {
                    start = ballGroups[ballPos[i] - 1].endBallId + 1; 
                }
                for (uint32 j=start; j <= end; j++) {
                    ballIds[pos] = j;
                    pos++;
                }
            }
            return ballIds;
        }
    }

    function relayRequestReveal(        
        address user,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s) 
        public returns (bool) {

        require(deadline >= block.timestamp, "LuckyBall: expired deadline");
        require(verifySig(user, deadline, _nonces[user], v, r, s), "LuckyBall: user sig does not match");
        
        _requestReveal(user);
        _nonces[user]++;
        return true;
    }

    function relayRequestRevealBatch(
        address[] calldata users,
        uint256[] calldata deadlines,
        uint8[] calldata vs,
        bytes32[] calldata rs,
        bytes32[] calldata ss) 
        public returns(bool) {
        
        for(uint256 i=0; i<users.length; i++) {
            relayRequestReveal(users[i],deadlines[i], vs[i], rs[i], ss[i]);
        }
        return true;
    }

    function endSeason() external onlyOperators() returns (bool) {
        require(ballGroups.length > 0, "LuckyBall: No balls issued yet");
        if (revealNeeded) {
            requestRevealGroupSeed();
        }
        seasons[_seasonId].endBallId = ballGroups[ballGroups.length-1].endBallId;
        requestRandomSeed(true); 
        return true;
    }

    function requestRevealGroupSeed() public onlyOperators() returns (uint256) {
        if (revealNeeded) {
            return requestRandomSeed(false);
        } else {
            return uint256(0);      
        }
    }

    function setRevealGroupSeed(uint256 randSeed) internal {
        revealGroupSeeds[_revealGroupId] = randSeed;
        emit CodeSeedRevealed(_seasonId, _revealGroupId);
        revealNeeded = false;        
        _revealGroupId++;
    }

    function requestRandomSeed(bool _isSeasonPick) internal returns (uint256) {
        uint256 requestId = COORDINATOR.requestRandomWords(
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

    function setSeasonWinner(uint256 randSeed) internal {
        Season storage season = seasons[_seasonId];
        uint256 seasonBallCount = uint256(season.endBallId - season.startBallId + 1);
        season.winningBallId = season.startBallId + uint32(randSeed % seasonBallCount);
        emit WinnerPicked(_seasonId, season.winningBallId); 
        emit SeasonEnded(_seasonId);
    }    

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        uint256 seed =  uint(keccak256(abi.encodePacked(randomWords[0], block.timestamp)));
        s_requests[requestId].seed = seed;
        if (s_requests[requestId].isSeasonPick) {
            setSeasonWinner(seed);
        } else {
            setRevealGroupSeed(seed);
        }
    }
}