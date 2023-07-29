// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
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

async function main() {
  const subscriptionId = 5320; //https://vrf.chain.link/
  const vrfCoordinator = "0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed"; //Mumbai 
  const keyHash = "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f";

  LuckyBallContract = await ethers.getContractFactory("LuckyBall");
  LuckyBallContract.runner.provider.getFeeData = async () => await getFeeOption()
  const [signer] = await ethers.getSigners();
  signer.provider.getFeeData = async () => await getFeeOption();
  LuckyBallContract.connect(signer);


  //let s_keyHash = "0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc";   

  //beacon proxy
  console.log('network: ', hre.network.name);
  const beacon = await upgrades.deployBeacon(LuckyBallContract);
  await beacon.waitForDeployment();
  console.log('beacon contract deployed at ', await beacon.getAddress());
  const proxy = await upgrades.deployBeaconProxy(beacon, LuckyBallContract, [subscriptionId, vrfCoordinator, keyHash]);
  await proxy.waitForDeployment();
  console.log('proxy contract deployed at ', await proxy.getAddress());
  const implementation = await beacon.implementation()
  console.log('implementation contract deployed at ', implementation);
  await hre.run("verify:verify", { address: implementation });

}

async function upgrade(beaconAddr, proxyAddr) {
  const ContractV2 = await ethers.getContractFactory("LuckyBallV2");
  const beacon = await upgrades.upgradeBeacon(beaconAddr, ContractV2);
  const contract2 = ContractV2.attach(proxyAddr);
  console.log('New implementation address is ', await beacon.implementation());h
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
