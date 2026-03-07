// SPDX-License-Identifier: MIT
// Author: Stan At
pragma solidity ^0.8.0;

interface ITRC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/*
  AirdropVault
  - 6 waves (Variant D): 500k, 350k, 250k, 180k, 120k, 100k = 1,500,000 4TEEN
  - Fixed unlock timestamps (based on Issue time)
  - Only OPERATOR can airdrop and withdraw excess (after all waves)
  - Per wallet: max 5 claims via social platform bitmask (IG/X/TG/FB/YT)
  - Contract holds 4TEEN tokens (you deposit via normal transfer)
*/
contract AirdropVault {
    ITRC20 public immutable FOURTEEN;
    address public operator;

    // 4TEEN decimals = 6, so 1 token = 1e6 raw
    uint256 private constant DEC = 1e6;

    // ===== Fixed Issue timestamp (UTC): 2025-11-23 02:37:45 =====
    uint256 public constant ISSUE_TS = 1763865465;

    // ===== Wave unlock timestamps (UTC) =====
    // Wave1 = Issue + 14 days, then +90 days each
    uint256 public constant W1 = 1765075065; // 2025-12-07 02:37:45
    uint256 public constant W2 = 1772851065; // 2026-03-07 02:37:45
    uint256 public constant W3 = 1780627065; // 2026-06-05 02:37:45
    uint256 public constant W4 = 1788403065; // 2026-09-03 02:37:45
    uint256 public constant W5 = 1796179065; // 2026-12-02 02:37:45
    uint256 public constant W6 = 1803955065; // 2027-03-02 02:37:45

    // After all waves: W1 + 6 * 90 days
    uint256 public constant AFTER_ALL_WAVES = 1811731065; // 2027-05-31 02:37:45

    // ===== Variant D caps (raw) =====
    uint256 public constant CAP1 = 500_000 * DEC;
    uint256 public constant CAP2 = 350_000 * DEC;
    uint256 public constant CAP3 = 250_000 * DEC;
    uint256 public constant CAP4 = 180_000 * DEC;
    uint256 public constant CAP5 = 120_000 * DEC;
    uint256 public constant CAP6 = 100_000 * DEC;

    uint256 public constant TOTAL_ALLOCATION =
        CAP1 + CAP2 + CAP3 + CAP4 + CAP5 + CAP6;

    // Accounting
    uint256 public totalDistributed;

    // Per-wallet platform mask:
    // 1=Instagram, 2=X, 4=Telegram, 8=Facebook, 16=YouTube
    mapping(address => uint8) public socialMask;

    event OperatorUpdated(address indexed oldOperator, address indexed newOperator);
    event Airdropped(address indexed to, uint256 amount, uint8 platformBit, uint8 newMask);
    event WithdrawnExcess(address indexed to, uint256 amount);

    modifier onlyOperator() {
        require(msg.sender == operator, "NOT_OPERATOR");
        _;
    }

    constructor(address _fourteenToken, address _operator) {
        require(_fourteenToken != address(0), "FOURTEEN_ZERO");
        require(_operator != address(0), "OPERATOR_ZERO");
        FOURTEEN = ITRC20(_fourteenToken);
        operator = _operator;
        emit OperatorUpdated(address(0), _operator);
    }

    // Operator replacement (only operator can rotate keys)
    function setOperator(address newOperator) external onlyOperator {
        require(newOperator != address(0), "OPERATOR_ZERO");
        address old = operator;
        operator = newOperator;
        emit OperatorUpdated(old, newOperator);
    }

    /* =========================
       Waves (views)
    ========================= */

    // Returns wave index: 0..5, or -1 if not started
    function currentWave() public view returns (int8) {
        uint256 t = block.timestamp;
        if (t < W1) return -1;
        if (t < W2) return 0;
        if (t < W3) return 1;
        if (t < W4) return 2;
        if (t < W5) return 3;
        if (t < W6) return 4;
        return 5;
    }

    function waveTime(uint8 i) public pure returns (uint256) {
        require(i < 6, "BAD_WAVE");
        if (i == 0) return W1;
        if (i == 1) return W2;
        if (i == 2) return W3;
        if (i == 3) return W4;
        if (i == 4) return W5;
        return W6; // i == 5
    }

    function waveCap(uint8 i) public pure returns (uint256) {
        require(i < 6, "BAD_WAVE");
        if (i == 0) return CAP1;
        if (i == 1) return CAP2;
        if (i == 2) return CAP3;
        if (i == 3) return CAP4;
        if (i == 4) return CAP5;
        return CAP6; // i == 5
    }

    function nextWaveTime() external view returns (uint256) {
        int8 w = currentWave();
        if (w < 0) return W1;
        if (w >= 5) return 0; // no next wave
        return waveTime(uint8(uint8(w) + 1));
    }

    // Total amount unlocked so far (cumulative cap)
    function unlockedTotal() public view returns (uint256) {
        int8 w = currentWave();
        if (w < 0) return 0;

        uint256 sum = CAP1;
        if (w >= 1) sum += CAP2;
        if (w >= 2) sum += CAP3;
        if (w >= 3) sum += CAP4;
        if (w >= 4) sum += CAP5;
        if (w >= 5) sum += CAP6;
        return sum;
    }

    function remainingUnlocked() public view returns (uint256) {
        uint256 unlocked = unlockedTotal();
        if (totalDistributed >= unlocked) return 0;
        return unlocked - totalDistributed;
    }

    function remainingPlanned() public view returns (uint256) {
        if (totalDistributed >= TOTAL_ALLOCATION) return 0;
        return TOTAL_ALLOCATION - totalDistributed;
    }

    function availableToDistributeNow() external view returns (uint256) {
        // you can distribute at most what is unlocked AND what you actually have
        uint256 lim = remainingUnlocked();
        uint256 bal = FOURTEEN.balanceOf(address(this));
        return (bal < lim) ? bal : lim;
    }

    function waveInfo()
        external
        view
        returns (
            int8 wave,
            uint256 unlocked,
            uint256 distributed,
            uint256 remainingNow,
            uint256 balance
        )
    {
        wave = currentWave();
        unlocked = unlockedTotal();
        distributed = totalDistributed;
        remainingNow = remainingUnlocked();
        balance = FOURTEEN.balanceOf(address(this));
    }

    /* =========================
       Per-wallet (views)
    ========================= */

    function isClaimedPlatform(address wallet, uint8 platformBit) external view returns (bool) {
        require(_isValidPlatformBit(platformBit), "BAD_PLATFORM_BIT");
        return (socialMask[wallet] & platformBit) != 0;
    }

    // returns 0..5 count of used bits (IG/X/TG/FB/YT)
    function claimsCount(address wallet) external view returns (uint8) {
        return _popcount5(socialMask[wallet]);
    }

    /* =========================
       Actions
    ========================= */

    // Airdrop (only operator)
    function airdrop(address to, uint256 amount, uint8 platformBit) external onlyOperator {
        require(to != address(0), "TO_ZERO");
        require(amount > 0, "AMOUNT_ZERO");
        require(_isValidPlatformBit(platformBit), "BAD_PLATFORM_BIT");

        require(unlockedTotal() > 0, "WAVE_NOT_STARTED");

        uint8 mask = socialMask[to];
        require((mask & platformBit) == 0, "ALREADY_CLAIMED_PLATFORM");

        require(remainingUnlocked() >= amount, "WAVE_CAP_EXCEEDED");
        require(FOURTEEN.balanceOf(address(this)) >= amount, "INSUFFICIENT_VAULT_BALANCE");

        socialMask[to] = mask | platformBit;
        totalDistributed += amount;

        require(FOURTEEN.transfer(to, amount), "TRANSFER_FAILED");

        emit Airdropped(to, amount, platformBit, socialMask[to]);
    }

    // Withdraw only AFTER all waves AND only "excess" over remaining planned allocation
    function withdrawExcess(address to, uint256 amount) external onlyOperator {
        require(to != address(0), "TO_ZERO");
        require(amount > 0, "AMOUNT_ZERO");
        require(block.timestamp >= AFTER_ALL_WAVES, "TOO_EARLY");

        uint256 bal = FOURTEEN.balanceOf(address(this));

        uint256 mustKeep = remainingPlanned();
        require(bal > mustKeep, "NO_EXCESS");

        uint256 excess = bal - mustKeep;
        require(amount <= excess, "AMOUNT_GT_EXCESS");

        require(FOURTEEN.transfer(to, amount), "TRANSFER_FAILED");
        emit WithdrawnExcess(to, amount);
    }

    // View helper: how much excess exists now (even though withdraw is time-locked)
    function excessNow() external view returns (uint256) {
        uint256 bal = FOURTEEN.balanceOf(address(this));
        uint256 mustKeep = remainingPlanned();
        if (bal <= mustKeep) return 0;
        return bal - mustKeep;
    }

    /* =========================
       Internals
    ========================= */

    function _isValidPlatformBit(uint8 b) internal pure returns (bool) {
        return (b == 1 || b == 2 || b == 4 || b == 8 || b == 16);
    }

    function _popcount5(uint8 x) internal pure returns (uint8) {
        // counts bits among {1,2,4,8,16}
        uint8 c = 0;
        if ((x & 1) != 0) c++;
        if ((x & 2) != 0) c++;
        if ((x & 4) != 0) c++;
        if ((x & 8) != 0) c++;
        if ((x & 16) != 0) c++;
        return c;
    }

    receive() external payable {
        revert("NO_TRX");
    }
}
