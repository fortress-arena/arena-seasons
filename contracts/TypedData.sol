// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;


contract VerifyTypedData {

    bytes32 public DOMAIN_SEPARATOR;
    mapping (address => uint) private _nonces;

    constructor() {
        _setDomainSeparator();
    }

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

    function verifySig(address _user, uint _deadline, uint8 v, bytes32 r,bytes32 s) public view returns (bool) {
        bytes32 hash = getEIP712Hash(_user, _deadline, _nonces[_user]);
        if (v < 27) {
          v += 27;
        }
        return _user == ecrecover(hash, v, r, s);
    }

}