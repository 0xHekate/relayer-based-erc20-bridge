//listen to contract events using ethers.js
//listen to contract events using ethers.js
const { ethers } = require("hardhat");
const BridgeBsc = require('../abis/bridge_bsc.json');
const fs = require("fs");
const sqlite3 = require('sqlite3').verbose();


/**
 * CREATE TABLE "transfers" (
	"id"	INTEGER NOT NULL,
	"sender"	TEXT NOT NULL,
	"token"	TEXT NOT NULL,
	"amount"	TEXT NOT NULL DEFAULT 0,
	"nonce"	TEXT NOT NULL,
	"processed"	INTEGER NOT NULL DEFAULT 0,
	"blockchain"	TEXT,
	PRIMARY KEY("id")
);
 */

require('dotenv').config({
    path: '/home/ubuntu/bridge/.env'
});


async function main() {

    const latestBlock = await hre.ethers.provider.getBlock("latest");

    console.log(`latestBlock: ${latestBlock.number}`);

    const bridgeEth = await (await ethers.getContractFactory("BridgeEth")).attach(process.env.BRIDGE_ADDRESS_ETH);

    const db = require('better-sqlite3')('./bridge.db');

    //run count query
    let count = db.prepare("SELECT count(*) as total FROM transfers where blockchain = 'bsc'").get();

    processFrom = count.total;

    let keepProcessing = true;
    let startRow = readLastBlock();

    let endRow = latestBlock.number;

    const stmt = db.prepare('INSERT INTO transfers (blockchain, sender, token, amount, nonce, processed) VALUES (?, ?, ?, ?, ?, ?)');

    while (keepProcessing) {
        let targetRow = startRow + 2000;
        console.log(`startRow: ${startRow} endRow: ${endRow} targetRow: ${targetRow}`);

        let bscFilter = bridgeEth.filters.BridgeTransfer();
        let bscEvents = await bridgeEth.queryFilter(bscFilter, startRow, targetRow);

        for(const e of bscEvents) {

            const {
                token,
                from,
                to,
                amount,
                date,
                nonce
            } = e.args;
        
            const foundItem = db.prepare('select * from transfers where blockchain = ? and nonce = ?').get('bsc', nonce.toString())
            
            if(foundItem) {
                console.log('Skipping processed row on ETH');
                continue;
            }else{
                stmt.run(['bsc', from, token, amount.toString(), nonce.toString(), 'false']);
                await writeLastBlock(e.blockNumber);
                console.log(`processing item from block ${e.blockNumber} -> ETH`);
            }
        }

        if(targetRow >= endRow) {
            keepProcessing = false;
        }else{
            startRow = targetRow;
        }
    }
};

main()
.then(() => process.exit(0))
.catch(error => {
    console.error(error);
    process.exit(1);
});


//function to write json file with last processed block
async function writeLastBlock(blockNumber) {
    let data = JSON.stringify({block:blockNumber}, null, 2);
    await fs.writeFileSync('/home/ubuntu/bridge/last_processed_block_eth.json', data, (err) => {
        if (err) throw err;
        console.log('Data written to file');
    });
}

//function to read json file with last processed nonce
function readLastBlock() {
    try {
        let processedBlocksFile = JSON.parse(fs.readFileSync('/home/ubuntu/bridge/last_processed_block_eth.json'));
        return processedBlocksFile.block;   
    } catch (error) {
        console.log(error);
    }
}