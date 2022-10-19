//SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/** @title This bridge operates on the Binance Smart Chain blockchain. It locks BabyDoge, initiated by a user,
    * and subject to a flat fee in BNB and a percentage fee in BabyDoge. Unlock is initiated through an external bot and
    * processed on a different blockchain.
    */
contract BridgeEth is Ownable, ReentrancyGuard {
    uint256 public nonce;
    uint256 minimumUSD = 10 * 10 ** 18;
    uint256 public feeReleaseThreshold = 0.1 ether;
    mapping(IERC20 => TokenConfig) private _tokenConfig;
    mapping(IERC20 => mapping(address => uint256)) private _balances;
    mapping(uint256 => bool) private _processedNonces;
    IERC20 private _firstToken;
    IERC20 private _secondToken;
    bool public paused = false;
    address payable private _unlocker_bot;
    address private _pauser_bot;
    uint256 constant private DAILY_TRANSFER_INTERVAL_ONE_DAY = 86400;
    uint256 private _dailyTransferNextTimestamp = block.timestamp + DAILY_TRANSFER_INTERVAL_ONE_DAY;
    address private _newProposedOwner;
    uint256 private _newOwnerConfirmationTimestamp = block.timestamp;

    enum ErrorType {UnexpectedRequest, NoBalanceRequest, MigrateBridge}

    event BridgeTransfer(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 date,
        uint256 nonce
    );

    event BridgeTokensUnlocked(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 date
    );

    event FeesReleasedToOwner(
        uint256 amount,
        uint256 date
    );

    struct TokenConfig{
        uint256 maximumTransferAmount;
        uint256 collectedFees;
        uint256 unlockTokenPercentageFee;
        uint256 dailyLockTotal;
        uint256 dailyWithdrawTotal;
        uint256 dailyTransferLimit;
        bool exists;
    }

    event UnexpectedRequest(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 date,
        ErrorType indexed error
    );

    /** @dev Creates a cross-blockchain bridge.
      * @param firstToken -- BEP20 token to bridge.
      * @param secondToken -- BEP20 token to bridge.
      * @param unlockerBot -- address of account that mints/burns.
      * @param pauserBot -- address of account that pauses bridge in emergencies.
      */
    constructor(address firstToken, address secondToken, address payable unlockerBot, address pauserBot) {
        require(firstToken!=address(0) && secondToken!=address(0) && unlockerBot != address(0) && pauserBot!= address(0) );
        _unlocker_bot = unlockerBot;
        _pauser_bot = pauserBot;
        _firstToken = IERC20(firstToken);
        _secondToken = IERC20(secondToken);
        configTokens();
    }

    function configTokens() internal{

        _tokenConfig[_firstToken] = TokenConfig({
            maximumTransferAmount :500000000000000000000000,
            collectedFees:0,
            unlockTokenPercentageFee:0,
            dailyLockTotal:0,
            dailyWithdrawTotal:0,
            dailyTransferLimit:4000000000000000000000000,
            exists:true
        });

        _tokenConfig[_secondToken] = TokenConfig({
            maximumTransferAmount:220000000000000000000000,
            collectedFees:0,
            unlockTokenPercentageFee:0,
            dailyLockTotal:0,
            dailyWithdrawTotal:0,
            dailyTransferLimit:8000000000000000000000000000,
            exists:true
        });
    }  

    modifier Pausable() {
        require( !paused, "Bridge: Paused.");
        _;
    }

    modifier OnlyUnlocker() {
        require(msg.sender == _unlocker_bot, "Bridge: You can't call this function.");
        _;
    }

    modifier OnlyPauserAndOwner() {
        require((msg.sender == _pauser_bot || msg.sender == owner()), "Bridge: You can't call this function.");
        _;
    }

    modifier onlyKnownTokens(IERC20 token) {
        require(
            address(token) == address(_secondToken) || 
            address(token) == address(_firstToken), "Bridge: Token not authorized.");
        _;
    }

    function resetTransferCounter(IERC20 token) internal {
        _dailyTransferNextTimestamp = block.timestamp + DAILY_TRANSFER_INTERVAL_ONE_DAY;
        TokenConfig storage config = _tokenConfig[token];
        config.dailyLockTotal = 0;
        config.dailyWithdrawTotal = 0;
    }

    /** @dev Locks tokens to bridge. External bot initiates unlock on other blockchain.
      * @param amount -- Amount of BabyDoge to lock.
      */
    function lock(IERC20 token, uint256 amount) external onlyKnownTokens(token) Pausable {
        address sender = msg.sender;
        require(_tokenConfig[token].exists == true, "Bridge: access denied.");
        require(token.balanceOf(sender) >= amount, "Bridge: Account has insufficient balance.");
        TokenConfig storage config = _tokenConfig[token];
        require(amount <= config.maximumTransferAmount, "Bridge: Please reduce the amount of tokens.");

        if (block.timestamp >= _dailyTransferNextTimestamp) {
            resetTransferCounter(token);
        }

        config.dailyLockTotal = config.dailyLockTotal + amount;

        if(config.dailyLockTotal > config.dailyTransferLimit) {
            revert("Bridge: Daily transfer limit reached.");
        }

        require(token.transferFrom(sender, address(this), amount), "Bridge: Transfer failed.");

        emit BridgeTransfer(
            address(token),
            sender,
            address(this),
            amount,
            block.timestamp,
            nonce
        );
        
        nonce++;
    }

    // Verificar limite transacao
    function release(IERC20 token, address to, uint256 amount, uint256 otherChainNonce) 
    external OnlyUnlocker() onlyKnownTokens(token) Pausable {
        require(!_processedNonces[otherChainNonce], "Bridge: Transaction processed.");
        require(to!= address(0), "Bridge: access denied.");
        TokenConfig storage config = _tokenConfig[token];
        require(amount <= config.maximumTransferAmount, "Bridge: Transfer blocked.");
        _processedNonces[otherChainNonce] = true;

        _balances[token][to] = _balances[token][to] + amount; 
    }

    function getPrice() public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(0x8A753747A1Fa494EC906cE90E9f37563A8AF630e);
        (,int256 answer,,,) = priceFeed.latestRoundData();
        return uint256(answer * 10000000000);
    } 

    function getConversionRate(uint256 ethAmount) public view returns (uint256 ethAmountInUsd){ //wei unit
        uint256 ethPrice = getPrice();
        return (ethPrice*ethAmount) / 1000000000000000000; // otherwise 18 + 18 = 36 decimal - need to remove 18 decimal
    }

    function getFee() view public returns (uint256 result) {
        uint256 ethPrice = getPrice();
        return (((minimumUSD*100000000000000000000) / ethPrice))/100; 
    }
    
    function withdraw(IERC20 token) external onlyKnownTokens(token) payable Pausable {
        require(getConversionRate(msg.value) >= getFee(), "You need to spend more ETH"); // otherwise reverts
        address claimer = msg.sender;
        uint256 claimerBalance = _balances[token][claimer];
        require(claimerBalance > 0, "Bridge: No balance.");
    
        TokenConfig storage config = _tokenConfig[token];

        if (block.timestamp >= _dailyTransferNextTimestamp) {
            resetTransferCounter(token);
        }

        config.dailyWithdrawTotal = config.dailyWithdrawTotal + claimerBalance;

        if(config.dailyWithdrawTotal > config.dailyTransferLimit) {
            revert("Bridge: Daily transfer limit reached.");
        }

        if(claimerBalance > token.balanceOf(address(this))) {
            revert('Bridge: No funds in the bridge.');
        }

        if (claimerBalance >= config.dailyTransferLimit) {
            pauseBridge(msg.sender, address(this), claimerBalance);
            revert('Bridge: Paused.');
        }

        if (address(this).balance >= feeReleaseThreshold) {
            uint256 amountReleased = address(this).balance;
            (bool success, ) = _unlocker_bot.call{value : amountReleased}("Releasing fee to unlocker");
            require(success, "Transfer failed.");
            emit FeesReleasedToOwner(amountReleased, block.timestamp);
        }

        _balances[token][claimer] = _balances[token][claimer] - claimerBalance;

        if (config.unlockTokenPercentageFee > 0) {
            uint256 amountFee = (claimerBalance * config.unlockTokenPercentageFee) / 100;
            claimerBalance = claimerBalance - amountFee;
            config.collectedFees = config.collectedFees + amountFee;
        }
        
        require(token.transfer(claimer, claimerBalance), "Bridge: Transfer failed");
        
        emit BridgeTokensUnlocked(address(token), address(this), msg.sender, claimerBalance, block.timestamp);
    } 
 
    function getBalance(IERC20 token) public view onlyKnownTokens(token) returns (uint256 balance) {
        return _balances[token][msg.sender];
    }

    function getTokenConfig(IERC20 token) public view onlyKnownTokens(token) returns (TokenConfig memory) {
        return _tokenConfig[token];
    }

    function setTokenConfig(
        IERC20 token, 
        uint256 maximumTransferAmount, 
        uint256 unlockTokenPercentageFee,
        uint256 dailyTransferLimit) external onlyKnownTokens(token) onlyOwner() {
            TokenConfig storage config = _tokenConfig[token];   
            config.maximumTransferAmount = maximumTransferAmount;
            config.unlockTokenPercentageFee = unlockTokenPercentageFee;
            config.dailyTransferLimit = dailyTransferLimit;
    }

    function resetDailyTotals(IERC20 token) external onlyKnownTokens(token) onlyOwner() {
        resetTransferCounter(token);
    }

    function setMinimumUsdFee(uint256 usd) external onlyOwner() {
        require(usd > 0, "Can't be zero");
        minimumUSD = usd * 10 ** 18;
    }

    function setTokenPercentageFee(IERC20 token, uint256 tokenFee) external onlyOwner() onlyKnownTokens(token) {
        require(tokenFee < 25, "Bridge: Gotta be smaller then 25") ;
        TokenConfig storage config = _tokenConfig[token];   
        require(config.exists, "Bridge: Token not found");
        config.unlockTokenPercentageFee = tokenFee;
    }

    function setFeeReleaseThreshold(uint256 amount) external onlyOwner() {
        require(amount > 0, "Bridge: Can't be zero");
        feeReleaseThreshold = amount;
    }

    function withdrawEth() external onlyOwner() {
        uint256 amountReleased = address(this).balance;
        (bool success, ) = owner().call{value : amountReleased}("Releasing eth to owner");
        require(success, "Transfer failed");
    }

    function withdrawERC20(IERC20 token) external onlyOwner() nonReentrant {
        require(address(token) != address(0), "Bridge: Can't be zero");
        require(token.balanceOf(address(this)) >= 0, "Bridge: Account has insufficient balance.");
        require(token.transfer(owner(), token.balanceOf(address(this))), "Bridge: Transfer failed.");
    }

    function withdrawCollectedFees(IERC20 token) external onlyOwner() onlyKnownTokens(token) nonReentrant {
        TokenConfig storage config = _tokenConfig[token];   
        require(config.exists, "Bridge: Token not found");
        require(token.balanceOf(address(this)) >= config.collectedFees, "Bridge: Account has insufficient balance.");
        require(token.transfer(owner(), config.collectedFees), "Bridge: Transfer failed.");
        config.collectedFees = 0;
    }

    function setUnlocker(address _unlocker) external onlyOwner {
        require(_unlocker != _unlocker_bot, "This address is already set as unlocker.");
        _unlocker_bot = payable(_unlocker);
    }

    function setPauser(address _pauser) external onlyOwner {
        require(_pauser != _pauser_bot, "This address is already set as pauser.");
        _pauser_bot = _pauser;
    }

    function setPausedState(bool state) external onlyOwner() {
        paused = state;
    }

    function pauseBridge(address from, address to, uint256 amount) internal {
        paused = true;

        emit UnexpectedRequest(
            from,
            to,
            amount,
            block.timestamp,
            ErrorType.UnexpectedRequest
        );
    }

}
