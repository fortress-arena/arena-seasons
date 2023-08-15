const chai = require("chai");
const { ethers, upgrades } = require("hardhat");
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

describe("LuckyBall core", function () {

  let LuckyBallContract;
  let contract;
  let owner;
  let operator;
  let user1;
  let user2;
  let VRFCoordinatorV2Mock;
  let vrf;
  let beacon;
 
  beforeEach(async function () {
    LuckyBallContract = await ethers.getContractFactory("LuckyBall");
    [owner, operator, user1, user2] = await ethers.getSigners();

    //let s_subscriptionId = 5320; //https://vrf.chain.link/
    //let vrfCoordinator = "0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed"; //Mumbai 
    //let s_keyHash = "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f";
    //let s_keyHash = "0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc";   

    //vrf setup
    VRFCoordinatorV2Mock = await ethers.getContractFactory("VRFCoordinatorV2Mock");
    let _BASEFEE = 100000000000000000n;
    let _GASPRICELINK= 1000000000;
    vrf = await VRFCoordinatorV2Mock.connect(owner).deploy(_BASEFEE, _GASPRICELINK);
    await vrf.waitForDeployment();    
    await vrf.createSubscription();
    let subscriptionId =  1;  
    await vrf.connect(owner).fundSubscription(1, 100000000000000000000000n);
    let vrfCoordinator= vrf.target;
    let s_keyHash = "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f";

    //beacon proxy
    beacon = await upgrades.deployBeacon(LuckyBallContract);
    await beacon.waitForDeployment();
    contract = await upgrades.deployBeaconProxy(beacon, LuckyBallContract, [subscriptionId, vrfCoordinator, s_keyHash]);
    await contract.waitForDeployment();
    //contract = await LuckyBallContract.connect(owner).deploy(subscriptionId, vrfCoordinator, s_keyHash);
    //await contract.waitForDeployment();
    //console.log(await contract.getAddress());
    //console.log((await contract.getDomainInfo()));
    await vrf.addConsumer(1, await contract.getAddress());
    return { vrf, contract, beacon };
  });

  async function ballFixture() {
    await contract.connect(owner).setOperator(operator.address);
    await contract.connect(operator).startSeason();
    await contract.connect(operator).issueBalls([user1.address, user2.address],[100,200]);
    return { contract };
  }

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
    //console.log(domain);
    //console.log(types);
    //console.log(relay);
    //console.log(sig);
    return {deadline, nonce, domain, types, relay, sig, contract};
  }

  it("EIP712 signature should pass", async function () {
    let { deadline, nonce, sig, contract } = await loadFixture(sigFixture);
    let verificationResult = await contract.verifySig(user1.address, deadline, nonce, sig.v, sig.r, sig.s);
    expect(verificationResult).to.be.true;
  });  

  it("EIP712 signature should fail with wrong address", async function () {
    let { deadline, nonce, sig, contract } = await loadFixture(sigFixture);
    let verificationResult2 = await contract.verifySig(user2.address, deadline, nonce, sig.v, sig.r, sig.s);
    expect(verificationResult2).to.be.false;
  });  

  it("transferOwner() should set a new owner", async function () {

    await contract.connect(owner).transferOwner(operator.address);
    let operatorAddr = await contract.getOwner();
    expect(operatorAddr).to.equal(operator.address);
  
  });

  it("setOperator() should set a new operator", async function () {

    await contract.connect(owner).setOperator(operator.address);
    let operatorAddr = await contract.getOperator();
    expect(operatorAddr).to.equal(operator.address);
  
  });

  it("setOperator() should not be executable by other than owner", async function () {
    await expect(contract.connect(user1).setOperator(user2.address)).to.be.revertedWith("LuckyBall: caller is not the owner address!");   

  });  

  it("transferOwner() should not be executable by other than owner", async function () {
    await expect(contract.connect(user1).transferOwner(user2.address)).to.be.revertedWith("LuckyBall: caller is not the owner address!");   

  });    

  it("startSeason() should be executable by owner or operator", async function () {
    await contract.connect(owner).setOperator(operator.address);
    await expect(contract.connect(operator).startSeason())
    .to.emit(contract, 'SeasonStarted');

    let seasonId = await contract.getCurrentSeasonId();
    console.log(seasonId);
    expect(seasonId).to.equal(1);
  });
  
  it("startSeason() should be not executable by other than owner or operator", async function () {
    await expect(contract.connect(user1).startSeason())
    .to.be.revertedWith("LuckyBall: caller is not the operator address!");
    
  });

  it("startSeason() should be reverted when the current season is not ended", async function() {
    let { contract } = await loadFixture(ballFixture);
    await contract.connect(user1).requestReveal();
    await expect(contract.connect(operator).startSeason())
    .to.be.revertedWith("LuckyBall: the current season should be ended first");
  });

  it("startSeason() should work after the current season is ended", async function() {
    await contract.connect(owner).setOperator(operator.address);
    await contract.connect(operator).startSeason();
    await contract.connect(operator).issueBalls([user1.address],[100]);
    await contract.connect(user1).requestReveal();
    await contract.connect(operator).requestRevealGroupSeed();
    let requestId = await contract.lastRequestId();
    console.log(requestId);
    await vrf.connect(owner).fulfillRandomWords(requestId, contract.target);
    //await contract.setRevealGroupSeed(1);
    console.log('revealNeeded: ', await contract.revealNeeded());
    //console.log(await contract.getRevealGroup(1));
    //console.log(await contract.getBallCode(1));
    //console.log(await contract.s_requests(requestId));

    await contract.connect(operator).endSeason();
    let requestId2 = await contract.lastRequestId();
    console.log('req2: ', requestId2)
    await vrf.connect(owner).fulfillRandomWords(requestId2, contract.target);
    await contract.connect(operator).startSeason();
    let newSeasonId = await contract.getCurrentSeasonId();
    expect(newSeasonId).to.equal(2);
  });
  
  it("Season object should hav startBallId and WinningCode ", async function() {
    await contract.connect(owner).setOperator(operator.address);
    await contract.connect(operator).startSeason();  
    let seasonId = await contract.getCurrentSeasonId();
    let season = await contract.seasons(seasonId);
    //console.log(season); 
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
    let seasonId = await contract.getCurrentSeasonId();
    let ballCount = await contract.ballCount();
    let user1BallCount = await contract.getUserBallCount(user1.address, seasonId);
    let user2BallCount = await contract.getUserBallCount(user2.address, seasonId);
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

  it("getBalls() should show all balls by user address and seasonId ", async function () {
    let { contract } = await loadFixture(ballFixture);  
    let seasonId = await contract.getCurrentSeasonId();  
    let balls = await contract.getBalls(user1.address, seasonId);
    expect(balls.length).to.equal(100);
  });

  it("getBallCode() should show 0 code when reveal is not done", async function () {
    let { contract } = await loadFixture(ballFixture);
    let ball1 = await contract.getBallCode(1);
    let ball2 = await contract.getBallCode(2);

    expect(ball1).to.equal(0);
    expect(ball2).to.equal(0);

  });

  it("getBallCode() should show code when reveal is done", async function () {

    await contract.connect(owner).setOperator(operator.address);
    await contract.connect(operator).startSeason();
    await contract.connect(operator).issueBalls([user1.address],[100]);
    await contract.connect(user1).requestReveal();
    await contract.connect(operator).requestRevealGroupSeed();
    let requestId = await contract.lastRequestId();
    //console.log(requestId);
    await vrf.connect(owner).fulfillRandomWords(requestId, contract.target);
    //await contract.setRevealGroupSeed(1);
    //console.log('revealNeeded: ', await contract.revealNeeded());
    //console.log(await contract.getRevealGroup(1));
    //console.log(await contract.getBallCode(1));
    //console.log(await contract.s_requests(requestId));

    expect(await contract.getBallCode(1)).to.be.at.least(100000);
    expect(await contract.getBallCode(1)).to.be.at.below(1000000);

  });  

  it("requestReveal() should accept reveal request", async function () {
    let { contract } = await loadFixture(ballFixture);
    let seasonId = await contract.getCurrentSeasonId();    
    await expect(contract.connect(user1).requestReveal())
    .to.emit(contract, "RevealRequested")
    .withArgs(seasonId, 1, user1.address, 100);

    let revealGroup = await contract.getRevealGroup(1);
    let revealGroup2 = await contract.getRevealGroup(101);
    expect(revealGroup).to.equal(1);
    expect(revealGroup2).to.equal(0); //not requested
    await expect(contract.getRevealGroup(1000)).to.be.revertedWith('LuckyBall: ballId is out of range');
  });

  it("requestReveal() should accept multiple reveal request", async function () {
    let { contract } = await loadFixture(ballFixture);
    await contract.connect(user1).requestReveal();
    let revealGroup = await contract.getRevealGroup(1);
    expect(revealGroup).to.equal(1);

    await contract.connect(operator).issueBalls([user1.address],[100]);

    let revealGroup400 = await contract.getRevealGroup(400);
    expect(revealGroup400).to.equal(0);
    
    await contract.connect(user1).requestReveal();
    //let userBallGroups = await contract.getUserBallGroups(user1.address, 1);
    //console.log(await contract.ballCount());
    //console.log(await contract.newRevealPos(user1.address));
    //console.log(userBallGroups);
    let revealGroup400_again = await contract.getRevealGroup(400);
    expect(revealGroup400_again).to.equal(1);
  });  

  it("requestReveal() should udpate ballPosByRevealGroup", async function () {
        //[user1.address, user2.address],[100,200]
    let { contract } = await loadFixture(ballFixture);
    let revealGroupId = await contract.getCurrentRevealGroupId();
    console.log('rGroupID:', revealGroupId);
    await contract.connect(user2).requestReveal()
    let revealGroupBalls = await contract.getBallsByRevealGroup(revealGroupId);
    //console.log(revealGroupBalls);
    expect(revealGroupBalls.length).to.equal(200);
    expect(revealGroupBalls[0]).to.equal(101);
    expect(revealGroupBalls[199]).to.equal(300);
  });


  it("relayRequestReveal() should relay with sig verification", async function () {
    let { deadline, nonce, sig, contract } = await loadFixture(sigFixture);
    await contract.connect(owner).startSeason();
    await contract.connect(owner).issueBalls([user1.address],[100]);
    expect(await contract.getRevealGroup(1)).to.equal(0);
    await contract.connect(user2).relayRequestReveal(
        user1.address, 
        deadline,
        sig.v,
        sig.r,
        sig.s);
    expect(await contract.getRevealGroup(1)).to.equal(1);
  });

  it("relayRequestReveal() should fail when deadline passed", async function () {
    let { deadline, nonce, sig, contract } = await loadFixture(sigFixture);
    await contract.connect(owner).startSeason();
    await contract.connect(owner).issueBalls([user1.address],[100]);
    expect(await contract.getRevealGroup(1)).to.equal(0);
    time.increaseTo(deadline + 1);
    await expect(contract.connect(user2).relayRequestReveal(
        user1.address, 
        deadline,
        sig.v,
        sig.r,
        sig.s)).to.be.revertedWith('LuckyBall: expired deadline');
  });  

  it("requestRevealGroupSeed() should call chainkLink", async function () {
    //let { vrf, contract } = await loadFixture(vrfFixture);
    await contract.connect(owner).setOperator(operator.address);
    await contract.connect(operator).startSeason();
    await contract.connect(operator).issueBalls([user1.address],[100]);
    await contract.connect(user1).requestReveal();
    await contract.connect(operator).requestRevealGroupSeed();
    let requestId = await contract.lastRequestId();
    console.log(requestId);
    await vrf.connect(owner).fulfillRandomWords(requestId, contract.target);
    //await contract.setRevealGroupSeed(1);
    //console.log(await contract.revealNeeded());
    //console.log(await contract.getRevealGroup(1));
    //console.log(await contract.getBallCode(1));
    //console.log(await contract.s_requests(requestId));

    expect(await contract.getBallCode(1)).to.be.at.least(100000);
    expect(await contract.getBallCode(1)).to.be.at.below(1000000);
  });

  it("endSeason() should end the current season, and then startSeason() should work", async function () {

    await contract.connect(owner).setOperator(operator.address);
    await contract.connect(operator).startSeason();
    await contract.connect(operator).issueBalls([user1.address, user2.address],[100,200]);
    await contract.connect(user1).requestReveal();
    await contract.connect(user2).requestReveal();
    await contract.connect(operator).requestRevealGroupSeed();    
    let requestId = await contract.lastRequestId();
    await vrf.connect(owner).fulfillRandomWords(requestId, contract.target);
    await contract.connect(operator).endSeason();
    let requestId2 = await contract.lastRequestId();   
    await vrf.connect(owner).fulfillRandomWords(requestId2, contract.target); 
    //console.log(await contract.s_requests(1));
    //console.log(await contract.s_requests(2));
    //console.log(await contract.seasons(1));
    await contract.connect(operator).startSeason();
    await contract.connect(operator).issueBalls([user1.address, user2.address],[100,200]);
    await contract.connect(user1).requestReveal();
    await contract.connect(user2).requestReveal();
    await contract.connect(operator).requestRevealGroupSeed();    
    requestId = await contract.lastRequestId();
    await vrf.connect(owner).fulfillRandomWords(requestId, contract.target);
    await contract.connect(operator).endSeason();
    requestId2 = await contract.lastRequestId();   
    await vrf.connect(owner).fulfillRandomWords(requestId2, contract.target); 

    let seasonId = await contract.getCurrentSeasonId();

    expect(seasonId).to.equal(2);
  });
  
  it("An upgrade version should work with the same proxy ", async function () {
    const ContractV2 = await ethers.getContractFactory("LuckyBallV2");
    await upgrades.upgradeBeacon(await beacon.getAddress(), ContractV2);
    const contract2 = ContractV2.attach(await contract.getAddress());
    expect(await contract2.getAddress()).to.equal(await contract.getAddress());
    expect(await contract2.getVersion()).to.equal("2");
  });
  
});