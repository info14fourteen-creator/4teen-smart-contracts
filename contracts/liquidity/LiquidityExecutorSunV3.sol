// SPDX-License-Identifier: MIT
// Author: Stan At

pragma solidity ^0.5.17;
pragma experimental ABIEncoderV2;

/* ========= INTERFACES ========= */

interface ITRC20 {
    function balanceOf(address owner) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
}

interface ISunV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16,
        uint16,
        uint16,
        uint8,
        bool
    );

    function tickSpacing() external view returns (int24);
}

interface INonfungiblePositionManager {

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128, uint256, uint256);

    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (uint128, uint256, uint256);

    function collect(CollectParams calldata params)
        external
        returns (uint256, uint256);
}

/* ========= EXECUTOR ========= */

contract LiquidityExecutorSunV3 {

    address public FOURTEEN;
    address public WTRX;
    address public pool;
    address public positionManager;

    uint256 public tokenId;
    bool public initialized;

    uint24 public constant FEE = 3000;
    uint256 public constant DEADLINE_OFFSET = 15 minutes;

    uint256 private constant Q96 = 2**96;

    /* ========= INIT ========= */

    function init(
        address _fourteen,
        address _wtrx,
        address _pool,
        address _positionManager
    ) external {
        require(!initialized, "ALREADY_INIT");

        FOURTEEN = _fourteen;
        WTRX = _wtrx;
        pool = _pool;
        positionManager = _positionManager;

        ITRC20(FOURTEEN).approve(positionManager, uint256(-1));
        ITRC20(WTRX).approve(positionManager, uint256(-1));

        initialized = true;
    }

    /* ========= EXECUTE ========= */

    function execute() external payable {
        require(initialized, "NOT_INIT");
        require(msg.value > 0, "NO_TRX");

        /* ===== read pool state ===== */
        (uint160 sqrtPriceX96, int24 tick, , , , ,) = ISunV3Pool(pool).slot0();
        int24 spacing = ISunV3Pool(pool).tickSpacing();

        require(sqrtPriceX96 > 0, "BAD_PRICE");

        /* ===== wider safe range ===== */
        int24 currentTick = (tick / spacing) * spacing;

        // широкая зона = меньше reverts
        int24 range = spacing * 80;

        int24 tickLower = currentTick - range;
        int24 tickUpper = currentTick + range;

        /* ===== price calculation ===== */
        uint256 priceX96 = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 96;

        // базовый расчет
        uint256 amountFourteen = (msg.value * Q96) / priceX96;

        // +5% safety buffer
        amountFourteen = amountFourteen * 105 / 100;

        require(amountFourteen > 0, "AMOUNT_TOO_SMALL");
        require(
            ITRC20(FOURTEEN).balanceOf(address(this)) >= amountFourteen,
            "NOT_ENOUGH_4TEEN"
        );

        uint256 deadline = block.timestamp + DEADLINE_OFFSET;

        if (tokenId == 0) {

            INonfungiblePositionManager.MintParams memory params =
                INonfungiblePositionManager.MintParams({
                    token0: FOURTEEN,
                    token1: WTRX,
                    fee: FEE,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: amountFourteen,
                    amount1Desired: msg.value,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: deadline
                });

            (tokenId, , , ) =
                INonfungiblePositionManager(positionManager)
                    .mint
                    .value(msg.value)(params);

        } else {

            INonfungiblePositionManager(positionManager).collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: tokenId,
                    recipient: address(this),
                    amount0Max: uint128(-1),
                    amount1Max: uint128(-1)
                })
            );

            INonfungiblePositionManager(positionManager)
                .increaseLiquidity
                .value(msg.value)(
                    INonfungiblePositionManager.IncreaseLiquidityParams({
                        tokenId: tokenId,
                        amount0Desired: amountFourteen,
                        amount1Desired: msg.value,
                        amount0Min: 0,
                        amount1Min: 0,
                        deadline: deadline
                    })
                );
        }
    }

    function () external payable {}
}
