// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { ethers, upgrades } = require("hardhat");

const getFeeOption = async () => {
  const feeData =  await provider.getFeeData()
  const maxFeePerGas = feeData.maxFeePerGas + ethers.parseUnits('5', 'gwei')
  const maxPriorityFeePerGas = feeData.maxPriorityFeePerGas + ethers.parseUnits('3', 'gwei')
  return { maxFeePerGas, maxPriorityFeePerGas }
}

async function main() {
  const subscriptionId = 5320; //https://vrf.chain.link/
  const vrfCoordinator = "0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed"; //Mumbai 
  const keyHash = "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f";

  LuckyBallContract = await ethers.getContractFactory("LuckyBall");
  const { owner } = await ethers.getSigners();

  //let s_keyHash = "0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc";   

  //beacon proxy
  const beacon = await upgrades.deployBeacon(LuckyBallContract);
  await beacon.waitForDeployment();
  console.log('beacon contract deployed at ', await beacon.getAddress());
  const proxy = await upgrades.deployBeaconProxy(beacon, LuckyBallContract, [subscriptionId, vrfCoordinator, keyHash]);
  await proxy.waitForDeployment();
  console.log('proxy contract deployed at ', await proxy.getAddress());
  console.log('implementation contract deployed at ', await beacon.implementation());
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
