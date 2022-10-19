const task = require("hardhat/config").task;
const fs = require("fs");

const firstToken_eth = process.env.FIRST_TOKEN_ADDRESS_ETH;
const secondToken_eth = process.env.SECOND_TOKEN_ADDRESS_ETH;
const firstToken_bsc = process.env.FIRST_TOKEN_ADDRESS_BSC;
const secondToken_bsc = process.env.SECOND_TOKEN_ADDRESS_BSC;

function changeToken(token) {

    if (token != secondToken_bsc &&
        token != secondToken_eth &&
        token != firstToken_eth &&
        token != firstToken_bsc) {
        throw new Error('Invalid token');
    }

    if (token === firstToken_eth) {
        return firstToken_bsc;
    }
    if (token === firstToken_bsc) {
        return firstToken_eth;
    }
    if (token === secondToken_eth) {
        return secondToken_bsc;
    }
    if (token === secondToken_bsc) {
        return secondToken_eth;
    }
}

task("process-eth-to-bsc", "Will process all transactions from ETH to bsc")
  .setAction(async (taskArgs, hre) => {
    const ethers = hre.ethers;

    const bridgeBsc = await (await ethers.getContractFactory("BridgeBsc")).attach(process.env.BRIDGE_ADDRESS_BSC);
    const [owner] = await ethers.getSigners();
  
    const db = require('better-sqlite3')('./bridge.db');

    //later today
    let rows = db.prepare("SELECT * FROM transfers where processed = 'false' and blockchain = 'bsc'").all();
    const stmt = db.prepare("update transfers set processed = ? where blockchain = 'bsc' and id = ?");
   
    
    for (const row of rows) {
        try{
            let tokenToRelease = changeToken(row.token);
            console.log('Trying to release ' + tokenToRelease + ' from ' + row.sender);
            await bridgeBsc.release(tokenToRelease, row.sender, row.amount, row.nonce);
            stmt.run(['true', row.id]);
        } catch(e) {
            if(e['error'] == 'ProviderError: execution reverted: Bridge: Transaction processed.') {
                console.log('Transaction processed.');
                stmt.run(['true', row.id]);
            }else{
                console.log(e['error'])
                stmt.run(['false', row.id]);
            }            
        }
    }

  });
