// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, Registry, ERC20, Math, SafeTransferLib, Address } from "src/base/Cellar.sol";

contract CellarWithMultiAssetDeposit is Cellar {
    using Math for uint256;
    using SafeTransferLib for ERC20;
    using Address for address;

    error AdvancedCellar__AlternativeAssetFeeTooLarge();
    error AdvancedCellar__AlternativeAssetNotSupported();
    error AdvancedCellar__CallDataLengthNotSupported();

    event AlternativeAssetUpdated(address asset, uint32 holdingPosition, uint32 depositFee);
    event AlternativeAssetDropped(address asset);

    uint32 internal constant MAX_ALTERNATIVE_ASSET_FEE = 0.1e8;

    struct AlternativeAssetData {
        bool isSupported;
        uint32 holdingPosition;
        uint32 depositFee;
    }

    mapping(ERC20 => AlternativeAssetData) internal alternativeAssetData;

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
        if (_alternativeAssetFee > MAX_ALTERNATIVE_ASSET_FEE) revert AdvancedCellar__AlternativeAssetFeeTooLarge();

        alternativeAssetData[_alternativeAsset] = AlternativeAssetData(
            true,
            _alternativeHoldingPosition,
            _alternativeAssetFee
        );

        emit AlternativeAssetUpdated(address(_alternativeAsset), _alternativeHoldingPosition, _alternativeAssetFee);
    }

    function dropAlternativeAssetData(ERC20 _alternativeAsset) external {
        _onlyOwner();
        delete alternativeAssetData[_alternativeAsset];
        // alternativeAssetData[_alternativeAsset] = AlternativeAssetData(false, 0, 0);

        emit AlternativeAssetDropped(address(_alternativeAsset));
    }

    /**
     * @notice Deposits assets into the cellar, and returns shares to receiver.
     * @param assets amount of assets deposited by user.
     * @param receiver address to receive the shares.
     * @return shares amount of shares given for deposit.
     */
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        // Use `_calculateTotalAssetsOrTotalAssetsWithdrawable` instead of totalAssets bc re-entrancy is already checked in this function.
        (uint256 _totalAssets, uint256 _totalSupply) = _getTotalAssetsAndTotalSupply(true);

        (
            ERC20 depositAsset,
            uint256 unadjustedAssets,
            uint256 adjustedAssets,
            uint32 position
        ) = _getDepositAssetAndAdjustedAssetsAndPosition(assets);

        // Perform share calculation using adjustedAssets.
        // Check for rounding error since we round down in previewDeposit.
        // NOTE for totalAssets, we add the delta between unadjustedAssets, and adjustedAssets, so that the fee the caller pays
        // to join with the alternative asset is factored into share price calcualtion.
        if (
            (shares = _convertToShares(
                adjustedAssets,
                _totalAssets + (unadjustedAssets - adjustedAssets),
                _totalSupply
            )) == 0
        ) revert Cellar__ZeroShares();

        if ((_totalSupply + shares) > shareSupplyCap) revert Cellar__ShareSupplyCapExceeded();

        // _enter into holding position but passing in actual assets.
        _enter(depositAsset, position, assets, shares, receiver);
    }

    function _getDepositAssetAndAdjustedAssetsAndPosition(
        uint256 assets
    ) internal view returns (ERC20 depositAsset, uint256 unadjustedAssets, uint256 adjustedAssets, uint32 position) {
        uint256 msgDataLength = msg.data.length;
        if (msgDataLength == 68) {
            // Caller has not encoded an alternative asset, so return address(0).
            depositAsset = asset;
            adjustedAssets = assets;
            unadjustedAssets = assets;
            position = holdingPosition;
        } else if (msgDataLength == 100) {
            // Caller has encoded an extra arguments, try to decode it as an address.
            (, , depositAsset) = abi.decode(msg.data[4:], (uint256, address, ERC20));

            AlternativeAssetData memory assetData = alternativeAssetData[depositAsset];
            if (!assetData.isSupported) revert AdvancedCellar__AlternativeAssetNotSupported();

            // Convert assets from depositAsset to asset.
            unadjustedAssets = priceRouter.getValue(depositAsset, assets, asset);

            // Collect alternative asset fee.
            adjustedAssets = unadjustedAssets.mulDivDown(1e8 - assetData.depositFee, 1e8);

            position = assetData.holdingPosition;
        } else {
            revert AdvancedCellar__CallDataLengthNotSupported();
        }
    }
}
