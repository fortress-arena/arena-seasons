const chai = require("chai");
const { ethers } = require("hardhat");
const chaiAsPromised  = require('chai-as-promised');
chai.use(chaiAsPromised);
const expect = chai.expect;

const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");

function combineSig(v, r, s) {
  return r + s.substr(2) + v.toString(16);
}

function splitSig(sig) {
  if (sig.startsWith("0x")) {
    sig = sig.substring(2);
  }
  return {r: "0x" + sig.slice(0, 64), s: "0x" + sig.slice(64, 128), v: parseInt(sig.slice(128, 130), 16)};
}

describe("EIP712 signature verification", function () {

  let LuckyBallContract;
  let contract;
  let owner;
  let user1;
  let user2;
 
  beforeEach(async function () {
    LuckyBallContract = await ethers.getContractFactory("LuckyBall");
    [owner, user1, user2] = await ethers.getSigners();

    contract = await LuckyBallContract.connect(owner).deploy();
    await contract.waitForDeployment();
    
  });

  async function sigFixture() {

    let [ name, version, chainId, verifyingContract ] = await contract.getDomainInfo();
    chainId = parseInt(chainId);
    let deadline = Math.floor(Date.now() / 1000) + 60*60*24; //1day
    let nonce = parseInt(await (contract.nonces(user1.address)));
    let domain = { name, version, chainId, verifyingContract };
    let types = { Relay: [{name: 'owner', type: 'address'},
                          {name: 'deadline', type: 'uint256'},
                          {name: 'nonce', type: 'uint256'} ]};
    let relay = { owner: user1.address, deadline, nonce};
    let sig = splitSig(await user1.signTypedData(domain, types, relay));
    console.log(domain);
    console.log(types);
    console.log(relay);
    console.log(sig);
    return {deadline, nonce, domain, types, relay, sig, contract};
  }

  it("EIP712 signature should pass", async function () {
    let { deadline, nonce, sig, contract } = await loadFixture(sigFixture);
    let verificationResult = await contract.verifySig(user1.address, deadline, nonce, sig.v, sig.r, sig.s);
    expect(verificationResult).to.be.true;
  });  

  it("EIP712 signature should pass", async function () {
    let { deadline, nonce, sig, contract } = await loadFixture(sigFixture);
    let verificationResult2 = await contract.verifySig(user2.address, deadline, nonce, sig.v, sig.r, sig.s);
    expect(verificationResult2).to.be.false;
  });    

});

describe("LuckyBall core", function () {

  let LuckyBallContract;
  let contract;
  let owner;
  let operator;
  let user1;
  let user2;
 
  beforeEach(async function () {
    LuckyBallContract = await ethers.getContractFactory("LuckyBall");
    [owner, operator, user1, user2] = await ethers.getSigners();

    contract = await LuckyBallContract.connect(owner).deploy();
    await contract.waitForDeployment();
    
  });

  async function ballFixture() {
    await contract.connect(owner).setOperator(operator.address);
    await contract.connect(operator).startSeason();
    await contract.connect(operator).issueBalls([user1.address, user2.address],[100,200]);
    return {contract};
  }

  it("setOperator() should set a new operator", async function () {

    await contract.connect(owner).setOperator(operator.address);
    let operatorAddr = await contract.getOperator();
    expect(operatorAddr).to.equal(operator.address);
  
  });

  it("setOperator() should not be executable by other than owner", async function () {
    await expect(contract.connect(user1).setOperator(user2.address)).to.be.revertedWith("LuckyBall: caller is not the owner address!");   

  });  

  it("startSeason() should be executable by owner or operator", async function () {
    await contract.connect(owner).setOperator(operator.address);
    await contract.connect(operator).startSeason();
    let seasonId = await contract.getCurrentSeasionId();
    console.log(seasonId);
    expect(seasonId).to.equal(1);
  });
  
  it("startSeason() should be not executable by other than owner or operator", async function () {
    await expect(contract.connect(user1).startSeason()).to.be.revertedWith("LuckyBall: caller is not the operator address!");
    
  });
  
  it("Season object should hav startBallGroupPos and WinningCode ", async function() {
    await contract.connect(owner).setOperator(operator.address);
    await contract.connect(operator).startSeason();  
    let seasonId = await contract.getCurrentSeasionId();
    let season = await contract.seasons(seasonId);
    //console.log(season); 
    expect(season.slice(0,4)).to.have.ordered.members([ 1n, 0n, 0n, 0n]);
    expect(season[4]).to.be.a('bigint'); //winningCode
    expect(season[4]).to.be.at.least(100000);
    expect(season[4]).to.be.at.below(1000000);
  });

  it("isSeasonActive() should return false when no season is created", async function () {
    expect(await contract.isSeasonActive()).to.be.false;
  });

  it("issueBalls() only allowed for operators", async function () {
    await expect(contract.connect(user1).issueBalls([user1.address],[100])).to.be.revertedWith("LuckyBall: caller is not the operator address!")
  });
  
  it("issueBalls() is not allowed when season is not active", async function () {
    await contract.connect(owner).setOperator(operator.address);
    await expect(contract.connect(operator).issueBalls([user1.address],[100])).to.be.revertedWith("LuckyBall: Season is not active")
  });  

  it("issueBalls() should issue balls to users with qty", async function () {
    //[user1.address, user2.address],[100,200]
    let { contract } = await loadFixture(ballFixture);
    let seasonId = await contract.getCurrentSeasionId();
    let ballCount = await contract.ballCount();
    let user1BallCount = await contract.userBallCounts(user1.address, seasonId);
    let user2BallCount = await contract.userBallCounts(user2.address, seasonId);
    expect(ballCount).to.equal(300);
    expect(user1BallCount).to.equal(100);
    expect(user2BallCount).to.equal(200);
    
  });

  it("issueBalls() should set balls' ownership", async function () {
    //[user1.address, user2.address],[100,200]
    let { contract } = await loadFixture(ballFixture);

    let ball1 = await contract.ownerOf(1);
    let ball100 = await contract.ownerOf(100);
    let ball101 = await contract.ownerOf(101);
    let ball300 = await contract.ownerOf(300);

    expect(ball1).to.equal(user1.address);
    expect(ball100).to.equal(user1.address);
    expect(ball101).to.equal(user2.address); 
    expect(ball300).to.equal(user2.address);       
    
  });

  it("issueBalls() should show 0 address when the ball does not exist", async function () {
    //[user1.address, user2.address],[100,200]
    let { contract } = await loadFixture(ballFixture);
    
    let ball0 = await contract.ownerOf(0);
    let ball1000 = await contract.ownerOf(1000);
    expect(ball0).to.equal('0x0000000000000000000000000000000000000000'); 
    expect(ball1000).to.equal('0x0000000000000000000000000000000000000000');       
  });  


  it("", async function () {
    expect().to.equal();
  });





});