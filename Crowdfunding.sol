pragma solidity 0.4.11;


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


contract CrowdFunding {

    event Invest(address indexed sender, uint256 amount);
    event Refund(address indexed receiver, uint256 amount);

    uint constant public maxTokensSold = 9000000 * 10**18; // 9M, tokenWei
    uint constant public freezingDays = 7 days;
    uint constant public fundingDays = 15 days;
    uint constant public startsAt = 15 days;

    Token public token;
    address public wallet;
    address public owner;
    uint public ceilingWei;
    uint public floorWei;
    uint public endTime;
    uint public raisedWei;
    uint public weiRefunded;
    uint public finalPrice; // ethWei per token, not ethWei per tokenWei
    mapping (address => uint) public weiAmountOf;
    State public state;

    enum State {
        FundingDeployed,
        FundingSetUp,
        FundingStarted,
        FundingSucceed,
        FundingFailed,
        TxStarted
    }

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

    modifier stateTransitions() {
        if (state == State.FundingStarted && now > startsAt + fundingDays)
            finalizeFunding();
        if (state == State.FundingSucceed && now > endTime + freezingDays)
            state = State.TxStarted;
        _;
    }

    function CrowdFunding(address _wallet, uint _ceilingWei, uint _floorWei)
        public
    {
        if (_wallet == 0 || _ceilingWei == 0 || _floorWei == 0)
            throw;
        owner = msg.sender;
        wallet = _wallet;
        ceilingWei = _ceilingWei;
        floorWei = _floorWei;
        state = State.FundingDeployed;
    }

    function setup(address _gnosisToken)
        public
        isOwner
        atState(State.FundingDeployed)
    {
        if (_gnosisToken == 0)
            throw;
        token = Token(_gnosisToken);
        if (token.balanceOf(this) != maxTokensSold)
            throw;
        state = State.FundingSetUp;
    }

    function changeSettings(uint _ceilingWei)
        public
        isWallet
        atState(State.FundingSetUp)
    {
        ceilingWei = _ceilingWei;
    }

    function calcCurrentTokenPrice()
        public
        stateTransitions
        returns (uint)
    {
        if (state == State.FundingSucceed || state == State.TxStarted)
            return finalPrice;
        return calcTokenPrice();
    }

    function updateState()
        public
        stateTransitions
        returns (State)
    {
        return state;
    }

    function invest(address investor)
        public
        payable
        isValidPayload
        stateTransitions
        atState(State.FundingStarted)
        returns (uint amount)
    {
        if (investor == 0)
            investor = msg.sender;
        amount = msg.value;
        uint maxWei = ceilingWei - raisedWei;
        if (amount > maxWei) {
            amount = maxWei;
            if (!investor.send(msg.value - amount))
                throw;
        }
        if (amount == 0 || !wallet.send(amount))
            throw;
        weiAmountOf[investor] += amount;
        raisedWei += amount;
        if (maxWei == amount)
            finalizeFunding();
        Invest(investor, amount);
    }

    function requestTokens(address receiver)
        public
        isValidPayload
        stateTransitions
        atState(State.TxStarted)
    {
        if (receiver == 0)
            receiver = msg.sender;
        uint tokenCount = weiAmountOf[receiver] * 10**18 / finalPrice;
        weiAmountOf[receiver] = 0;
        token.transfer(receiver, tokenCount);
    }

    function refund(address receiver)
        public
        isValidPayload
        stateTransitions
        atState(State.FundingFailed)
    {
        if (receiver == 0)
            receiver = msg.sender;

        uint weiAmount = weiAmountOf[receiver];
        if (weiAmount == 0) throw;
        weiAmountOf[receiver] = 0;
        weiRefunded += weiAmount;
        Refund(receiver, weiAmount);
        if (!receiver.send(weiAmount)) throw;

    }

    // 价格单位：ethWei per token, not ethWei per tokenWei
    function calcTokenPrice()
        constant
        public
        returns (uint)
    {
        // 前三天固定售出Token总量28%，之后每天增加1%
        // 当天价格 = ceilingWei / 当天Token总量
        uint period = now - startsAt;
        uint curTotalToken = 0;
        for (uint i=3; i<fundingDays; i++) {
            if (period < i * 60 * 24) {
                curTotalToken = 28000000 * 10**18 + i * 1000000 * 10**18; 
                break;
            }
        }
        if (curTotalToken == 0)
            curTotalToken = 40000000 * 10**18;
        return ceilingWei * 10**18 / curTotalToken + 1;
    }

    function finalizeFunding()
        private
    {
        finalPrice = calcTokenPrice();
        if (raisedWei >= floorWei)
            state = State.FundingSucceed;
        else
            state = State.FundingFailed;
        uint soldTokens = raisedWei * 10**18 / finalPrice;
        token.transfer(wallet, maxTokensSold - soldTokens);
        endTime = now;
    }
}

