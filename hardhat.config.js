require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');
require('dotenv').config()

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      accounts: {
        mnemonic: process.env.MNEMONIC
      }
    },
    
    sepolia: {
      url: 'https://eth-sepolia.g.alchemy.com/v2/' + process.env.ALCHEMY_API_KEY,
      accounts: {
        mnemonic: process.env.MNEMONIC,
      }
    },
    mumbai: {
      url: 'https://polygon-mumbai.g.alchemy.com/v2/' + process.env.ALCHEMY_API_KEY,
      accounts: {
        mnemonic: process.env.MNEMONIC,
      }
    },
    ganache: {
      url: "http://127.0.0.1:8545",
    }    
  },
  etherscan: {
    apiKey: {
      //polygon
      polygon: process.env.POLYGONSCAN_API_KEY,
      polygonMumbai: process.env.POLYGONSCAN_API_KEY,
      mumbai: process.env.POLYGONSCAN_API_KEY,

      //ethereum
      mainet: process.env.ETHERSCAN_API_KEY,
      sepolia: process.env.ETHERSCAN_API_KEY,
    },
    customChains: [
      {
        network: "polygonMumbai",
        chainId: 80001,
        urls: {
          apiURL: "https://api-testnet.polygonscan.com/api",
          browserURL: "https://mumbai.polygonscan.com"
        }
      }
    ] 
  }
};

