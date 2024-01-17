// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, Registry, ERC20, Math, SafeTransferLib, Address } from "src/base/Cellar.sol";

// TODO once audited, make a permutation for oracle, aave flashloans, multi-asset deposit
// TODO once audited, make a permutation for oracle, aave flashloans, multi-asset deposit, native support
contract CellarWithMultiAssetDeposit is Cellar {
    using Math for uint256;
    using SafeTransferLib for ERC20;
    using Address for address;

    // ========================================= STRUCTS =========================================

    /**
     * @notice Stores data needed for multi-asset deposits into this cellar.
     * @param isSupported bool indicating that mapped asset is supported
     * @param holdingPosition the holding position to deposit alternative assets into
     * @param depositFee fee taken for depositing this alternative asset
     */
    struct AlternativeAssetData {
        bool isSupported;
        uint32 holdingPosition;
        uint32 depositFee;
    }

    // ========================================= CONSTANTS =========================================

    /**
     * @notice The max possible fee that can be charged for an alternative asset deposit.
     */
    uint32 internal constant MAX_ALTERNATIVE_ASSET_FEE = 0.1e8;

    // ========================================= GLOBAL STATE =========================================

    /**
     * @notice Maps alternative assets to alternative asset data.
     */
    mapping(ERC20 => AlternativeAssetData) public alternativeAssetData;

    //============================== ERRORS ===============================

    error CellarWithMultiAssetDeposit__AlternativeAssetFeeTooLarge();
    error CellarWithMultiAssetDeposit__AlternativeAssetNotSupported();
    error CellarWithMultiAssetDeposit__CallDataLengthNotSupported();

    //============================== EVENTS ===============================

    /**
     * @notice Emitted when an alternative asset is added or updated.
     */
    event AlternativeAssetUpdated(address asset, uint32 holdingPosition, uint32 depositFee);

    /**
     * @notice Emitted when an alternative asser is removed.
     */
    event AlternativeAssetDropped(address asset);

    //============================== IMMUTABLES ===============================

    constructor(
        address _owner,
        Registry _registry,
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint32 _holdingPosition,
        bytes memory _holdingPositionConfig,
        uint256 _initialDeposit,
        uint64 _strategistPlatformCut,
        uint192 _shareSupplyCap
    )
        Cellar(
            _owner,
            _registry,
            _asset,
            _name,
            _symbol,
            _holdingPosition,
            _holdingPositionConfig,
            _initialDeposit,
            _strategistPlatformCut,
            _shareSupplyCap
        )
    {}

    //============================== OWNER FUNCTIONS ===============================

    /**
     * @notice Allows the owner to add, or update an existing alternative asset deposit.
     * @param _alternativeAsset the ERC20 alternative asset that can be deposited
     * @param _alternativeHoldingPosition the holding position to direct alternative asset deposits to
     * @param _alternativeAssetFee the fee to charge for depositing this alternative asset
     */
    function setAlternativeAssetData(
        ERC20 _alternativeAsset,
        uint32 _alternativeHoldingPosition,
        uint32 _alternativeAssetFee
    ) external {
        _onlyOwner();
        if (!isPositionUsed[_alternativeHoldingPosition]) revert Cellar__PositionNotUsed(_alternativeHoldingPosition);
        if (_assetOf(_alternativeHoldingPosition) != _alternativeAsset)
            revert Cellar__AssetMismatch(address(_alternativeAsset), address(_assetOf(_alternativeHoldingPosition)));
        if (getPositionData[_alternativeHoldingPosition].isDebt)
            revert Cellar__InvalidHoldingPosition(_alternativeHoldingPosition);
        if (_alternativeAssetFee > MAX_ALTERNATIVE_ASSET_FEE)
            revert CellarWithMultiAssetDeposit__AlternativeAssetFeeTooLarge();

        alternativeAssetData[_alternativeAsset] = AlternativeAssetData(
            true,
            _alternativeHoldingPosition,
            _alternativeAssetFee
        );

        emit AlternativeAssetUpdated(address(_alternativeAsset), _alternativeHoldingPosition, _alternativeAssetFee);
    }

    /**
     * @notice Allows the owner to stop an alternative asset from being deposited.
     * @param _alternativeAsset the asset to not allow for alternative asset deposits anymore
     */
    function dropAlternativeAssetData(ERC20 _alternativeAsset) external {
        _onlyOwner();
        delete alternativeAssetData[_alternativeAsset];
        // alternativeAssetData[_alternativeAsset] = AlternativeAssetData(false, 0, 0);

        emit AlternativeAssetDropped(address(_alternativeAsset));
    }

    /**
     * @notice Deposits assets into the cellar, and returns shares to receiver.
     * @dev Compliant with ERC4626 standard, but additionally allows for multi-asset deposits
     *      by encoding the asset to deposit at the end of the normal deposit params.
     * @param assets amount of assets deposited by user.
     * @param receiver address to receive the shares.
     * @return shares amount of shares given for deposit.
     */
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        // Use `_calculateTotalAssetsOrTotalAssetsWithdrawable` instead of totalAssets bc re-entrancy is already checked in this function.
        (uint256 _totalAssets, uint256 _totalSupply) = _getTotalAssetsAndTotalSupply(true);

        (
            ERC20 depositAsset,
            uint256 assetsConvertedToAsset,
            uint256 assetsConvertedToAssetWithFeeRemoved,
            uint32 position
        ) = _getDepositAssetAndAdjustedAssetsAndPosition(assets);

        // Perform share calculation using assetsConvertedToAssetWithFeeRemoved.
        // Check for rounding error since we round down in previewDeposit.
        // NOTE for totalAssets, we add the delta between assetsConvertedToAsset, and assetsConvertedToAssetWithFeeRemoved, so that the fee the caller pays
        // to join with the alternative asset is factored into share price calculation.
        if (
            (shares = _convertToShares(
                assetsConvertedToAssetWithFeeRemoved,
                _totalAssets + (assetsConvertedToAsset - assetsConvertedToAssetWithFeeRemoved),
                _totalSupply
            )) == 0
        ) revert Cellar__ZeroShares();

        if ((_totalSupply + shares) > shareSupplyCap) revert Cellar__ShareSupplyCapExceeded();

        // _enter into holding position but passing in actual assets.
        _enter(depositAsset, position, assets, shares, receiver);
    }

    //============================== HELPER FUNCTION ===============================

    /**
     * @notice Reads message data to determine if user is trying to deposit with an alternative asset or wants to do a normal deposit.
     */
    function _getDepositAssetAndAdjustedAssetsAndPosition(
        uint256 assets
    )
        internal
        view
        returns (
            ERC20 depositAsset,
            uint256 assetsConvertedToAsset,
            uint256 assetsConvertedToAssetWithFeeRemoved,
            uint32 position
        )
    {
        uint256 msgDataLength = msg.data.length;
        if (msgDataLength == 68) {
            // Caller has not encoded an alternative asset, so return address(0).
            depositAsset = asset;
            assetsConvertedToAssetWithFeeRemoved = assets;
            assetsConvertedToAsset = assets;
            position = holdingPosition;
        } else if (msgDataLength == 100) {
            // Caller has encoded an extra arguments, try to decode it as an address.
            (, , depositAsset) = abi.decode(msg.data[4:], (uint256, address, ERC20));

            AlternativeAssetData memory assetData = alternativeAssetData[depositAsset];
            if (!assetData.isSupported) revert CellarWithMultiAssetDeposit__AlternativeAssetNotSupported();

            // Convert assets from depositAsset to asset.
            assetsConvertedToAsset = priceRouter.getValue(depositAsset, assets, asset);

            // Collect alternative asset fee.
            assetsConvertedToAssetWithFeeRemoved = assetsConvertedToAsset.mulDivDown(1e8 - assetData.depositFee, 1e8);

            position = assetData.holdingPosition;
        } else {
            revert CellarWithMultiAssetDeposit__CallDataLengthNotSupported();
        }
    }
}
