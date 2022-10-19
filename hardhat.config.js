/**
 * @type import('hardhat/config').HardhatUserConfig
 */
 require('@nomiclabs/hardhat-waffle');
 require('dotenv').config({path: __dirname + '/.env'});
 require("@nomiclabs/hardhat-etherscan");
 require('hardhat-contract-sizer');
 require('./tasks/process_bsc_transactions');
 require('./tasks/process_eth_transactions');

 
 task('accounts', "Print all accounts").setAction(async () => {
     const accounts = await ethers.getSigners();
 
     for (const account of accounts) {
         console.log(account.address);
     }
 })
 
 module.exports = {
     solidity: {
         settings: {
             optimizer: {
                 enabled: true,
                 runs: 200,
             }
         },
         compilers: [
             {
                 version: "0.6.12",
             },
             {
                 version: "0.5.0",
             },
             {
                 version: "0.6.2",
             },
             {
                 version: "0.8.0",
             },
             {
                 version: "0.8.7",
             },
             {
                 version: "0.8.13",
             }
         ],
     },
     networks: {
         eth_testnet: {
             url: process.env.ENDPOINT_WSS_ETH_RINKBY_TESTNET,
             accounts: ['0x' + process.env.PRIVATE_KEY],
         },
         bsc_testnet: {
             url: process.env.ENDPOINT_WSS_BSC_TESTNET,
             accounts: ['0x' + process.env.PRIVATE_KEY]
         }
     },
     etherscan: {
         apiKey: ""
     }
 };