pragma solidity 0.4.10;

contract Token {
    function transfer(address to, uint256 value) returns (bool success);
    function transferFrom(address from, address to, uint256 value) returns (bool success);
    function approve(address spender, uint256 value) returns (bool success);

    function totalSupply() constant returns (uint256 supply) {}
    function balanceOf(address owner) constant returns (uint256 balance);
    function allowance(address owner, address spender) constant returns (uint256 remaining);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


contract Crowdfunding {

    event Invest(address indexed sender, uint256 amount);

    enum State {
        FundingDeployed,    // 部署完成
        FundingSetUp        // 配置完成
        FundingStarted,     // 开始众筹
        FundingSucceed,     // 众筹成功：提前达到 maxFundingGoalInWei，或者按时达到 minFundingGoalInWei
        FundingFailed,      // 众筹失败：endsAt前没达到 minFundingGoalInWei
        TxStarted           // 解除冻结，代币开始交易
    }
    State public state;

    uint constant public maxFundingGoalInWei = 100000 * 10**18;
    uint constant public minFundingGoalInWei = 7500 * 10**18;
    uint constant public freezingPeriod = 7 days;
    uint256 public startsAt;
    uint256 public endsAt;

    Token public waltonToken;
    address public wallet;
    address public owner;

    uint public endTime;
    uint public weiRaised;
    uint public finalPrice;
    mapping (address => uint) public weiAmountOf;

    modifier atState(State _state) {
        if (state != _state)
            throw;
        _;
    }

    modifier isOwner() {
        if (msg.sender != owner)
            throw;
        _;
    }

    modifier isWallet() {
        if (msg.sender != wallet)
            throw;
        _;
    }

    modifier isValidPayload() {
        if (msg.data.length != 4 && msg.data.length != 36)
            throw;
        _;
    }

    modifier stateTransition() {
        if (state == State.FundingStarted && calcTokenPrice() <= calcStopPrice())
            finalizeFunding();
        if (state == State.FundingSucceed && now > endTime + freezingPeriod)
            state = State.TxStarted;
        _;
    }

    function Crowdfunding(address _wallet, uint _maxFundingGoalInWei, uint _priceFactor)
        public
    {
        if (_wallet == 0 || _maxFundingGoalInWei == 0 || _priceFactor == 0)
            throw;
        owner = msg.sender;
        wallet = _wallet;
        maxFundingGoalInWei = _maxFundingGoalInWei;
        priceFactor = _priceFactor;
        state = State.FundingDeployed;
    }

    function setup(address _token)
        public
        isOwner
        atState(State.FundingDeployed)
    {
        if (_token == 0)
            throw;
        waltonToken = Token(_token);
        if (waltonToken.balanceOf(this) != MAX_TOKENS_SOLD)
            throw;
        state = State.FundingSetUp;
    }

    function startFunding()
        public
        isWallet
        atState(State.FundingSetUp)
    {
        state = State.FundingStarted;
        startBlock = block.number;
    }

    function changeSettings(uint _maxFundingGoalInWei, uint _priceFactor)
        public
        isWallet
        atState(State.FundingSetUp)
    {
        maxFundingGoalInWei = _maxFundingGoalInWei;
        priceFactor = _priceFactor;
    }

    function calcCurrentTokenPrice()
        public
        stateTransition
        returns (uint)
    {
        if (state == State.FundingSucceed || state == State.TxStarted)
            return finalPrice;
        return calcTokenPrice();
    }

    function updateState()
        public
        stateTransition
        returns (State)
    {
        return state;
    }

    function invest(address investor)
        public
        payable
        isValidPayload
        stateTransition
        atState(State.FundingStarted)
        returns (uint amount)
    {
        if (investor == 0)
            investor = msg.sender;
        amount = msg.value;
        uint maxWei = maxFundingGoalInWei - weiRaised;
        if (amount > maxWei) {
            amount = maxWei;
            if (!investor.send(msg.value - amount))
                throw;
        }
        if (amount == 0 || !wallet.send(amount))
            throw;
        weiAmountOf[investor] += amount;
        weiRaised += amount;
        if (maxWei == amount)
            finalizeFunding();
        Invest(investor, amount);
    }

    function claimTokens(address receiver)
        public
        isValidPayload
        stateTransition
        atState(State.TxStarted)
    {
        if (receiver == 0)
            receiver = msg.sender;
        uint tokenCount = weiAmountOf[receiver] * 10**18 / finalPrice;
        weiAmountOf[receiver] = 0;
        waltonToken.transfer(receiver, tokenCount);
    }

    function calcStopPrice()
        constant
        public
        returns (uint)
    {
        return weiRaised * 10**18 / MAX_TOKENS_SOLD + 1;
    }

    function calcTokenPrice()
        constant
        public
        returns (uint)
    {
        return priceFactor * 10**18 / (block.number - startBlock + 7500) + 1;
    }

    function finalizeFunding()
        private
    {
        state = State.FundingSucceed;
        if (weiRaised == maxFundingGoalInWei)
            finalPrice = calcTokenPrice();
        else
            finalPrice = calcStopPrice();
        uint soldTokens = weiRaised * 10**18 / finalPrice;
        waltonToken.transfer(wallet, MAX_TOKENS_SOLD - soldTokens);
        endTime = now;
    }
}
