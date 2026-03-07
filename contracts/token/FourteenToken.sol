// SPDX-License-Identifier: MIT
// Author: Stan At

pragma solidity ^0.8.0;

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(msg.sender);
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract TRC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public virtual returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner_, address spender) public view virtual returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual returns (bool) {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "TRC20: transfer amount exceeds allowance");
        _approve(sender, msg.sender, currentAllowance - amount);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "TRC20: transfer from the zero address");
        require(recipient != address(0), "TRC20: transfer to the zero address");

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "TRC20: transfer amount exceeds balance");

        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "TRC20: mint to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;

        emit Transfer(address(0), account, amount);
    }

    function _approve(address owner_, address spender, uint256 amount) internal {
        require(owner_ != address(0), "TRC20: approve from the zero address");
        require(spender != address(0), "TRC20: approve to the zero address");

        _allowances[owner_][spender] = amount;

        emit Approval(owner_, spender, amount);
    }
}

contract FourteenToken is TRC20, Ownable {
    uint256 public constant initialSupply = 10102022000000;

    uint256 public annualGrowthRate = 1475;
    uint256 public tokenPrice = 1000000;
    uint256 public lastPriceUpdate;

    uint256 public constant priceUpdateInterval = 90 days;

    struct LockInfo {
        uint256 amount;
        uint256 releaseTime;
    }

    mapping(address => LockInfo[]) private _locks;

    event PriceUpdated(uint256 oldPrice, uint256 newPrice);
    event BuyTokens(address indexed buyer, uint256 amountTRX, uint256 amountTokens);

    // Forwarding configuration
    address public liquidityPool;
    address public airdropAddress;

    // Reentrancy guard for forwarding
    bool private _inForward;

    modifier nonReentrant() {
        require(!_inForward, "Reentrant");
        _inForward = true;
        _;
        _inForward = false;
    }

    constructor(address _liquidityPool, address _airdropAddress)
        TRC20("4teen", "4TEEN", 6)
    {
        require(_liquidityPool != address(0), "liquidity pool zero");
        require(_airdropAddress != address(0), "airdrop zero");

        liquidityPool = _liquidityPool;
        airdropAddress = _airdropAddress;

        _mint(msg.sender, initialSupply);
        lastPriceUpdate = block.timestamp;
    }

    function setAnnualGrowthRate(uint256 newRate) external onlyOwner {
        annualGrowthRate = newRate;
    }

    function setLiquidityPool(address _pool) external onlyOwner {
        require(_pool != address(0), "zero");
        liquidityPool = _pool;
    }

    function setAirdropAddress(address _addr) external onlyOwner {
        require(_addr != address(0), "zero");
        airdropAddress = _addr;
    }

    function getCurrentPrice() public returns (uint256) {
        uint256 elapsedPeriods = (block.timestamp - lastPriceUpdate) / priceUpdateInterval;

        if (elapsedPeriods > 0) {
            uint256 oldPrice = tokenPrice;

            for (uint256 i = 0; i < elapsedPeriods; i++) {
                tokenPrice = (tokenPrice * (10000 + annualGrowthRate)) / 10000;
            }

            lastPriceUpdate += elapsedPeriods * priceUpdateInterval;

            emit PriceUpdated(oldPrice, tokenPrice);
        }

        return tokenPrice;
    }

    function buyTokens() external payable nonReentrant {
        require(msg.value > 0, "Send TRX to buy tokens");

        getCurrentPrice();

        uint256 amount = (msg.value * 10**decimals) / tokenPrice;
        require(amount > 0, "Amount too small");

        _mint(msg.sender, amount);

        _locks[msg.sender].push(
            LockInfo({
                amount: amount,
                releaseTime: block.timestamp + 14 days
            })
        );

        // Forwarding logic: 7% -> owner, 90% -> liquidityPool, 3% -> airdropAddress
        uint256 ownerShare = (msg.value * 7) / 100;
        uint256 liquidityShare = (msg.value * 90) / 100;
        uint256 airdropShare = msg.value - ownerShare - liquidityShare; // ensures total sums to msg.value

        // send to owner
        (bool sentOwner, ) = payable(owner()).call{ value: ownerShare }("");
        require(sentOwner, "Owner transfer failed");

        // send to liquidity pool
        (bool sentLP, ) = payable(liquidityPool).call{ value: liquidityShare }("");
        require(sentLP, "Liquidity transfer failed");

        // send to airdrop address
        (bool sentAirdrop, ) = payable(airdropAddress).call{ value: airdropShare }("");
        require(sentAirdrop, "Airdrop transfer failed");

        emit BuyTokens(msg.sender, msg.value, amount);
    }

    function lockedBalanceOf(address account) public view returns (uint256) {
        LockInfo[] memory locks = _locks[account];

        uint256 lockedAmount = 0;

        for (uint256 i = 0; i < locks.length; i++) {
            if (block.timestamp < locks[i].releaseTime) {
                lockedAmount += locks[i].amount;
            }
        }

        return lockedAmount;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        uint256 locked = lockedBalanceOf(msg.sender);
        uint256 totalBal = balanceOf(msg.sender);

        require(totalBal - locked >= amount, "Some tokens are locked");

        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        uint256 locked = lockedBalanceOf(sender);
        uint256 totalBal = balanceOf(sender);

        require(totalBal - locked >= amount, "Some tokens are locked");

        return super.transferFrom(sender, recipient, amount);
    }

    function withdrawLiquidity(uint256 amount) external onlyOwner {
        payable(owner()).transfer(amount);
    }

    receive() external payable {}
}
