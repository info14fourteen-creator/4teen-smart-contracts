// SPDX-License-Identifier: MIT
// Author: Stan At

pragma solidity ^0.8.0;

/* =========================
   Ownable
========================= */
abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Not owner");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/* =========================
   Liquidity Executor Interface
========================= */
interface ILiquidityExecutor {
    function execute() external payable;
}

/* =========================
   FourteenLiquidityController
========================= */
contract FourteenLiquidityController is Ownable {

    address public targetA;
    address public targetB;

    uint256 public lastExecutionDay;

    uint256 public constant MIN_BALANCE = 100 trx;      // minimum balance required
    uint256 public constant DAILY_PERCENT = 643;        // 6.43%
    uint256 public constant PERCENT_DIVIDER = 10_000;

    /* =========================
       Events
    ========================= */
    event LiquidityExecuted(
        uint256 indexed day,
        uint256 totalAmount,
        uint256 amountA,
        uint256 amountB
    );

    event TargetsUpdated(
        address indexed oldA,
        address indexed oldB,
        address newA,
        address newB
    );

    event TRXReceived(address indexed from, uint256 amount);

    /* =========================
       Constructor
    ========================= */
    constructor(address _targetA, address _targetB) {
        require(_targetA != address(0), "targetA zero");
        require(_targetB != address(0), "targetB zero");

        targetA = _targetA;
        targetB = _targetB;
    }

    /* =========================
       Core logic
    ========================= */
    function executeLiquidity() external {
        uint256 today = block.timestamp / 1 days;
        require(today > lastExecutionDay, "Already executed today");

        uint256 balance = address(this).balance;
        require(balance >= MIN_BALANCE, "Balance below 100 TRX");

        uint256 totalAmount = (balance * DAILY_PERCENT) / PERCENT_DIVIDER;
        require(totalAmount > 0, "Amount too small");

        // Safe split (no rounding issues)
        uint256 amountA = totalAmount / 2;
        uint256 amountB = totalAmount - amountA;

        // lock execution day BEFORE external calls
        lastExecutionDay = today;

        // CALL executors with TRX + function execution
        ILiquidityExecutor(targetA).execute{value: amountA}();
        ILiquidityExecutor(targetB).execute{value: amountB}();

        emit LiquidityExecuted(today, totalAmount, amountA, amountB);
    }

    /* =========================
       Admin
    ========================= */
    function setTargets(address _newA, address _newB) external onlyOwner {
        require(_newA != address(0), "targetA zero");
        require(_newB != address(0), "targetB zero");

        address oldA = targetA;
        address oldB = targetB;

        targetA = _newA;
        targetB = _newB;

        emit TargetsUpdated(oldA, oldB, _newA, _newB);
    }

    /* =========================
       Receive TRX
    ========================= */
    receive() external payable {
        emit TRXReceived(msg.sender, msg.value);
    }
}
