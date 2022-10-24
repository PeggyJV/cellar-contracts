// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC4626, SafeERC20 } from "./ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IGravity } from "src/interfaces/external/IGravity.sol";
import { Uint32Array } from "src/utils/Uint32Array.sol";
import { Math } from "../utils/Math.sol";
import { Owned } from "@solmate/auth/Owned.sol";
import { ReentrancyGuard } from "@solmate/utils/ReentrancyGuard.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { Owned } from "@solmate/auth/Owned.sol";

import { console } from "@forge-std/Test.sol"; //TODO remove this

// import { Owned } from "@solmate/auth/Owned.sol";

// import { ReentrancyGuard } from "@solmate/utils/ReentrancyGuard.sol"; This implementation is slightly less size wise

/**
 * @title Sommelier Cellar
 * @notice A composable ERC4626 that can use a set of other ERC4626 or ERC20 positions to earn yield.
 * @author Brian Le, crispymangoes
 */
//TODO contract should use variable packing
//TODO look for public functions that can be made external.
//TODO use solmate Reentrancy, Ownable, and maybe ERC20 to cut down on size.
//TODO add multicall to adaptors so that we can use staticcall and multicall to batch view function calls together
contract Cellar is ERC4626, Owned, ReentrancyGuard, ERC721Holder {
    using Uint32Array for uint32[];
    using SafeERC20 for ERC20;
    using SafeCast for uint256;
    using Math for uint256;
    using Address for address;

    // ========================================= POSITIONS CONFIG =========================================

    /**
     * @notice Emitted when a position is added.
     * @param position address of position that was added
     * @param index index that position was added at
     */
    event PositionAdded(address indexed position, uint256 index);

    /**
     * @notice Emitted when a position is removed.
     * @param position address of position that was removed
     * @param index index that position was removed from
     */
    event PositionRemoved(address indexed position, uint256 index);

    /**
     * @notice Emitted when the positions at two indexes are swapped.
     * @param newPosition1 address of position (previously at index2) that replaced index1.
     * @param newPosition2 address of position (previously at index1) that replaced index2.
     * @param index1 index of first position involved in the swap
     * @param index2 index of second position involved in the swap.
     */
    event PositionSwapped(address indexed newPosition1, address indexed newPosition2, uint256 index1, uint256 index2);

    /**
     * @notice Attempted an operation on an untrusted position.
     * @param position address of the position
     */
    error Cellar__UntrustedPosition(address position);

    /**
     * @notice Attempted to add a position that is already being used.
     * @param position address of the position
     */
    error Cellar__PositionAlreadyUsed(uint256 position);

    /**
     * @notice Attempted an action on a position that is required to be empty before the action can be performed.
     * @param position address of the non-empty position
     * @param sharesRemaining amount of shares remaining in the position
     */
    error Cellar__PositionNotEmpty(uint256 position, uint256 sharesRemaining);

    /**
     * @notice Attempted an operation with an asset that was different then the one expected.
     * @param asset address of the asset
     * @param expectedAsset address of the expected asset
     */
    error Cellar__AssetMismatch(address asset, address expectedAsset);

    /**
     * @notice Attempted an action on a position that is not being used by the cellar but must be for
     *         the operation to succeed.
     * @param position address of the invalid position
     */
    error Cellar__InvalidPosition(address position);

    /**
     * @notice Attempted to add a position when the position array is full.
     * @param maxPositions maximum number of positions that can be used
     */
    error Cellar__PositionArrayFull(uint256 maxPositions);

    /**
     * @notice Array of uint32s made up of cellars positions Ids.
     */
    //TODO I could probs get away with a fixed size array.
    uint32[] public positions;

    //TODO add natspec
    uint32 public numberOfDebtPositions;

    /**
     * @notice Tell whether a position is currently used.
     */
    mapping(uint256 => bool) public isPositionUsed;

    /**
     * @notice Get position data given position id.
     */
    mapping(uint32 => Registry.PositionData) public getPositionData;

    /**
     * @notice Get the addresses of the positions current used by the cellar.
     */
    function getPositions() external view returns (uint32[] memory) {
        return positions;
    }

    /**
     * @notice Maximum amount of positions a cellar can use at once.
     */
    uint256 public constant MAX_POSITIONS = 32;

    /**
     * @notice Insert a trusted position to the list of positions used by the cellar at a given index.
     * @param index index at which to insert the position
     * @param positionId address of position to add
     */
    function addPosition(
        uint32 index,
        uint32 positionId,
        bytes memory configurationData
    ) external onlyOwner whenNotShutdown {
        if (positions.length >= MAX_POSITIONS) revert Cellar__PositionArrayFull(MAX_POSITIONS);

        // Check if position is already being used.
        if (isPositionUsed[positionId]) revert Cellar__PositionAlreadyUsed(positionId);

        // Copy position data from registry to here.
        (address adaptor, bool isDebt, bytes memory adaptorData) = registry.cellarAddPosition(
            positionId,
            assetRiskTolerance,
            protocolRiskTolerance
        );
        getPositionData[positionId] = Registry.PositionData({
            adaptor: adaptor,
            isDebt: isDebt,
            adaptorData: adaptorData,
            configurationData: configurationData
        });

        if (index == 0 && _assetOf(positionId) != asset) revert("Holding position asset mismatch.");

        // Add new position at a specified index.
        positions.add(index, positionId);
        isPositionUsed[positionId] = true;
        if (isDebt) numberOfDebtPositions++;

        // emit PositionAdded(position, index);
    }

    /**
     * @notice Remove the position at a given index from the list of positions used by the cellar.
     * @param index index at which to remove the position
     */
    function removePosition(uint32 index) external onlyOwner {
        // Get position being removed.
        uint32 positionId = positions[index];

        // Only remove position if it is empty, and if it is not the holding position.
        uint256 positionBalance = _balanceOf(positionId);
        if (positionBalance > 0) revert Cellar__PositionNotEmpty(positionId, positionBalance);

        // If removing the holding position, make sure new holding position is valid.
        if (index == 0 && _assetOf(positions[1]) != asset) revert("Holding position asset mismatch.");

        // Remove position at the given index.
        positions.remove(index);
        isPositionUsed[positionId] = false;
        if (getPositionData[positionId].isDebt) numberOfDebtPositions--;
        delete getPositionData[positionId];

        // emit PositionRemoved(position, index);
    }

    /**
     * @notice Swap the positions at two given indexes.
     * @param index1 index of first position to swap
     * @param index2 index of second position to swap
     */
    function swapPositions(uint32 index1, uint32 index2) external onlyOwner {
        // Get the new positions that will be at each index.
        uint32 newPosition1 = positions[index2];
        uint32 newPosition2 = positions[index1];

        // Swap positions.
        (positions[index1], positions[index2]) = (newPosition1, newPosition2);

        // If we swapped with the holding position make sure new holding position works.
        if ((index1 == 0 || index2 == 0) && _assetOf(positions[0]) != asset) revert("Holding position asset mismatch.");

        // emit PositionSwapped(newPosition1, newPosition2, index1, index2);
    }

    // =============================================== FEES CONFIG ===============================================

    /**
     * @notice Emitted when platform fees is changed.
     * @param oldPlatformFee value platform fee was changed from
     * @param newPlatformFee value platform fee was changed to
     */
    event PlatformFeeChanged(uint64 oldPlatformFee, uint64 newPlatformFee);

    /**
     * @notice Emitted when fees distributor is changed.
     * @param oldFeesDistributor address of fee distributor was changed from
     * @param newFeesDistributor address of fee distributor was changed to
     */
    event FeesDistributorChanged(bytes32 oldFeesDistributor, bytes32 newFeesDistributor);

    /**
     * @notice Emitted when strategist platform fee cut is changed.
     * @param oldPlatformCut value strategist platform fee cut was changed from
     * @param newPlatformCut value strategist platform fee cut was changed to
     */
    event StrategistPlatformCutChanged(uint64 oldPlatformCut, uint64 newPlatformCut);

    /**
     * @notice Emitted when strategists payout address is changed.
     * @param oldPayoutAddress value strategists payout address was changed from
     * @param newPayoutAddress value strategists payout address was changed to
     */
    event StrategistPayoutAddressChanged(address oldPayoutAddress, address newPayoutAddress);

    /**
     * @notice Attempted to use an invalid cosmos address.
     */
    error Cellar__InvalidCosmosAddress();

    /**
     * @notice Attempted to change strategist fee cut with invalid value.
     */
    error Cellar__InvalidFeeCut();

    /**
     * @notice Attempted to change platform fee with invalid value.
     */
    error Cellar__InvalidFee();

    /**
     * @notice Data related to fees.
     * @param strategistPlatformCut Determines how much platform fees go to strategist.
     *                              This should be a value out of 1e18 (ie. 1e18 represents 100%, 0 represents 0%).
     * @param platformFee The percentage of total assets accrued as platform fees over a year.
                          This should be a value out of 1e18 (ie. 1e18 represents 100%, 0 represents 0%).
     * @param feesDistributor Cosmos address of module that distributes fees, specified as a hex value.
     *                        The Gravity contract expects a 32-byte value formatted in a specific way.
     * @param strategistPayoutAddress Address to send the strategists fee shares.
     */
    struct FeeData {
        uint64 strategistPlatformCut;
        uint64 platformFee;
        uint64 lastAccrual;
        bytes32 feesDistributor;
        address strategistPayoutAddress;
    }

    /**
     * @notice Stores all fee data for cellar.
     */
    FeeData public feeData =
        FeeData({
            strategistPlatformCut: 0.75e18,
            platformFee: 0.01e18,
            lastAccrual: 0,
            feesDistributor: hex"000000000000000000000000b813554b423266bbd4c16c32fa383394868c1f55", // 20 bytes, so need 12 bytes of zero
            strategistPayoutAddress: address(0)
        });

    uint64 public constant MAX_PLATFORM_FEE = 0.2e18;
    uint64 public constant MAX_FEE_CUT = 1e18;

    /**
     * @notice Set the percentage of platform fees accrued over a year.
     * @param newPlatformFee value out of 1e18 that represents new platform fee percentage
     */
    function setPlatformFee(uint64 newPlatformFee) external onlyOwner {
        if (newPlatformFee > MAX_PLATFORM_FEE) revert Cellar__InvalidFee();
        emit PlatformFeeChanged(feeData.platformFee, newPlatformFee);

        feeData.platformFee = newPlatformFee;
    }

    /**
     * @notice Set the address of the fee distributor on the Sommelier chain.
     * @dev IMPORTANT: Ensure that the address is formatted in the specific way that the Gravity contract
     *      expects it to be.
     * @param newFeesDistributor formatted address of the new fee distributor module
     */
    function setFeesDistributor(bytes32 newFeesDistributor) external onlyOwner {
        if (uint256(newFeesDistributor) > type(uint160).max) revert Cellar__InvalidCosmosAddress();
        emit FeesDistributorChanged(feeData.feesDistributor, newFeesDistributor);

        feeData.feesDistributor = newFeesDistributor;
    }

    /**
     * @notice Sets the Strategists cut of platform fees
     * @param cut the platform cut for the strategist
     */
    function setStrategistPlatformCut(uint64 cut) external onlyOwner {
        if (cut > MAX_FEE_CUT) revert Cellar__InvalidFeeCut();
        emit StrategistPlatformCutChanged(feeData.strategistPlatformCut, cut);

        feeData.strategistPlatformCut = cut;
    }

    /**
     * @notice Sets the Strategists payout address
     * @param payout the new strategist payout address
     */
    function setStrategistPayoutAddress(address payout) external onlyOwner {
        emit StrategistPayoutAddressChanged(feeData.strategistPayoutAddress, payout);

        feeData.strategistPayoutAddress = payout;
    }

    // =========================================== EMERGENCY LOGIC ===========================================

    /**
     * @notice Emitted when cellar emergency state is changed.
     * @param isShutdown whether the cellar is shutdown
     */
    event ShutdownChanged(bool isShutdown);

    /**
     * @notice Attempted action was prevented due to contract being shutdown.
     */
    error Cellar__ContractShutdown();

    /**
     * @notice Attempted action was prevented due to contract not being shutdown.
     */
    error Cellar__ContractNotShutdown();

    /**
     * @notice Whether or not the contract is shutdown in case of an emergency.
     */
    bool public isShutdown;

    /**
     * @notice Prevent a function from being called during a shutdown.
     */
    modifier whenNotShutdown() {
        if (isShutdown) revert Cellar__ContractShutdown();

        _;
    }

    /**
     * @notice Shutdown the cellar. Used in an emergency or if the cellar has been deprecated.
     * @dev In the case where
     */
    function initiateShutdown() external whenNotShutdown onlyOwner {
        isShutdown = true;

        emit ShutdownChanged(true);
    }

    /**
     * @notice Restart the cellar.
     */
    function liftShutdown() external onlyOwner {
        if (!isShutdown) revert Cellar__ContractNotShutdown();
        isShutdown = false;

        emit ShutdownChanged(false);
    }

    // =========================================== CONSTRUCTOR ===========================================

    /**
     * @notice Addresses of the positions currently used by the cellar.
     */
    uint256 public constant PRICE_ROUTER_REGISTRY_SLOT = 2;

    /**
     * @notice Address of the platform's registry contract. Used to get the latest address of modules.
     */
    Registry public immutable registry;

    // Below values determine what positions and adaptors this cellar can use.
    uint128 public immutable assetRiskTolerance; // 0 safest -> uint128 max no restrictions

    uint128 public immutable protocolRiskTolerance; // 0 safest -> uint256 max no restrictions

    /**
     * @dev Owner should be set to the Gravity Bridge, which relays instructions from the Steward
     *      module to the cellars.
     *      https://github.com/PeggyJV/steward
     *      https://github.com/cosmos/gravity-bridge/blob/main/solidity/contracts/Gravity.sol
     * @param _registry address of the platform's registry contract
     * @param _asset address of underlying token used for the for accounting, depositing, and withdrawing
     * @param _positions addresses of the positions to initialize the cellar with
     * @param _name name of this cellar's share token
     * @param _name symbol of this cellar's share token
     * @param _strategistPayout The address to send the strategists fee shares.
     */
    constructor(
        Registry _registry,
        ERC20 _asset,
        uint32[] memory _positions,
        bytes[] memory _configurationData,
        string memory _name,
        string memory _symbol,
        address _strategistPayout,
        uint128 _assetRiskTolerance,
        uint128 _protocolRiskTolerance
    ) ERC4626(_asset, _name, _symbol) Owned(_registry.getAddress(0)) {
        registry = _registry;
        assetRiskTolerance = _assetRiskTolerance;
        protocolRiskTolerance = _protocolRiskTolerance;

        // Initialize positions.
        positions = _positions;
        for (uint256 i; i < _positions.length; i++) {
            uint32 position = _positions[i];

            // if (isPositionUsed[position]) revert Cellar__PositionAlreadyUsed(position);

            (address adaptor, bool isDebt, bytes memory adaptorData) = registry.cellarAddPosition(
                position,
                _assetRiskTolerance,
                _protocolRiskTolerance
            );

            require(adaptor != address(0), "Position does not exist.");

            isPositionUsed[position] = true;
            getPositionData[position] = Registry.PositionData({
                adaptor: adaptor,
                isDebt: isDebt,
                adaptorData: adaptorData,
                configurationData: _configurationData[i]
            });
            if (isDebt) numberOfDebtPositions++;
        }

        // Initialize holding position.
        // Holding position is the zero position.
        ERC20 holdingPositionAsset = _assetOf(_positions[0]);
        if (holdingPositionAsset != _asset)
            revert Cellar__AssetMismatch(address(holdingPositionAsset), address(_asset));

        // Initialize last accrual timestamp to time that cellar was created, otherwise the first
        // `accrue` will take platform fees from 1970 to the time it is called.
        feeData.lastAccrual = uint64(block.timestamp);

        feeData.strategistPayoutAddress = _strategistPayout;
    }

    // =========================================== CORE LOGIC ===========================================

    /**
     * @notice Emitted when withdraws are made from a position.
     * @param position the position assets were withdrawn from
     * @param amount the amount of assets withdrawn
     */
    event PulledFromPosition(address indexed position, uint256 amount);

    /**
     * @notice Emitted when share locking period is changed.
     * @param oldPeriod the old locking period
     * @param newPeriod the new locking period
     */
    event ShareLockingPeriodChanged(uint256 oldPeriod, uint256 newPeriod);

    /**
     * @notice Attempted an action with zero shares.
     */
    error Cellar__ZeroShares();

    /**
     * @notice Attempted an action with zero assets.
     */
    error Cellar__ZeroAssets();

    /**
     * @notice Withdraw did not withdraw all assets.
     * @param assetsOwed the remaining assets owed that were not withdrawn.
     */
    error Cellar__IncompleteWithdraw(uint256 assetsOwed);

    /**
     * @notice Attempted to withdraw an illiquid position.
     * @param illiquidPosition the illiquid position.
     */
    error Cellar__IlliquidWithdraw(address illiquidPosition);

    /**
     * @notice Attempted to set `shareLockPeriod` to an invalid number.
     */
    error Cellar__InvalidShareLockPeriod();

    /**
     * @notice Attempted to burn shares when they are locked.
     * @param blockSharesAreUnlocked the block number when caller can transfer/redeem shares
     * @param currentBlock the current block number.
     */
    error Cellar__SharesAreLocked(uint256 blockSharesAreUnlocked, uint256 currentBlock);

    /**
     * @notice Attempted deposit on behalf of a user without being approved.
     */
    error Cellar__NotApprovedToDepositOnBehalf(address depositor);

    /**
     * @notice Shares must be locked for atleaset 8 blocks after minting.
     */
    uint256 public constant MINIMUM_SHARE_LOCK_PERIOD = 8;

    /**
     * @notice Shares can be locked for at most 7200 blocks after minting.
     */
    uint256 public constant MAXIMUM_SHARE_LOCK_PERIOD = 7200;

    /**
     * @notice After deposits users must wait `shareLockPeriod` blocks before being able to transfer or withdraw their shares.
     */
    uint256 public shareLockPeriod = MAXIMUM_SHARE_LOCK_PERIOD;

    /**
     * @notice mapping that stores every users last block they minted shares.
     */
    mapping(address => uint256) public userShareLockStartBlock;

    /**
     * @notice Allows share lock period to be updated.
     * @param newLock the new lock period
     */
    function setShareLockPeriod(uint256 newLock) external onlyOwner {
        if (newLock < MINIMUM_SHARE_LOCK_PERIOD || newLock > MAXIMUM_SHARE_LOCK_PERIOD)
            revert Cellar__InvalidShareLockPeriod();
        uint256 oldLockingPeriod = shareLockPeriod;
        shareLockPeriod = newLock;
        emit ShareLockingPeriodChanged(oldLockingPeriod, newLock);
    }

    /**
     * @notice helper function that checks enough blocks have passed to unlock shares.
     * @param owner the address of the user to check
     */
    function _checkIfSharesLocked(address owner) internal view {
        uint256 lockBlock = userShareLockStartBlock[owner];
        if (lockBlock != 0) {
            uint256 blockSharesAreUnlocked = lockBlock + shareLockPeriod;
            if (blockSharesAreUnlocked > block.number)
                revert Cellar__SharesAreLocked(blockSharesAreUnlocked, block.number);
        }
    }

    /**
     * @notice modifies before transfer hook to check that shares are not locked
     * @param from the address transferring shares
     */
    function _beforeTokenTransfer(
        address from,
        address,
        uint256
    ) internal view override {
        _checkIfSharesLocked(from);
    }

    /**
     * @notice Attempted deposit more than the max deposit.
     * @param assets the assets user attempted to deposit
     * @param maxDeposit the max assets that can be deposited
     */
    error Cellar__DepositRestricted(uint256 assets, uint256 maxDeposit);

    /**
     * @notice called at the beginning of deposit.
     * @param assets amount of assets deposited by user.
     * @param receiver address receiving the shares.
     */
    function beforeDeposit(
        uint256 assets,
        uint256,
        address receiver
    ) internal view override whenNotShutdown {
        if (msg.sender != receiver) {
            if (!registry.approvedForDepositOnBehalf(msg.sender))
                revert Cellar__NotApprovedToDepositOnBehalf(msg.sender);
        }
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) revert Cellar__DepositRestricted(assets, maxAssets);
    }

    /**
     * @notice called at the end of deposit.
     * @param assets amount of assets deposited by user.
     */
    function afterDeposit(
        uint256 assets,
        uint256,
        address receiver
    ) internal override {
        _depositTo(positions[0], assets);
        userShareLockStartBlock[receiver] = block.number;
    }

    /**
     * @notice called at the beginning of withdraw.
     */
    function beforeWithdraw(
        uint256,
        uint256,
        address,
        address owner
    ) internal view override {
        // Make sure users shares are not locked.
        _checkIfSharesLocked(owner);
    }

    function _enter(
        uint256 assets,
        uint256 shares,
        address receiver
    ) internal {
        beforeDeposit(assets, shares, receiver);

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares, receiver);
    }

    /**
     * @notice Deposits assets into the cellar, and returns shares to receiver.
     * @param assets amount of assets deposited by user.
     * @param receiver address to receive the shares.
     * @return shares amount of shares given for deposit.
     */
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        uint256 _totalAssets = totalAssets();

        // Check for rounding error since we round down in previewDeposit.
        if ((shares = _convertToShares(assets, _totalAssets)) == 0) revert Cellar__ZeroShares();

        _enter(assets, shares, receiver);
    }

    /**
     * @notice Mints shares from the cellar, and returns shares to receiver.
     * @param shares amount of shares requested by user.
     * @param receiver address to receive the shares.
     * @return assets amount of assets deposited into the cellar.
     */
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        uint256 _totalAssets = totalAssets();

        // previewMintRoundsUp, but iniital mint could return zero assets, so check for rounding error.
        if ((assets = _previewMint(shares, _totalAssets)) == 0) revert Cellar__ZeroAssets(); // No need to check for rounding error, previewMint rounds up.

        _enter(assets, shares, receiver);
    }

    function _exit(
        uint256 assets,
        uint256 shares,
        address receiver,
        address owner
    ) internal {
        beforeWithdraw(assets, shares, receiver, owner);

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        _withdrawInOrder(assets, receiver);

        /// @notice `afterWithdraw` is currently not used.
        // afterWithdraw(assets, shares, receiver, owner);
    }

    /**
     * @notice Withdraw assets from the cellar by redeeming shares.
     * @dev Unlike conventional ERC4626 contracts, this may not always return one asset to the receiver.
     *      Since there are no swaps involved in this function, the receiver may receive multiple
     *      assets. The value of all the assets returned will be equal to the amount defined by
     *      `assets` denominated in the `asset` of the cellar (eg. if `asset` is USDC and `assets`
     *      is 1000, then the receiver will receive $1000 worth of assets in either one or many
     *      tokens).
     * @param assets equivalent value of the assets withdrawn, denominated in the cellar's asset
     * @param receiver address that will receive withdrawn assets
     * @param owner address that owns the shares being redeemed
     * @return shares amount of shares redeemed
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
        // Get data efficiently.
        uint256 _totalAssets = totalAssets(); // Store totalHoldings and pass into _withdrawInOrder if no stack errors.

        // No need to check for rounding error, `previewWithdraw` rounds up.
        shares = _previewWithdraw(assets, _totalAssets);

        _exit(assets, shares, receiver, owner);
    }

    /**
     * @notice Redeem shares to withdraw assets from the cellar.
     * @dev Unlike conventional ERC4626 contracts, this may not always return one asset to the receiver.
     *      Since there are no swaps involved in this function, the receiver may receive multiple
     *      assets. The value of all the assets returned will be equal to the amount defined by
     *      `assets` denominated in the `asset` of the cellar (eg. if `asset` is USDC and `assets`
     *      is 1000, then the receiver will receive $1000 worth of assets in either one or many
     *      tokens).
     * @param shares amount of shares to redeem
     * @param receiver address that will receive withdrawn assets
     * @param owner address that owns the shares being redeemed
     * @return assets equivalent value of the assets withdrawn, denominated in the cellar's asset
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
        // Get data efficiently.
        uint256 _totalAssets = totalAssets();

        // Check for rounding error since we round down in previewRedeem.
        if ((assets = _convertToAssets(shares, _totalAssets)) == 0) revert Cellar__ZeroAssets();

        _exit(assets, shares, receiver, owner);
    }

    /**
     * @dev Withdraw from positions in the order defined by `positions`. Used if the withdraw type
     *      is `ORDERLY`.
     * @param assets the amount of assets to withdraw from cellar
     * @param receiver the address to sent withdrawn assets to
     */
    function _withdrawInOrder(uint256 assets, address receiver) internal {
        // Get the price router.
        PriceRouter priceRouter = PriceRouter(registry.getAddress(PRICE_ROUTER_REGISTRY_SLOT));

        for (uint256 i; i < positions.length; i++) {
            // Move on to next position if this one is empty.
            uint32 position = positions[i];
            if (_balanceOf(position) == 0) continue;
            ERC20 positionAsset = _assetOf(position);

            uint256 onePositionAsset = 10**positionAsset.decimals();
            uint256 exchangeRate = priceRouter.getExchangeRate(positionAsset, asset);

            // Denominate withdrawable position balance in cellar's asset.
            uint256 withdrawableBalance = _withdrawableFrom(position);
            uint256 totalWithdrawableBalanceInAssets = withdrawableBalance.mulDivDown(exchangeRate, onePositionAsset);

            // We want to pull as much as we can from this position, but no more than needed.
            uint256 amount;

            if (totalWithdrawableBalanceInAssets > assets) {
                amount = assets.mulDivDown(onePositionAsset, exchangeRate);
                assets = 0;
            } else {
                amount = withdrawableBalance;
                assets = assets - totalWithdrawableBalanceInAssets;
            }

            // Withdraw from position.
            _withdrawFrom(position, amount, receiver);

            // emit PulledFromPosition(position, amount);

            // Stop if no more assets to withdraw.
            if (assets == 0) break;
        }
        // If withdraw did not remove all assets owed, revert.
        if (assets > 0) revert Cellar__IncompleteWithdraw(assets);
    }

    // ========================================= ACCOUNTING LOGIC =========================================

    /**
     * @notice The total amount of assets in the cellar.
     * @dev EIP4626 states totalAssets needs to be inclusive of fees.
     * Since performance fees mint shares, total assets remains unchanged,
     * so this implementation is inclusive of fees even though it does not explicitly show it.
     * @dev EIP4626 states totalAssets must not revert, but it is possible for `totalAssets` to revert
     * so it does NOT conform to ERC4626 standards.
     */
    //TODO take this logic and make generalized internal function to replace this and withdrawable amount
    //TODO bonus now internal function could be used in place of totalAssets if it is cheaper.
    //TODO use multicall to reduxe external calls to adaptors, and possibly batch multiple positions calls together if they sequentioally use the same adaptor.
    function totalAssets() public view override returns (uint256 assets) {
        uint256 numOfPositions = positions.length;
        ERC20[] memory positionAssets = new ERC20[](numOfPositions - numberOfDebtPositions);
        uint256[] memory balances = new uint256[](numOfPositions - numberOfDebtPositions);
        ERC20[] memory debtPositionAssets = new ERC20[](numberOfDebtPositions);
        uint256[] memory debtBalances = new uint256[](numberOfDebtPositions);
        uint256 collateralIndex;
        uint256 debtIndex;

        for (uint256 i; i < numOfPositions; i++) {
            uint32 position = positions[i];
            if (getPositionData[position].isDebt) {
                debtPositionAssets[debtIndex] = _assetOf(position);
                debtBalances[debtIndex] = _balanceOf(position);
                debtIndex++;
            } else {
                positionAssets[collateralIndex] = _assetOf(position);
                balances[collateralIndex] = _balanceOf(position);
                collateralIndex++;
            }
        }

        PriceRouter priceRouter = PriceRouter(registry.getAddress(PRICE_ROUTER_REGISTRY_SLOT));
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(PriceRouter.getValues.selector, positionAssets, balances, asset);
        calls[1] = abi.encodeWithSelector(PriceRouter.getValues.selector, debtPositionAssets, debtBalances, asset);
        bytes[] memory results = priceRouter.multicall(calls);
        assets = abi.decode(results[0], (uint256)) - abi.decode(results[1], (uint256));
        // assets =
        // priceRouter.getValues(positionAssets, balances, asset) -
        // priceRouter.getValues(debtPositionAssets, debtBalances, asset);
    }

    /**
     * @notice The total amount of assets in the cellar.
     * @dev Excludes locked yield that hasn't been distributed.
     */
    function totalAssetsWithdrawable() public view returns (uint256 assets) {
        uint256 numOfPositions = positions.length;
        ERC20[] memory positionAssets = new ERC20[](numOfPositions);
        uint256[] memory balances = new uint256[](numOfPositions);

        for (uint256 i; i < numOfPositions; i++) {
            uint32 position = positions[i];
            positionAssets[i] = _assetOf(position);
            balances[i] = _withdrawableFrom(position);
        }

        PriceRouter priceRouter = PriceRouter(registry.getAddress(PRICE_ROUTER_REGISTRY_SLOT));
        assets = priceRouter.getValues(positionAssets, balances, asset);
    }

    /**
     * @notice The amount of assets that the cellar would exchange for the amount of shares provided.
     * @param shares amount of shares to convert
     * @return assets the shares can be exchanged for
     */
    function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
        assets = _convertToAssets(shares, totalAssets());
    }

    /**
     * @notice The amount of shares that the cellar would exchange for the amount of assets provided.
     * @param assets amount of assets to convert
     * @return shares the assets can be exchanged for
     */
    function convertToShares(uint256 assets) public view override returns (uint256 shares) {
        shares = _convertToShares(assets, totalAssets());
    }

    /**
     * @notice Simulate the effects of minting shares at the current block, given current on-chain conditions.
     * @param shares amount of shares to mint
     * @return assets that will be deposited
     */
    function previewMint(uint256 shares) public view override returns (uint256 assets) {
        uint256 _totalAssets = totalAssets();
        assets = _previewMint(shares, _totalAssets);
    }

    /**
     * @notice Simulate the effects of withdrawing assets at the current block, given current on-chain conditions.
     * @param assets amount of assets to withdraw
     * @return shares that will be redeemed
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        uint256 _totalAssets = totalAssets();
        shares = _previewWithdraw(assets, _totalAssets);
    }

    /**
     * @notice Simulate the effects of depositing assets at the current block, given current on-chain conditions.
     * @param assets amount of assets to deposit
     * @return shares that will be minted
     */
    function previewDeposit(uint256 assets) public view override returns (uint256 shares) {
        uint256 _totalAssets = totalAssets();
        shares = _convertToShares(assets, _totalAssets);
    }

    /**
     * @notice Simulate the effects of redeeming shares at the current block, given current on-chain conditions.
     * @param shares amount of shares to redeem
     * @return assets that will be returned
     */
    function previewRedeem(uint256 shares) public view override returns (uint256 assets) {
        uint256 _totalAssets = totalAssets();
        assets = _convertToAssets(shares, _totalAssets);
    }

    /**
     * @notice Finds the max amount of value an `owner` can remove from the cellar.
     * @param owner address of the user to find max value.
     * @param inShares if false, then returns value in terms of assets
     *                 if true then returns value in terms of shares
     */
    function _findMax(address owner, bool inShares) internal view returns (uint256 maxOut) {
        // Check if owner shares are locked, return 0 if so.
        uint256 lockBlock = userShareLockStartBlock[owner];
        if (lockBlock != 0) {
            uint256 blockSharesAreUnlocked = lockBlock + shareLockPeriod;
            if (blockSharesAreUnlocked > block.number) return 0;
        }
        // Get amount of assets to withdraw.
        uint256 _totalAssets = totalAssets();
        uint256 assets = _convertToAssets(balanceOf(owner), _totalAssets);

        uint256 withdrawable = totalAssetsWithdrawable();
        maxOut = assets <= withdrawable ? assets : withdrawable;

        if (inShares) maxOut = _convertToShares(maxOut, _totalAssets);
        // else leave maxOut in terms of assets.
    }

    /**
     * @notice Returns the max amount withdrawable by a user inclusive of performance fees
     * @dev EIP4626 states maxWithdraw must not revert, but it is possible for `totalAssets` to revert
     * so it does NOT conform to ERC4626 standards.
     * @param owner address to check maxWithdraw of.
     * @return the max amount of assets withdrawable by `owner`.
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        return _findMax(owner, false);
    }

    /**
     * @notice Returns the max amount shares redeemable by a user
     * @dev EIP4626 states maxRedeem must not revert, but it is possible for `totalAssets` to revert
     * so it does NOT conform to ERC4626 standards.
     * @param owner address to check maxRedeem of.
     * @return the max amount of shares redeemable by `owner`.
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        return _findMax(owner, true);
    }

    /**
     * @dev Used to more efficiently convert amount of shares to assets using a stored `totalAssets` value.
     */
    function _convertToAssets(uint256 shares, uint256 _totalAssets) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply();

        assets = totalShares == 0
            ? shares.changeDecimals(18, asset.decimals())
            : shares.mulDivDown(_totalAssets, totalShares);
    }

    /**
     * @dev Used to more efficiently convert amount of assets to shares using a stored `totalAssets` value.
     */
    function _convertToShares(uint256 assets, uint256 _totalAssets) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply();

        shares = totalShares == 0
            ? assets.changeDecimals(asset.decimals(), 18)
            : assets.mulDivDown(totalShares, _totalAssets);
    }

    /**
     * @dev Used to more efficiently simulate minting shares using a stored `totalAssets` value.
     */
    function _previewMint(uint256 shares, uint256 _totalAssets) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply();

        assets = totalShares == 0
            ? shares.changeDecimals(18, asset.decimals())
            : shares.mulDivUp(_totalAssets, totalShares);
    }

    /**
     * @dev Used to more efficiently simulate withdrawing assets using a stored `totalAssets` value.
     */
    function _previewWithdraw(uint256 assets, uint256 _totalAssets) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply();

        shares = totalShares == 0
            ? assets.changeDecimals(asset.decimals(), 18)
            : assets.mulDivUp(totalShares, _totalAssets);
    }

    // =========================================== ADAPTOR LOGIC ===========================================

    /**
     * @notice Emitted on when the rebalance deviation is changed.
     * @param oldDeviation the old rebalance deviation
     * @param newDeviation the new rebalance deviation
     */
    event RebalanceDeviationChanged(uint256 oldDeviation, uint256 newDeviation);

    /**
     * @notice totalAssets deviated outside the range set by `allowedRebalanceDeviation`.
     * @param assets the total assets in the cellar
     * @param min the minimum allowed assets
     * @param max the maximum allowed assets
     */
    error Cellar__TotalAssetDeviatedOutsideRange(uint256 assets, uint256 min, uint256 max);

    /**
     * @notice Total shares in a cellar changed when they should stay constant.
     * @param current the current amount of total shares
     * @param expected the expected amount of total shares
     */
    error Cellar__TotalSharesMustRemainConstant(uint256 current, uint256 expected);

    /**
     * @notice Total shares in a cellar changed when they should stay constant.
     * @param requested the requested rebalance  deviation
     * @param max the max rebalance deviation.
     */
    error Cellar__InvalidRebalanceDeviation(uint256 requested, uint256 max);

    mapping(address => bool) public isAdaptorSetup; // Map adaptor address to bool

    function setupAdaptor(address _adaptor) external onlyOwner {
        // Following call reverts if adaptor does not exist, or if it does not meet cellars risk appetite.
        registry.cellarSetupAdaptor(_adaptor, assetRiskTolerance, protocolRiskTolerance);
        isAdaptorSetup[_adaptor] = true;
    }

    uint64 public constant MAX_REBALANCE_DEVIATION = 0.1e18;

    /**
     * @notice The percent the total assets of a cellar may deviate during a rebalance call.
     */
    uint256 public allowedRebalanceDeviation = 0.003e18; // Currently set to 0.3%

    /**
     * @notice Allows governance to change this cellars rebalance deviation.
     * @param newDeviation the new reabalance deviation value.
     */
    function setRebalanceDeviation(uint256 newDeviation) external onlyOwner {
        if (newDeviation > MAX_REBALANCE_DEVIATION)
            revert Cellar__InvalidRebalanceDeviation(newDeviation, MAX_REBALANCE_DEVIATION);

        uint256 oldDeviation = allowedRebalanceDeviation;
        allowedRebalanceDeviation = newDeviation;

        emit RebalanceDeviationChanged(oldDeviation, newDeviation);
    }

    // Set to true before any adaptor calls are made.
    bool public blockExternalReceiver;

    struct AdaptorCall {
        address adaptor;
        bytes[] callData;
    }

    function callOnAdaptor(AdaptorCall[] memory data) external onlyOwner whenNotShutdown nonReentrant {
        blockExternalReceiver = true;

        uint256 minimumAllowedAssets;
        uint256 maximumAllowedAssets;
        uint256 totalShares;
        {
            //record totalAssets
            uint256 assetsBeforeAdaptorCall = totalAssets();
            minimumAllowedAssets = assetsBeforeAdaptorCall.mulDivUp((1e18 - allowedRebalanceDeviation), 1e18);
            maximumAllowedAssets = assetsBeforeAdaptorCall.mulDivUp((1e18 + allowedRebalanceDeviation), 1e18);
            totalShares = totalSupply();
        }

        //run all adaptor functions
        for (uint8 i = 0; i < data.length; i++) {
            address adaptor = data[i].adaptor;
            require(isAdaptorSetup[adaptor], "Adaptor not set up to be used with Cellar.");
            for (uint8 j = 0; j < data[i].callData.length; j++) {
                adaptor.functionDelegateCall(data[i].callData[j]); //TODO is there someway to append data to this, so we can append the adaptor address?
            }
        }

        // After making every external call, check that the totalAssets haas not deviated significantly, and that totalShares is the same.
        uint256 assets = totalAssets();
        if (assets < minimumAllowedAssets || assets > maximumAllowedAssets) {
            revert Cellar__TotalAssetDeviatedOutsideRange(assets, minimumAllowedAssets, maximumAllowedAssets);
        }
        if (totalShares != totalSupply()) revert Cellar__TotalSharesMustRemainConstant(totalSupply(), totalShares);

        blockExternalReceiver = false;
    }

    // ============================================ LIMITS LOGIC ============================================

    /**
     * @notice Total amount of assets that can be deposited for a user.
     * @return assets maximum amount of assets that can be deposited
     */
    function maxDeposit(address) public view override returns (uint256) {
        if (isShutdown) return 0;

        return type(uint256).max;
    }

    /**
     * @notice Total amount of shares that can be minted for a user.
     * @return shares maximum amount of shares that can be minted
     */
    function maxMint(address) public view override returns (uint256) {
        if (isShutdown) return 0;

        return type(uint256).max;
    }

    // ========================================= FEES LOGIC =========================================

    /**
     * @notice Attempted to send fee shares to strategist payout address, when address is not set.
     */
    error Cellar__PayoutNotSet();

    /**
     * @dev Calculate the amount of fees to mint such that value of fees after minting is not diluted.
     */
    function _convertToFees(uint256 feesInShares) internal view returns (uint256 fees) {
        // Saves an SLOAD.
        uint256 totalShares = totalSupply();

        // Get the amount of fees to mint. Without this, the value of fees minted would be slightly
        // diluted because total shares increased while total assets did not. This counteracts that.
        if (totalShares > feesInShares) {
            // Denominator is greater than zero
            uint256 denominator = totalShares - feesInShares;
            fees = feesInShares.mulDivUp(totalShares, denominator);
        }
        // If denominator is less than or equal to zero, `fees` should be zero.
    }

    /**
     * @notice Emitted when platform fees are send to the Sommelier chain.
     * @param feesInSharesRedeemed amount of fees redeemed for assets to send
     * @param feesInAssetsSent amount of assets fees were redeemed for that were sent
     */
    event SendFees(uint256 feesInSharesRedeemed, uint256 feesInAssetsSent);

    /**
     * @notice Transfer accrued fees to the Sommelier chain to distribute.
     * @dev Fees are accrued as shares and redeemed upon transfer.
     * @dev assumes cellar's accounting asset is able to be transferred and sent to Cosmos
     */
    function sendFees() external nonReentrant {
        address strategistPayoutAddress = feeData.strategistPayoutAddress;
        if (strategistPayoutAddress == address(0)) revert Cellar__PayoutNotSet();

        uint256 _totalAssets = totalAssets();

        // Calculate platform fees earned.
        uint256 elapsedTime = block.timestamp - feeData.lastAccrual;
        uint256 platformFeeInAssets = (_totalAssets * elapsedTime * feeData.platformFee) / 1e18 / 365 days;
        uint256 platformFees = _convertToFees(_convertToShares(platformFeeInAssets, _totalAssets));
        _mint(address(this), platformFees);

        uint256 strategistFeeSharesDue = platformFees.mulWadDown(feeData.strategistPlatformCut);
        if (strategistFeeSharesDue > 0) {
            //transfer shares to strategist
            _transfer(address(this), strategistPayoutAddress, strategistFeeSharesDue);

            platformFees -= strategistFeeSharesDue;
        }

        feeData.lastAccrual = uint32(block.timestamp);

        // Redeem our fee shares for assets to send to the fee distributor module.
        uint256 assets = _convertToAssets(platformFees, _totalAssets);
        if (assets > 0) {
            _burn(address(this), platformFees);

            // Transfer assets to a fee distributor on the Sommelier chain.
            IGravity gravityBridge = IGravity(registry.getAddress(0));
            asset.safeApprove(address(gravityBridge), assets);
            gravityBridge.sendToCosmos(address(asset), feeData.feesDistributor, assets);
        }

        emit SendFees(platformFees, assets);
    }

    // ========================================== HELPER FUNCTIONS ==========================================
    //TODO for _depositTo and _withdrawFrom, adaptor data should contain values to validate minimums.
    // ^^^^ might be better to enforce this using withdrawableFrom?
    //Weird cuz if an aUSDC position says you can withdraw this much USDC from me, but then a debt position says you can borrow this much more, the two answers are dependent on eachother, but each position doesn't know that.
    //TODO need to pass in adaptor data that the strategist can set for their cellar
    /**
     * @dev Deposit into a position according to its position type and update related state.
     * @param position address to deposit funds into
     * @param assets the amount of assets to deposit into the position
     */
    //TODO this is ONLY used in the afterDeposit function
    function _depositTo(uint32 position, uint256 assets) internal {
        //TODO adaptor should be a non zero address
        address adaptor = getPositionData[position].adaptor;
        adaptor.functionDelegateCall(
            abi.encodeWithSelector(
                BaseAdaptor.deposit.selector,
                assets,
                getPositionData[position].adaptorData,
                getPositionData[position].configurationData
            )
        );
    }

    /**
     * @dev Withdraw from a position according to its position type and update related state.
     * @param position address to withdraw funds from
     * @param assets the amount of assets to withdraw from the position
     * @param receiver the address to sent withdrawn assets to
     */
    //TODO this is only used in the _withdrawInOrder function
    function _withdrawFrom(
        uint32 position,
        uint256 assets,
        address receiver
    ) internal {
        address adaptor = getPositionData[position].adaptor;
        adaptor.functionDelegateCall(
            abi.encodeWithSelector(
                BaseAdaptor.withdraw.selector,
                assets,
                receiver,
                getPositionData[position].adaptorData,
                getPositionData[position].configurationData
            )
        );
    }

    /**
     * @dev Get the withdrawable balance of a position according to its position type.
     * @param position position to get the withdrawable balance of
     */
    //TODO maybe these view functions should use staticcall
    function _withdrawableFrom(uint32 position) internal view returns (uint256) {
        // Debt positions always return 0 for their withdrawable.
        if (getPositionData[position].isDebt) return 0;
        return
            BaseAdaptor(getPositionData[position].adaptor).withdrawableFrom(
                getPositionData[position].adaptorData,
                getPositionData[position].configurationData
            );
    }

    /**
     * @dev Get the balance of a position according to its position type.
     * @dev For ERC4626 position balances, this uses `previewRedeem` as opposed
     *      to `convertToAssets` so that balanceOf ERC4626 positions includes fees taken on withdraw.
     * @param position position to get the balance of
     */
    function _balanceOf(uint32 position) internal view returns (uint256) {
        address adaptor = getPositionData[position].adaptor;
        return BaseAdaptor(adaptor).balanceOf(getPositionData[position].adaptorData);
    }

    /**
     * @dev Get the asset of a position according to its position type.
     * @param position to get the asset of
     */
    function _assetOf(uint32 position) internal view returns (ERC20) {
        address adaptor = getPositionData[position].adaptor;
        return BaseAdaptor(adaptor).assetOf(getPositionData[position].adaptorData);
    }

    function getPositionAssets() external view returns (ERC20[] memory assets) {
        assets = new ERC20[](positions.length);
        for (uint256 i = 0; i < positions.length; i++) {
            assets[i] = _assetOf(positions[i]);
        }
    }
}
