// SPDX-License-Identifier: MIT
// Author: Stan At

pragma solidity ^0.5.17;

/* ========= INTERFACES ========= */

interface ITRC20 {
    function balanceOf(address owner) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
}

interface IFactory {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IPair {
    function token0() external view returns (address);
    function getReserves() external view returns (uint112, uint112, uint32);
}

interface IRouter {
    function WBASE() external view returns (address);

    function addLiquidityBase(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountTRXMin,
        address to,
        uint deadline
    ) external payable returns (uint, uint, uint);
}

/* ========= EXECUTOR ========= */

contract LiquidityExecutorJustMoney {

    address public FOURTEEN;
    address public factory;
    address public router;
    address public WBASE;

    bool public initialized;

    uint256 public constant SLIPPAGE_BPS = 300; // 3%
    uint256 public constant DEADLINE_OFFSET = 10 minutes;

    function init(
        address _fourteen,
        address _factory,
        address _router
    ) external {
        require(!initialized, "ALREADY_INIT");
        require(_fourteen != address(0), "FOURTEEN_ZERO");
        require(_factory != address(0), "FACTORY_ZERO");
        require(_router != address(0), "ROUTER_ZERO");

        FOURTEEN = _fourteen;
        factory = _factory;
        router = _router;

        WBASE = IRouter(router).WBASE();
        require(WBASE != address(0), "WBASE_ZERO");

        ITRC20(FOURTEEN).approve(router, uint256(-1));

        initialized = true;
    }

    function execute() external payable {
        require(initialized, "NOT_INIT");
        require(msg.value > 0, "NO_TRX");

        address pair = IFactory(factory).getPair(FOURTEEN, WBASE);
        require(pair != address(0), "PAIR_NOT_FOUND");

        (uint112 r0, uint112 r1,) = IPair(pair).getReserves();
        require(r0 > 0 && r1 > 0, "EMPTY_POOL");

        uint256 tokenAmount;

        if (IPair(pair).token0() == WBASE) {
            tokenAmount = msg.value * uint256(r1) / uint256(r0);
        } else {
            tokenAmount = msg.value * uint256(r0) / uint256(r1);
        }

        require(
            ITRC20(FOURTEEN).balanceOf(address(this)) >= tokenAmount,
            "NOT_ENOUGH_4TEEN"
        );

        uint256 deadline = block.timestamp + DEADLINE_OFFSET;

        IRouter(router).addLiquidityBase.value(msg.value)(
            FOURTEEN,
            tokenAmount,
            tokenAmount * (10000 - SLIPPAGE_BPS) / 10000,
            msg.value * (10000 - SLIPPAGE_BPS) / 10000,
            address(this),
            deadline
        );
    }

    function () external payable {}
}
