#!/bin/sh

echo "Running BSC->ETH";
cd /home/ubuntu/bridge && npx hardhat run scripts/import-from-bsc.js --network bsc_testnet && npx hardhat process-bsc-to-eth --network eth_testnet

echo "Running ETH->BSC";
cd /home/ubuntu/bridge && npx hardhat run scripts/import-from-eth.js --network eth_testnet && npx hardhat process-eth-to-bsc --network bsc_testnet


