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
        FundingDeployed,
        FundingSetUp,
        FundingStarted,
        FundingEnded,
        TxStarted
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
    uint public totalReceived;
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
        if (state == State.FundingEnded && now > endTime + freezingPeriod)
            state = State.TxStarted;
        _;
    }

    function Crowdfunding(address _wallet, uint _ceiling, uint _priceFactor)
        public
    {
        if (_wallet == 0 || _ceiling == 0 || _priceFactor == 0)
            throw;
        owner = msg.sender;
        wallet = _wallet;
        ceiling = _ceiling;
        priceFactor = _priceFactor;
        state = State.FundingDeployed;
    }

    function setup(address _gnosisToken)
        public
        isOwner
        atState(State.FundingDeployed)
    {
        if (_gnosisToken == 0)
            throw;
        waltonToken = Token(_gnosisToken);
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

    function changeSettings(uint _ceiling, uint _priceFactor)
        public
        isWallet
        atState(State.FundingSetUp)
    {
        ceiling = _ceiling;
        priceFactor = _priceFactor;
    }

    function calcCurrentTokenPrice()
        public
        stateTransition
        returns (uint)
    {
        if (state == State.FundingEnded || state == State.TxStarted)
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
        uint maxWei = (MAX_TOKENS_SOLD / 10**18) * calcTokenPrice() - totalReceived;
        uint maxWeiBasedOnTotalReceived = ceiling - totalReceived;
        if (maxWeiBasedOnTotalReceived < maxWei)
            maxWei = maxWeiBasedOnTotalReceived;
        if (amount > maxWei) {
            amount = maxWei;
            if (!investor.send(msg.value - amount))
                throw;
        }
        if (amount == 0 || !wallet.send(amount))
            throw;
        weiAmountOf[investor] += amount;
        totalReceived += amount;
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
        return totalReceived * 10**18 / MAX_TOKENS_SOLD + 1;
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
        state = State.FundingEnded;
        if (totalReceived == ceiling)
            finalPrice = calcTokenPrice();
        else
            finalPrice = calcStopPrice();
        uint soldTokens = totalReceived * 10**18 / finalPrice;
        waltonToken.transfer(wallet, MAX_TOKENS_SOLD - soldTokens);
        endTime = now;
    }
}
