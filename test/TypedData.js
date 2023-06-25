const chai = require("chai");
const { ethers } = require("hardhat");
const chaiAsPromised  = require('chai-as-promised');
chai.use(chaiAsPromised);
const expect = chai.expect;
const crypto = require('crypto');

function combineSig(v, r, s) {
  return r + s.substr(2) + v.toString(16);
}

function splitSig(sig) {
  if (sig.startsWith("0x")) {
    sig = sig.substring(2);
  }
  return {r: "0x" + sig.slice(0, 64), s: "0x" + sig.slice(64, 128), v: parseInt(sig.slice(128, 130), 16)};

}

describe("LuckyBall-core", function () {

  //let signingKey = new ethers.utils.SigningKey("0x63eeb773af53b643eb56f5742e3f6bcafed1fa5538af07e02ccbd95726a4e554");
  //let signingKeyAddr = ethers.utils.computeAddress(signingKey.publicKey);
  //let signer = {address: signingKeyAddr, key: signingKey};

  //let hash =  ethers.utils.solidityKeccak256(["address", "address", "address"],[extAcct.address, shares3.party1, shares3.party2]);
  //let sig = extAcct.key.signDigest(hash);

  let TContract;
  let contract;
  let owner;
  let addr1;
  let addr2;
  let addr3;

  beforeEach(async function () {
    TContract = await ethers.getContractFactory("VerifyTypedData");
    [owner, addr1, addr2, addr3] = await ethers.getSigners();

    contract = await TContract.connect(owner).deploy();
    await contract.waitForDeployment();
    
  });

  it(" should return domain info", async function () {
    //let domain  = 
    let [ name, version, chainId, verifyingContract ] = await contract.getDomainInfo();
    chainId = parseInt(chainId);
    //console.log(name);
    //console.log(version);    
    //console.log(chainId);
    //console.log(verifyingContract);
    
    let domain = { name, version, chainId, verifyingContract };
    //Relay(address owner,uint256 deadline,uint256 nonce)
    let types = { Relay: [{name: 'owner', type: 'address'},
                          {name: 'deadline', type: 'uint256'},
                          {name: 'nonce', type: 'uint256'} ]};
    let relay = { owner: owner.address, deadline: 1719254576, nonce: 0};

    console.log(domain);
    console.log(types);
    console.log(relay);
    console.log('\c');
    let sig = await owner.signTypedData(domain, types, relay);
    console.log(sig);
    //console.log(typeof(chainId));
    let ss = splitSig(sig);
    let sigCombined = combineSig(ss.v, ss.r, ss.s);



    let v1 = await contract.verifySig(owner.address, 1719254576, ss.v, ss.r, ss.s);
    console.log(ss);
    console.log(sig);
    console.log(sigCombined);
    expect(v1).to.equal(true);
    expect(sig).to.equal(sigCombined);
    
    console.log(sig);
  });

 
});


