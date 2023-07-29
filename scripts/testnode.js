const hre = require("hardhat");
const axios = require("axios");
const { ethers, upgrades } = require("hardhat");

const gasUrls = {
  polygon:  'https://gasstation.polygon.technology/v2', // Polygon Pos Mainet
  mumbai: 'https://gasstation-testnet.polygon.technology/v2' // Polygon Mumbai
}

const getFeeOption = async () => {
  const data =  (await axios(gasUrls[hre.network.name])).data
  return {
    maxFeePerGas: ethers.parseUnits(Math.ceil(data.fast.maxFee).toString(), 'gwei'),
    maxPriorityFeePerGas: ethers.parseUnits(Math.ceil(data.standard.maxPriorityFee).toString(), 'gwei')
  }
}


let LuckyBallContract;
let contract;
let owner;
let operator;
let user1;
let user2;
let VRFCoordinatorV2Mock;
let vrf;
let beacon;

const main = async () => {
  LuckyBallContract = await ethers.getContractFactory("LuckyBall");
  [owner, operator, user1, user2] = await ethers.getSigners();
  owner.provider.getFeeData = async () => getFeeOption();

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
  console.log('beacon contract deployed at ', await beacon.getAddress());

  contract = await upgrades.deployBeaconProxy(beacon, LuckyBallContract, [subscriptionId, vrfCoordinator, s_keyHash]);
  await contract.waitForDeployment();
  console.log('proxy contract deployed at ', await contract.getAddress());

  await vrf.addConsumer(1, await contract.getAddress());
  console.log('vrf contract deployed at ', await vrf.getAddress());
  return { vrf, contract, beacon };
};


// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
