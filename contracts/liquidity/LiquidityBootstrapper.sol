// SPDX-License-Identifier: MIT
// Author: Stan At
pragma solidity ^0.8.0;

/* =========================
   Minimal Ownable
========================= */
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "NOT_OWNER");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ZERO");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/* =========================
   Interfaces
========================= */
interface ITRC20 {
    function balanceOf(address) external view returns (uint256);
}

interface IFourteenVault {
    function pull(address to, uint256 amount) external;
}

interface ILiquidityController {
    function lastExecutionDay() external view returns (uint256);
    function executeLiquidity() external;

    function targetA() external view returns (address);
    function targetB() external view returns (address);

    function DAILY_PERCENT() external view returns (uint256);
    function PERCENT_DIVIDER() external view returns (uint256);
    function MIN_BALANCE() external view returns (uint256);
}

/* ===== JustMoney ===== */
interface IJustMoneyExecutor {
    function factory() external view returns (address);
    function WBASE() external view returns (address);
    function FOURTEEN() external view returns (address);
}

interface IFactory {
    function getPair(address, address) external view returns (address);
}

interface IPair {
    function token0() external view returns (address);
    function getReserves() external view returns (uint112, uint112, uint32);
}

/* ===== Sun V3 ===== */
interface ISunV3Executor {
    function pool() external view returns (address);
}

interface ISunV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24,
        uint16,
        uint16,
        uint16,
        uint8,
        bool
    );
}

/* =========================
   LiquidityBootstrapper
========================= */
contract LiquidityBootstrapper is Ownable {
    ILiquidityController public controller; // settable (optional)
    IFourteenVault public vault;            // set after deploy
    ITRC20 public immutable FOURTEEN;       // only for balance checks on executors

    uint256 public constant SAFETY_BPS = 500; // +5%
    uint256 public constant BPS = 10_000;

    event VaultUpdated(address indexed oldVault, address indexed newVault);
    event ControllerUpdated(address indexed oldController, address indexed newController);

    constructor(address _controller, address _fourteenToken) {
        require(_controller != address(0), "CTRL_ZERO");
        require(_fourteenToken != address(0), "FOURTEEN_ZERO");

        controller = ILiquidityController(_controller);
        FOURTEEN = ITRC20(_fourteenToken);
    }

    function setVault(address newVault) external onlyOwner {
        require(newVault != address(0), "VAULT_ZERO");
        address old = address(vault);
        vault = IFourteenVault(newVault);
        emit VaultUpdated(old, newVault);
    }

    // optional, раз ты хочешь заменяемость
    function setController(address newController) external onlyOwner {
        require(newController != address(0), "CTRL_ZERO");
        address old = address(controller);
        controller = ILiquidityController(newController);
        emit ControllerUpdated(old, newController);
    }

    function bootstrapAndExecute() external {
        require(address(vault) != address(0), "VAULT_NOT_SET");

        // 1) day check (must match LiquidityController logic)
        uint256 today = block.timestamp / 1 days;
        require(controller.lastExecutionDay() < today, "ALREADY_RUN");

        // 2) controller TRX balance check
        uint256 trxBalance = address(controller).balance;
        require(trxBalance >= controller.MIN_BALANCE(), "LOW_BALANCE");

        // 3) compute daily amount exactly like controller
        uint256 total =
            trxBalance * controller.DAILY_PERCENT()
            / controller.PERCENT_DIVIDER();
        require(total > 0, "ZERO_AMOUNT");

        uint256 amountA = total / 2;
        uint256 amountB = total - amountA;

        address execA = controller.targetA();
        address execB = controller.targetB();

        // IMPORTANT: assumes execA = JustMoney, execB = SunV3 (your chosen convention)
        _prepareJustMoney(execA, amountA);
        _prepareSunV3(execB, amountB);

        // 4) execute controller (unchanged)
        controller.executeLiquidity();
    }

    function _prepareJustMoney(address exec, uint256 trxAmount) internal {
        require(exec != address(0), "EXEC_ZERO");

        IJustMoneyExecutor jm = IJustMoneyExecutor(exec);

        address pair =
            IFactory(jm.factory())
                .getPair(jm.FOURTEEN(), jm.WBASE());
        require(pair != address(0), "PAIR_NOT_FOUND");

        (uint112 r0, uint112 r1,) = IPair(pair).getReserves();
        require(r0 > 0 && r1 > 0, "EMPTY_POOL");

        uint256 needed;
        if (IPair(pair).token0() == jm.WBASE()) {
            needed = trxAmount * uint256(r1) / uint256(r0);
        } else {
            needed = trxAmount * uint256(r0) / uint256(r1);
        }

        needed = needed * (BPS + SAFETY_BPS) / BPS;
        _topUpFromVault(exec, needed);
    }

    function _prepareSunV3(address exec, uint256 trxAmount) internal {
        require(exec != address(0), "EXEC_ZERO");

        address pool = ISunV3Executor(exec).pool();
        require(pool != address(0), "POOL_ZERO");

        (uint160 sqrtPriceX96,,,,,,) = ISunV3Pool(pool).slot0();

        uint256 priceX96 =
            (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 96;
        require(priceX96 > 0, "BAD_PRICE");

        uint256 needed = (trxAmount << 96) / priceX96;

        needed = needed * (BPS + SAFETY_BPS) / BPS;
        _topUpFromVault(exec, needed);
    }

    function _topUpFromVault(address exec, uint256 needed) internal {
        uint256 current = FOURTEEN.balanceOf(exec);
        if (current < needed) {
            vault.pull(exec, needed - current);
        }
    }

    receive() external payable {}
}
