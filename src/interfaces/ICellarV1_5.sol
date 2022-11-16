pragma solidity ^0.8.10;

interface ICellarV1_5 {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event DepositLimitChanged(uint256 oldLimit, uint256 newLimit);
    event FeesDistributorChanged(bytes32 oldFeesDistributor, bytes32 newFeesDistributor);
    event HighWatermarkReset(uint256 newHighWatermark);
    event HoldingPositionChanged(address indexed oldPosition, address indexed newPosition);
    event LiquidityLimitChanged(uint256 oldLimit, uint256 newLimit);
    event OwnerUpdated(address indexed user, address indexed newOwner);
    event PerformanceFeeChanged(uint64 oldPerformanceFee, uint64 newPerformanceFee);
    event PlatformFeeChanged(uint64 oldPlatformFee, uint64 newPlatformFee);
    event PositionAdded(address indexed position, uint256 index);
    event PositionRemoved(address indexed position, uint256 index);
    event PositionSwapped(address indexed newPosition1, address indexed newPosition2, uint256 index1, uint256 index2);
    event PulledFromPosition(address indexed position, uint256 amount);
    event Rebalance(address indexed fromPosition, address indexed toPosition, uint256 assetsFrom, uint256 assetsTo);
    event RebalanceDeviationChanged(uint256 oldDeviation, uint256 newDeviation);
    event SendFees(uint256 feesInSharesRedeemed, uint256 feesInAssetsSent);
    event ShareLockingPeriodChanged(uint256 oldPeriod, uint256 newPeriod);
    event ShutdownChanged(bool isShutdown);
    event StrategistPayoutAddressChanged(address oldPayoutAddress, address newPayoutAddress);
    event StrategistPerformanceCutChanged(uint64 oldPerformanceCut, uint64 newPerformanceCut);
    event StrategistPlatformCutChanged(uint64 oldPlatformCut, uint64 newPlatformCut);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event TrustChanged(address indexed position, bool isTrusted);
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event WithdrawTypeChanged(uint8 oldType, uint8 newType);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function MAXIMUM_SHARE_LOCK_PERIOD() external view returns (uint256);

    function MAX_FEE_CUT() external view returns (uint64);

    function MAX_PERFORMANCE_FEE() external view returns (uint64);

    function MAX_PLATFORM_FEE() external view returns (uint64);

    function MAX_POSITIONS() external view returns (uint8);

    function MAX_REBALANCE_DEVIATION() external view returns (uint64);

    function MINIMUM_SHARE_LOCK_PERIOD() external view returns (uint256);

    function PRICE_ROUTER_REGISTRY_SLOT() external view returns (uint256);

    function addPosition(uint256 index, address position) external;

    function allowance(address owner, address spender) external view returns (uint256);

    function allowedRebalanceDeviation() external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function asset() external view returns (address);

    function balanceOf(address account) external view returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    function convertToShares(uint256 assets) external view returns (uint256 shares);

    function decimals() external view returns (uint8);

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function depositLimit() external view returns (uint256);

    function feeData()
        external
        view
        returns (
            uint256 highWatermark,
            uint64 strategistPerformanceCut,
            uint64 strategistPlatformCut,
            uint64 platformFee,
            uint64 performanceFee,
            bytes32 feesDistributor,
            address strategistPayoutAddress
        );

    function getPositionType(address) external view returns (uint8);

    function getPositions() external view returns (address[] memory);

    function holdingPosition() external view returns (address);

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);

    function initiateShutdown() external;

    function isPositionUsed(address) external view returns (bool);

    function isShutdown() external view returns (bool);

    function isTrusted(address) external view returns (bool);

    function lastAccrual() external view returns (uint64);

    function liftShutdown() external;

    function liquidityLimit() external view returns (uint256);

    function maxDeposit(address receiver) external view returns (uint256 assets);

    function maxMint(address receiver) external view returns (uint256);

    function maxRedeem(address owner) external view returns (uint256);

    function maxWithdraw(address owner) external view returns (uint256);

    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    function name() external view returns (string memory);

    function nonces(address owner) external view returns (uint256);

    function owner() external view returns (address);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function positions(uint256) external view returns (address);

    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    function previewMint(uint256 shares) external view returns (uint256 assets);

    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    function pushPosition(address position) external;

    function rebalance(
        address fromPosition,
        address toPosition,
        uint256 assetsFrom,
        uint8 exchange,
        bytes memory params
    ) external returns (uint256 assetsTo);

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets);

    function registry() external view returns (address);

    function removePosition(uint256 index) external;

    function resetHighWatermark() external;

    function sendFees() external;

    function setDepositLimit(uint256 newLimit) external;

    function setFeesDistributor(bytes32 newFeesDistributor) external;

    function setHoldingPosition(address newHoldingPosition) external;

    function setLiquidityLimit(uint256 newLimit) external;

    function setOwner(address newOwner) external;

    function setPerformanceFee(uint64 newPerformanceFee) external;

    function setPlatformFee(uint64 newPlatformFee) external;

    function setRebalanceDeviation(uint256 newDeviation) external;

    function setShareLockPeriod(uint256 newLock) external;

    function setStrategistPayoutAddress(address payout) external;

    function setStrategistPerformanceCut(uint64 cut) external;

    function setStrategistPlatformCut(uint64 cut) external;

    function setWithdrawType(uint8 newWithdrawType) external;

    function shareLockPeriod() external view returns (uint256);

    function swapPositions(uint256 index1, uint256 index2) external;

    function symbol() external view returns (string memory);

    function totalAssets() external view returns (uint256 assets);

    function totalAssetsWithdrawable() external view returns (uint256 assets);

    function totalSupply() external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function trustPosition(address position, uint8 positionType) external;

    function userShareLockStartBlock(address) external view returns (uint256);

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares);

    function withdrawType() external view returns (uint8);
}
