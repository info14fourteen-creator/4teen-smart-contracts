// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFourteenToken {
    function owner() external view returns (address);
    function annualGrowthRate() external view returns (uint256);
    function tokenPrice() external view returns (uint256);
    function lastPriceUpdate() external view returns (uint256);
    function priceUpdateInterval() external view returns (uint256);
    function liquidityPool() external view returns (address);
    function airdropAddress() external view returns (address);

    function setAnnualGrowthRate(uint256 newRate) external;
    function setLiquidityPool(address pool) external;
    function setAirdropAddress(address addr) external;
    function withdrawLiquidity(uint256 amount) external;
    function transferOwnership(address newOwner) external;
    function getCurrentPrice() external returns (uint256);
}

abstract contract ReentrancyGuard {
    bool private _entered;

    modifier nonReentrant() {
        require(!_entered, "Reentrant");
        _entered = true;
        _;
        _entered = false;
    }
}

contract OwnableSimple {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        require(initialOwner != address(0), "Owner zero");
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Not owner");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferContractOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Owner zero");
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract FourteenController is OwnableSimple, ReentrancyGuard {
    enum Level {
        Bronze,
        Silver,
        Gold,
        Platinum
    }

    enum IncomingKind {
        None,
        LiquidityWithdrawal
    }

    struct Ambassador {
        bool exists;
        bool active;
        bool selfRegistered;
        bool manualAssigned;
        bool overrideEnabled;
        uint8 currentLevel;
        uint8 overrideLevel;
        uint256 totalBuyers;
        uint256 totalVolumeSun;
        uint256 totalRewardsAccruedSun;
        uint256 totalRewardsClaimedSun;
        uint256 claimableRewardsSun;
        uint256 createdAt;
        bytes32 slugHash;
        bytes32 metaHash;
    }

    IFourteenToken public immutable fourteenToken;

    uint256 public ownerAvailableBalance;
    uint256 public totalReservedRewards;
    uint256 public unallocatedPurchaseFunds;

    bool public selfRegistrationEnabled = true;
    bool public paused;

    uint256 public totalAmbassadors;
    uint256 public activeAmbassadors;
    uint256 public totalBoundBuyers;
    uint256 public totalTrackedVolumeSun;
    uint256 public totalRewardsAccruedSun;
    uint256 public totalRewardsClaimedSun;

    IncomingKind private _expectedIncomingKind;
    uint256 private _expectedIncomingAmount;

    mapping(address => Ambassador) private _ambassadors;
    mapping(address => address) public buyerToAmbassador;
    mapping(bytes32 => address) public slugToAmbassador;
    mapping(bytes32 => bool) public processedPurchases;
    mapping(address => bool) public operators;

    event PurchaseOwnerShareReceived(uint256 amountSun);
    event LiquidityPulledFromFourteen(uint256 amountSun);
    event ManualOwnerDeposit(address indexed from, uint256 amountSun);

    event PurchaseFundsAllocated(
        bytes32 indexed purchaseId,
        address indexed buyer,
        address indexed ambassador,
        uint256 purchaseAmountSun,
        uint256 ownerShareSun,
        uint256 rewardSun,
        uint256 ownerPartSun,
        uint8 level
    );

    event AmbassadorRegistered(address indexed ambassador, bytes32 slugHash, bool selfRegistered);
    event AmbassadorAssigned(address indexed ambassador, uint8 level, bytes32 slugHash);
    event AmbassadorStatusChanged(address indexed ambassador, bool active);
    event AmbassadorLevelSet(address indexed ambassador, uint8 level, bool overrideEnabled);
    event AmbassadorMetaUpdated(address indexed ambassador, bytes32 metaHash);
    event AmbassadorSlugUpdated(address indexed ambassador, bytes32 oldSlugHash, bytes32 newSlugHash);

    event BuyerBound(address indexed buyer, address indexed ambassador);
    event BuyerRebound(address indexed buyer, address indexed oldAmbassador, address indexed newAmbassador);

    event ReferralRewardAccrued(
        address indexed buyer,
        address indexed ambassador,
        uint256 purchaseAmountSun,
        uint256 rewardSun,
        uint8 level
    );

    event ReservedRewardDebited(address indexed ambassador, uint256 amountSun);
    event RewardsWithdrawn(address indexed ambassador, uint256 amountSun);
    event OwnerFundsWithdrawn(address indexed owner, uint256 amountSun);
    event OperatorUpdated(address indexed operator, bool allowed);
    event SelfRegistrationUpdated(bool enabled);
    event PauseUpdated(bool pausedState);

    event FourteenGrowthRateUpdated(uint256 newRate);
    event FourteenLiquidityPoolUpdated(address indexed pool);
    event FourteenAirdropAddressUpdated(address indexed airdrop);
    event FourteenLiquidityWithdrawn(uint256 amountSun);
    event FourteenOwnershipTransferred(address indexed newOwner);
    event FourteenPriceSynced(uint256 newPrice);

    modifier onlyOperatorOrOwner() {
        require(msg.sender == owner() || operators[msg.sender], "Not operator/owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    constructor(address fourteenTokenAddress) OwnableSimple(msg.sender) {
        require(fourteenTokenAddress != address(0), "Token zero");
        fourteenToken = IFourteenToken(fourteenTokenAddress);
    }

    receive() external payable {
        if (_expectedIncomingKind == IncomingKind.LiquidityWithdrawal) {
            require(msg.sender == address(fourteenToken), "Unexpected sender");
            require(msg.value == _expectedIncomingAmount, "Unexpected liquidity amount");

            ownerAvailableBalance += msg.value;
            _expectedIncomingKind = IncomingKind.None;
            _expectedIncomingAmount = 0;

            emit LiquidityPulledFromFourteen(msg.value);
            return;
        }

        require(msg.sender == address(fourteenToken), "Direct transfers disabled");
        unallocatedPurchaseFunds += msg.value;
        emit PurchaseOwnerShareReceived(msg.value);
    }

    // =========================
    // 4TEEN owner control
    // =========================

    function setFourteenAnnualGrowthRate(uint256 newRate) external onlyOwner {
        fourteenToken.setAnnualGrowthRate(newRate);
        emit FourteenGrowthRateUpdated(newRate);
    }

    function setFourteenLiquidityPool(address pool) external onlyOwner {
        require(pool != address(0), "Pool zero");
        fourteenToken.setLiquidityPool(pool);
        emit FourteenLiquidityPoolUpdated(pool);
    }

    function setFourteenAirdropAddress(address airdrop) external onlyOwner {
        require(airdrop != address(0), "Airdrop zero");
        fourteenToken.setAirdropAddress(airdrop);
        emit FourteenAirdropAddressUpdated(airdrop);
    }

    function withdrawFourteenLiquidity(uint256 amountSun) external onlyOwner {
        require(_expectedIncomingKind == IncomingKind.None, "Incoming pending");

        _expectedIncomingKind = IncomingKind.LiquidityWithdrawal;
        _expectedIncomingAmount = amountSun;

        fourteenToken.withdrawLiquidity(amountSun);

        require(_expectedIncomingKind == IncomingKind.None, "Liquidity not received");
        emit FourteenLiquidityWithdrawn(amountSun);
    }

    function transferFourteenOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Owner zero");
        fourteenToken.transferOwnership(newOwner);
        emit FourteenOwnershipTransferred(newOwner);
    }

    function syncFourteenPrice() external onlyOwner returns (uint256 newPrice) {
        newPrice = fourteenToken.getCurrentPrice();
        emit FourteenPriceSynced(newPrice);
    }

    // =========================
    // Program controls
    // =========================

    function setPaused(bool state) external onlyOwner {
        paused = state;
        emit PauseUpdated(state);
    }

    function setSelfRegistrationEnabled(bool enabled) external onlyOwner {
        selfRegistrationEnabled = enabled;
        emit SelfRegistrationUpdated(enabled);
    }

    function setOperator(address operator, bool allowed) external onlyOwner {
        require(operator != address(0), "Operator zero");
        operators[operator] = allowed;
        emit OperatorUpdated(operator, allowed);
    }

    // =========================
    // Ambassador registration
    // =========================

    function registerAsAmbassador(bytes32 slugHash, bytes32 metaHash) external whenNotPaused {
        require(selfRegistrationEnabled, "Self-registration disabled");
        require(slugHash != bytes32(0), "Slug empty");
        require(!_ambassadors[msg.sender].exists, "Already ambassador");
        require(slugToAmbassador[slugHash] == address(0), "Slug taken");

        Ambassador storage a = _ambassadors[msg.sender];
        a.exists = true;
        a.active = true;
        a.selfRegistered = true;
        a.manualAssigned = false;
        a.overrideEnabled = false;
        a.currentLevel = uint8(Level.Bronze);
        a.overrideLevel = uint8(Level.Bronze);
        a.createdAt = block.timestamp;
        a.slugHash = slugHash;
        a.metaHash = metaHash;

        slugToAmbassador[slugHash] = msg.sender;

        totalAmbassadors += 1;
        activeAmbassadors += 1;

        emit AmbassadorRegistered(msg.sender, slugHash, true);
    }

    function assignAmbassador(
        address ambassadorAddress,
        uint8 level,
        bytes32 slugHash,
        bytes32 metaHash
    ) external onlyOwner {
        require(ambassadorAddress != address(0), "Ambassador zero");
        require(slugHash != bytes32(0), "Slug empty");
        _validateLevel(level);

        address slugOwner = slugToAmbassador[slugHash];
        require(slugOwner == address(0) || slugOwner == ambassadorAddress, "Slug taken");

        Ambassador storage a = _ambassadors[ambassadorAddress];
        bool isNew = !a.exists;
        bool wasActive = a.active;
        bytes32 oldSlug = a.slugHash;

        if (isNew) {
            a.exists = true;
            a.createdAt = block.timestamp;
            totalAmbassadors += 1;
        }

        if (oldSlug != bytes32(0) && oldSlug != slugHash) {
            delete slugToAmbassador[oldSlug];
        }

        a.active = true;
        a.manualAssigned = true;
        a.overrideEnabled = true;
        a.currentLevel = level;
        a.overrideLevel = level;
        a.slugHash = slugHash;
        a.metaHash = metaHash;

        slugToAmbassador[slugHash] = ambassadorAddress;

        if (!wasActive) {
            activeAmbassadors += 1;
        }

        emit AmbassadorAssigned(ambassadorAddress, level, slugHash);
    }

    function setAmbassadorLevel(address ambassadorAddress, uint8 level) external onlyOwner {
        _validateAmbassadorExists(ambassadorAddress);
        _validateLevel(level);

        Ambassador storage a = _ambassadors[ambassadorAddress];
        a.currentLevel = level;
        a.overrideLevel = level;
        a.overrideEnabled = true;

        emit AmbassadorLevelSet(ambassadorAddress, level, true);
    }

    function enableLevelOverride(address ambassadorAddress, uint8 level) external onlyOwner {
        _validateAmbassadorExists(ambassadorAddress);
        _validateLevel(level);

        Ambassador storage a = _ambassadors[ambassadorAddress];
        a.overrideEnabled = true;
        a.overrideLevel = level;
        a.currentLevel = level;

        emit AmbassadorLevelSet(ambassadorAddress, level, true);
    }

    function disableLevelOverride(address ambassadorAddress) external onlyOwner {
        _validateAmbassadorExists(ambassadorAddress);

        Ambassador storage a = _ambassadors[ambassadorAddress];
        a.overrideEnabled = false;
        a.currentLevel = _getAutoLevelByBuyerCount(a.totalBuyers);

        emit AmbassadorLevelSet(ambassadorAddress, a.currentLevel, false);
    }

    function enableAmbassador(address ambassadorAddress) external onlyOwner {
        _validateAmbassadorExists(ambassadorAddress);

        Ambassador storage a = _ambassadors[ambassadorAddress];
        if (!a.active) {
            a.active = true;
            activeAmbassadors += 1;
            emit AmbassadorStatusChanged(ambassadorAddress, true);
        }
    }

    function disableAmbassador(address ambassadorAddress) external onlyOwner {
        _validateAmbassadorExists(ambassadorAddress);

        Ambassador storage a = _ambassadors[ambassadorAddress];
        if (a.active) {
            a.active = false;
            activeAmbassadors -= 1;
            emit AmbassadorStatusChanged(ambassadorAddress, false);
        }
    }

    function setAmbassadorMeta(address ambassadorAddress, bytes32 metaHash) external onlyOwner {
        _validateAmbassadorExists(ambassadorAddress);
        _ambassadors[ambassadorAddress].metaHash = metaHash;
        emit AmbassadorMetaUpdated(ambassadorAddress, metaHash);
    }

    function setAmbassadorSlug(address ambassadorAddress, bytes32 newSlugHash) external onlyOwner {
        _validateAmbassadorExists(ambassadorAddress);
        require(newSlugHash != bytes32(0), "Slug empty");

        address slugOwner = slugToAmbassador[newSlugHash];
        require(slugOwner == address(0) || slugOwner == ambassadorAddress, "Slug taken");

        Ambassador storage a = _ambassadors[ambassadorAddress];
        bytes32 oldSlug = a.slugHash;

        if (oldSlug != bytes32(0) && oldSlug != newSlugHash) {
            delete slugToAmbassador[oldSlug];
        }

        a.slugHash = newSlugHash;
        slugToAmbassador[newSlugHash] = ambassadorAddress;

        emit AmbassadorSlugUpdated(ambassadorAddress, oldSlug, newSlugHash);
    }

    // =========================
    // Buyer binding
    // =========================

    function bindBuyerToAmbassador(address buyer, address ambassadorAddress) external onlyOwner {
        _bindBuyerToAmbassador(buyer, ambassadorAddress);
    }

    function rebindBuyer(address buyer, address newAmbassador) external onlyOwner {
        require(buyer != address(0), "Buyer zero");
        require(newAmbassador != address(0), "Ambassador zero");
        require(buyer != newAmbassador, "Self-referral forbidden");

        address oldAmbassador = buyerToAmbassador[buyer];
        require(oldAmbassador != address(0), "Buyer not bound");
        require(oldAmbassador != newAmbassador, "Same ambassador");

        _validateAmbassadorForNewBinding(newAmbassador);

        Ambassador storage oldA = _ambassadors[oldAmbassador];
        Ambassador storage newA = _ambassadors[newAmbassador];

        if (oldA.totalBuyers > 0) {
            oldA.totalBuyers -= 1;
        }
        newA.totalBuyers += 1;

        buyerToAmbassador[buyer] = newAmbassador;

        _refreshAutoLevel(oldAmbassador);
        _refreshAutoLevel(newAmbassador);

        emit BuyerRebound(buyer, oldAmbassador, newAmbassador);
    }

    function canBindBuyerToAmbassador(address buyer, address ambassadorAddress) external view returns (bool) {
        if (buyer == address(0)) return false;
        if (ambassadorAddress == address(0)) return false;
        if (buyer == ambassadorAddress) return false;
        if (buyerToAmbassador[buyer] != address(0)) return false;

        Ambassador storage a = _ambassadors[ambassadorAddress];
        if (!a.exists) return false;
        if (!a.active) return false;

        return true;
    }

    // =========================
    // Trigger allocation
    // =========================

    function recordVerifiedPurchase(
        bytes32 purchaseId,
        address buyer,
        address ambassadorCandidate,
        uint256 purchaseAmountSun,
        uint256 ownerShareSun
    ) external onlyOperatorOrOwner whenNotPaused {
        require(purchaseId != bytes32(0), "PurchaseId empty");
        require(!processedPurchases[purchaseId], "Purchase already processed");
        require(buyer != address(0), "Buyer zero");
        require(purchaseAmountSun > 0, "Purchase amount zero");
        require(ownerShareSun > 0, "Owner share zero");
        require(ownerShareSun <= unallocatedPurchaseFunds, "Insufficient unallocated funds");

        address actualAmbassador = buyerToAmbassador[buyer];

        if (actualAmbassador == address(0)) {
            require(ambassadorCandidate != address(0), "Ambassador zero");
            _bindBuyerToAmbassador(buyer, ambassadorCandidate);
            actualAmbassador = ambassadorCandidate;
        }

        require(_ambassadors[actualAmbassador].exists, "Ambassador missing");

        uint8 level = _getEffectiveLevel(actualAmbassador);
        uint256 percent = _getRewardPercentByLevel(level);
        uint256 rewardSun = (ownerShareSun * percent) / 100;
        uint256 ownerPartSun = ownerShareSun - rewardSun;

        processedPurchases[purchaseId] = true;
        unallocatedPurchaseFunds -= ownerShareSun;

        Ambassador storage a = _ambassadors[actualAmbassador];
        a.totalVolumeSun += purchaseAmountSun;
        a.totalRewardsAccruedSun += rewardSun;
        a.claimableRewardsSun += rewardSun;

        totalTrackedVolumeSun += purchaseAmountSun;
        totalRewardsAccruedSun += rewardSun;
        totalReservedRewards += rewardSun;
        ownerAvailableBalance += ownerPartSun;

        emit ReferralRewardAccrued(buyer, actualAmbassador, purchaseAmountSun, rewardSun, level);
        emit PurchaseFundsAllocated(
            purchaseId,
            buyer,
            actualAmbassador,
            purchaseAmountSun,
            ownerShareSun,
            rewardSun,
            ownerPartSun,
            level
        );
    }

    // =========================
    // Rewards and funds
    // =========================

    function withdrawRewards() external nonReentrant whenNotPaused {
        Ambassador storage a = _ambassadors[msg.sender];
        require(a.exists, "Not ambassador");

        uint256 amountSun = a.claimableRewardsSun;
        require(amountSun > 0, "Nothing to withdraw");

        a.claimableRewardsSun = 0;
        a.totalRewardsClaimedSun += amountSun;

        totalReservedRewards -= amountSun;
        totalRewardsClaimedSun += amountSun;

        (bool sent, ) = payable(msg.sender).call{value: amountSun}("");
        require(sent, "Reward transfer failed");

        emit RewardsWithdrawn(msg.sender, amountSun);
    }

    function withdrawOwnerFunds(uint256 amountSun) external onlyOwner nonReentrant whenNotPaused {
        require(amountSun > 0, "Amount zero");
        require(amountSun <= ownerAvailableBalance, "Insufficient owner balance");

        ownerAvailableBalance -= amountSun;

        (bool sent, ) = payable(owner()).call{value: amountSun}("");
        require(sent, "Owner transfer failed");

        emit OwnerFundsWithdrawn(owner(), amountSun);
    }

    function depositOwnerFunds() external payable onlyOwner {
        require(msg.value > 0, "Zero value");
        ownerAvailableBalance += msg.value;
        emit ManualOwnerDeposit(msg.sender, msg.value);
    }

    function creditManualReward(address ambassadorAddress, uint256 amountSun) external onlyOwner {
        _validateAmbassadorExists(ambassadorAddress);
        require(amountSun > 0, "Amount zero");
        require(amountSun <= ownerAvailableBalance, "Insufficient owner balance");

        ownerAvailableBalance -= amountSun;

        Ambassador storage a = _ambassadors[ambassadorAddress];
        a.totalRewardsAccruedSun += amountSun;
        a.claimableRewardsSun += amountSun;

        totalReservedRewards += amountSun;
        totalRewardsAccruedSun += amountSun;

        emit ReferralRewardAccrued(address(0), ambassadorAddress, 0, amountSun, _getEffectiveLevel(ambassadorAddress));
    }

    function debitReservedReward(address ambassadorAddress, uint256 amountSun) external onlyOwner {
        _validateAmbassadorExists(ambassadorAddress);
        require(amountSun > 0, "Amount zero");

        Ambassador storage a = _ambassadors[ambassadorAddress];
        require(amountSun <= a.claimableRewardsSun, "Insufficient claimable");

        a.claimableRewardsSun -= amountSun;
        totalReservedRewards -= amountSun;
        ownerAvailableBalance += amountSun;

        emit ReservedRewardDebited(ambassadorAddress, amountSun);
    }

    // =========================
    // Read functions - Fourteen
    // =========================

    function getFourteenOwner() external view returns (address) { return fourteenToken.owner(); }
    function getFourteenLiquidityPool() external view returns (address) { return fourteenToken.liquidityPool(); }
    function getFourteenAirdropAddress() external view returns (address) { return fourteenToken.airdropAddress(); }
    function getFourteenAnnualGrowthRate() external view returns (uint256) { return fourteenToken.annualGrowthRate(); }
    function getFourteenStoredTokenPrice() external view returns (uint256) { return fourteenToken.tokenPrice(); }
    function getFourteenLastPriceUpdate() external view returns (uint256) { return fourteenToken.lastPriceUpdate(); }
    function getFourteenPriceUpdateInterval() external view returns (uint256) { return fourteenToken.priceUpdateInterval(); }

    function previewFourteenCurrentPrice() external view returns (uint256) {
        uint256 storedPrice = fourteenToken.tokenPrice();
        uint256 lastUpdate = fourteenToken.lastPriceUpdate();
        uint256 interval = fourteenToken.priceUpdateInterval();
        uint256 rate = fourteenToken.annualGrowthRate();

        if (block.timestamp <= lastUpdate || interval == 0) {
            return storedPrice;
        }

        uint256 elapsed = (block.timestamp - lastUpdate) / interval;
        uint256 price = storedPrice;

        for (uint256 i = 0; i < elapsed; i++) {
            price = (price * (10000 + rate)) / 10000;
        }

        return price;
    }

    // =========================
    // Read functions - dashboard / ambassador
    // =========================

    function ambassadorExists(address ambassadorAddress) external view returns (bool) {
        return _ambassadors[ambassadorAddress].exists;
    }

    function ambassadorActive(address ambassadorAddress) external view returns (bool) {
        return _ambassadors[ambassadorAddress].active;
    }

    function ambassadorFlags(address ambassadorAddress) external view returns (bool, bool, bool) {
        Ambassador storage a = _ambassadors[ambassadorAddress];
        return (a.selfRegistered, a.manualAssigned, a.overrideEnabled);
    }

    function ambassadorLevels(address ambassadorAddress) external view returns (uint8, uint8, uint8) {
        Ambassador storage a = _ambassadors[ambassadorAddress];
        return (_getEffectiveLevel(ambassadorAddress), a.currentLevel, a.overrideLevel);
    }

    function ambassadorStats1(address ambassadorAddress) external view returns (uint256, uint256, uint256) {
        Ambassador storage a = _ambassadors[ambassadorAddress];
        return (a.totalBuyers, a.totalVolumeSun, a.totalRewardsAccruedSun);
    }

    function ambassadorStats2(address ambassadorAddress) external view returns (uint256, uint256, uint256) {
        Ambassador storage a = _ambassadors[ambassadorAddress];
        return (a.totalRewardsClaimedSun, a.claimableRewardsSun, a.createdAt);
    }

    function ambassadorMeta(address ambassadorAddress) external view returns (bytes32, bytes32) {
        Ambassador storage a = _ambassadors[ambassadorAddress];
        return (a.slugHash, a.metaHash);
    }

    function getDashboardCore(address ambassadorAddress)
        external
        view
        returns (
            bool exists,
            bool active,
            uint8 effectiveLevel,
            uint256 rewardPercent,
            uint256 createdAt
        )
    {
        Ambassador storage a = _ambassadors[ambassadorAddress];
        exists = a.exists;
        active = a.active;
        effectiveLevel = _getEffectiveLevel(ambassadorAddress);
        rewardPercent = _getRewardPercentByLevel(effectiveLevel);
        createdAt = a.createdAt;
    }

    function getDashboardStats(address ambassadorAddress)
        external
        view
        returns (
            uint256 totalBuyers,
            uint256 totalVolumeSun,
            uint256 totalRewardsAccruedSun,
            uint256 totalRewardsClaimedSun,
            uint256 claimableRewardsSun
        )
    {
        Ambassador storage a = _ambassadors[ambassadorAddress];
        totalBuyers = a.totalBuyers;
        totalVolumeSun = a.totalVolumeSun;
        totalRewardsAccruedSun = a.totalRewardsAccruedSun;
        totalRewardsClaimedSun = a.totalRewardsClaimedSun;
        claimableRewardsSun = a.claimableRewardsSun;
    }

    function getDashboardProfile(address ambassadorAddress)
        external
        view
        returns (
            bool selfRegistered,
            bool manualAssigned,
            bool overrideEnabled,
            uint8 currentLevel,
            uint8 overrideLevel,
            bytes32 slugHash,
            bytes32 metaHash
        )
    {
        Ambassador storage a = _ambassadors[ambassadorAddress];
        selfRegistered = a.selfRegistered;
        manualAssigned = a.manualAssigned;
        overrideEnabled = a.overrideEnabled;
        currentLevel = a.currentLevel;
        overrideLevel = a.overrideLevel;
        slugHash = a.slugHash;
        metaHash = a.metaHash;
    }

    function getClaimableRewards(address ambassadorAddress) external view returns (uint256) {
        return _ambassadors[ambassadorAddress].claimableRewardsSun;
    }

    function getEffectiveLevel(address ambassadorAddress) external view returns (uint8) {
        return _getEffectiveLevel(ambassadorAddress);
    }

    function getAmbassadorPayoutData(address ambassadorAddress)
        external
        view
        returns (
            uint256 claimableRewardsSun,
            uint256 totalRewardsAccruedSun,
            uint256 totalRewardsClaimedSun
        )
    {
        Ambassador storage a = _ambassadors[ambassadorAddress];
        claimableRewardsSun = a.claimableRewardsSun;
        totalRewardsAccruedSun = a.totalRewardsAccruedSun;
        totalRewardsClaimedSun = a.totalRewardsClaimedSun;
    }

    function getMyReferralStats(address ambassadorAddress)
        external
        view
        returns (
            uint256 totalBuyers,
            uint256 totalVolumeSun,
            uint256 totalRewardsAccruedSun,
            uint256 claimableRewardsSun
        )
    {
        Ambassador storage a = _ambassadors[ambassadorAddress];
        totalBuyers = a.totalBuyers;
        totalVolumeSun = a.totalVolumeSun;
        totalRewardsAccruedSun = a.totalRewardsAccruedSun;
        claimableRewardsSun = a.claimableRewardsSun;
    }

    function getRewardPercent(address ambassadorAddress) external view returns (uint256) {
        return _getRewardPercentByLevel(_getEffectiveLevel(ambassadorAddress));
    }

    function getRewardPercentByLevel(uint8 level) external pure returns (uint256) {
        return _getRewardPercentByLevel(level);
    }

    function getLevelByBuyerCount(uint256 buyersCount) external pure returns (uint8) {
        return _getAutoLevelByBuyerCount(buyersCount);
    }

    function getAmbassadorLevelProgress(address ambassadorAddress) external view returns (uint8, uint256, uint256, uint256) {
        Ambassador storage a = _ambassadors[ambassadorAddress];
        uint8 currentLevel = _getEffectiveLevel(ambassadorAddress);
        uint256 buyersCount = a.totalBuyers;

        if (currentLevel == uint8(Level.Platinum)) {
            return (currentLevel, buyersCount, 1000, 0);
        }
        if (currentLevel == uint8(Level.Gold)) {
            return (currentLevel, buyersCount, 1000, buyersCount >= 1000 ? 0 : 1000 - buyersCount);
        }
        if (currentLevel == uint8(Level.Silver)) {
            return (currentLevel, buyersCount, 100, buyersCount >= 100 ? 0 : 100 - buyersCount);
        }
        return (currentLevel, buyersCount, 10, buyersCount >= 10 ? 0 : 10 - buyersCount);
    }

    // =========================
    // Read functions - buyer/system
    // =========================

    function getBuyerAmbassador(address buyer) external view returns (address) {
        return buyerToAmbassador[buyer];
    }

    function isBuyerBound(address buyer) external view returns (bool) {
        return buyerToAmbassador[buyer] != address(0);
    }

    function isSlugTaken(bytes32 slugHash) external view returns (bool) {
        return slugToAmbassador[slugHash] != address(0);
    }

    function getAmbassadorBySlugHash(bytes32 slugHash) external view returns (address) {
        return slugToAmbassador[slugHash];
    }

    function getOwnerBalance() external view returns (uint256) { return ownerAvailableBalance; }
    function getReservedRewardsBalance() external view returns (uint256) { return totalReservedRewards; }
    function getUnallocatedPurchaseFunds() external view returns (uint256) { return unallocatedPurchaseFunds; }
    function getControllerTRXBalance() external view returns (uint256) { return address(this).balance; }

    function getSystemCounts() external view returns (uint256, uint256, uint256) {
        return (totalAmbassadors, activeAmbassadors, totalBoundBuyers);
    }

    function getSystemRewards() external view returns (uint256, uint256, uint256) {
        return (totalTrackedVolumeSun, totalRewardsAccruedSun, totalRewardsClaimedSun);
    }

    function getSystemBalances() external view returns (uint256, uint256, uint256, uint256) {
        return (address(this).balance, ownerAvailableBalance, totalReservedRewards, unallocatedPurchaseFunds);
    }

    function getSystemStats()
        external
        view
        returns (
            uint256 ambassadorsCount,
            uint256 activeAmbassadorsCount,
            uint256 boundBuyersCount,
            uint256 trackedVolume,
            uint256 rewardsAccrued,
            uint256 rewardsClaimed
        )
    {
        ambassadorsCount = totalAmbassadors;
        activeAmbassadorsCount = activeAmbassadors;
        boundBuyersCount = totalBoundBuyers;
        trackedVolume = totalTrackedVolumeSun;
        rewardsAccrued = totalRewardsAccruedSun;
        rewardsClaimed = totalRewardsClaimedSun;
    }

    function isPurchaseProcessed(bytes32 purchaseId) external view returns (bool) {
        return processedPurchases[purchaseId];
    }

    // =========================
    // Internal
    // =========================

    function _bindBuyerToAmbassador(address buyer, address ambassadorAddress) internal {
        require(buyer != address(0), "Buyer zero");
        require(ambassadorAddress != address(0), "Ambassador zero");
        require(buyerToAmbassador[buyer] == address(0), "Buyer already bound");
        require(buyer != ambassadorAddress, "Self-referral forbidden");

        _validateAmbassadorForNewBinding(ambassadorAddress);

        buyerToAmbassador[buyer] = ambassadorAddress;

        Ambassador storage a = _ambassadors[ambassadorAddress];
        a.totalBuyers += 1;
        totalBoundBuyers += 1;

        _refreshAutoLevel(ambassadorAddress);

        emit BuyerBound(buyer, ambassadorAddress);
    }

    function _refreshAutoLevel(address ambassadorAddress) internal {
        Ambassador storage a = _ambassadors[ambassadorAddress];
        if (!a.exists || a.overrideEnabled) {
            return;
        }
        a.currentLevel = _getAutoLevelByBuyerCount(a.totalBuyers);
    }

    function _getEffectiveLevel(address ambassadorAddress) internal view returns (uint8) {
        Ambassador storage a = _ambassadors[ambassadorAddress];
        if (!a.exists) return uint8(Level.Bronze);
        if (a.overrideEnabled) return a.overrideLevel;
        return a.currentLevel;
    }

    function _getRewardPercentByLevel(uint8 level) internal pure returns (uint256) {
        if (level == uint8(Level.Bronze)) return 10;
        if (level == uint8(Level.Silver)) return 25;
        if (level == uint8(Level.Gold)) return 50;
        if (level == uint8(Level.Platinum)) return 75;
        revert("Invalid level");
    }

    function _getAutoLevelByBuyerCount(uint256 buyersCount) internal pure returns (uint8) {
        if (buyersCount >= 1000) return uint8(Level.Platinum);
        if (buyersCount >= 100) return uint8(Level.Gold);
        if (buyersCount >= 10) return uint8(Level.Silver);
        return uint8(Level.Bronze);
    }

    function _validateLevel(uint8 level) internal pure {
        require(level <= uint8(Level.Platinum), "Invalid level");
    }

    function _validateAmbassadorExists(address ambassadorAddress) internal view {
        require(ambassadorAddress != address(0), "Ambassador zero");
        require(_ambassadors[ambassadorAddress].exists, "Ambassador not found");
    }

    function _validateAmbassadorForNewBinding(address ambassadorAddress) internal view {
        _validateAmbassadorExists(ambassadorAddress);
        require(_ambassadors[ambassadorAddress].active, "Ambassador inactive");
    }
}
