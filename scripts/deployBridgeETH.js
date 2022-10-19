const fs = require('fs');
const {
	ethers
} = require("hardhat");

async function main() {

	// Add Liquidity libraries
	const [deployer] = await ethers.getSigners();
	console.log(`Deploying contracts with the account: ${deployer.address}`);

	const balance = await deployer.getBalance();
	console.log(`Account ETH balance: ${balance.toString()}`);

	let first = await ethers.getContractFactory('firstToken');
	let firstToken = await first.deploy();

	console.log(`1TH deployed at address: ${firstToken.address}`);

	let second = await ethers.getContractFactory('SecondToken');
	let secondToken = await second.deploy();

	console.log(`2TH deployed at address: ${secondToken.address}`);

	const Bridge = await ethers.getContractFactory('BridgeEth');
	const bridge = await Bridge.deploy(firstToken.address, secondToken.address, deployer.address, deployer.address);

	console.log(`Bridge deployed at address: ${bridge.address}`);

	const dataFirst = {
		address: firstToken.address,
		abi: JSON.parse(firstToken.interface.format('json'))
	};

	const dataSecond = {
		address: secondToken.address,
		abi: JSON.parse(secondToken.interface.format('json'))
	};

	const dataBridge = {
		address: bridge.address,
		abi: JSON.parse(bridge.interface.format('json'))
	};

	fs.writeFileSync('abis/token_first_eth.json', JSON.stringify(dataFirst));
	fs.writeFileSync('abis/token_second_eth.json', JSON.stringify(dataSecond));
	fs.writeFileSync('abis/bridge_eth.json', JSON.stringify(dataBridge));

	try {
		console.log("Verifying First");
		await hre.run("verify:verify", {
			address: firstToken.address,
			constructorArguments: [],
		});
	} catch (e) {
		console.log(e);
		console.log('Already verified');
	}

	try {
		console.log("Verifying Second");
		await hre.run("verify:verify", {
			address: secondToken.address,
			constructorArguments: [],
		});
	} catch (e) {
		console.log(e);
		console.log('Already verified');
	}

	console.log("Verifying bridge");
	await hre.run("verify:verify", {
		address: bridge.address,
		constructorArguments: [
			firstToken.address, secondToken.address, deployer.address, deployer.address
		],
	})

	console.log('done');
}

main()
	.then(() => process.exit(0))
	.catch(error => {
		console.error(error);
		process.exit(1);
	});