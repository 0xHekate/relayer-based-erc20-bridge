# Simple relayer based ERC20 Bridge

This project demonstrates a basic token bridge, using a relayer between different EVM blockchains, this bridge supports up to two tokens and will lock tokens in one blockchain and unlock it over another network, careful, the current setup uses a few private keys for different roles in the bridge as unlocker, pauser and owner, ideally this should be setup for a series of multisig wallets to avoid key leakage. Beware using the code in production be sure your keys are properly stored and safe.

This code could be widely improved by using typescript and having a few setup classes, this is intended more as a simple demonstration.

Setup your hardhat config with testnet keys, use the deployment scripts to deploy and verify your contracts, switch to proper user and set **./bridge.sh** to run on cron or pm2 every 2 minutes.


Try running some of the following tasks:
```shell
npm install
./bridge.sh
```

The bridge works with a relayer set watching an event on both networks, once the event is catched, the user account is credited, that allows for a user to claim a specific amount of tokens. 

the smart-contract has several built-in security-focused parameters those are:

* maximumTransferAmount - max amount per transfer.
* dailyTransferLimit - daily transfer limit, if the user requests more the transaction is reverted.

No ownership transfering functions are built-in, if built we recommend to set a 24 hour time-block beforing transfering ownership

The bridge collects and send fees to the operator account so it there's no need to keep refuiling the account with gas-tokens. The fee release window, must be calculated considering a reasonable amount on Bsc we recommend 0.1 BNB and on ETH the value can be set in dollars using the function **setMinimumUsdFee**, The recomended the first deposit to the bridge operator to be 0.2 ETH and 0.5 BNB


