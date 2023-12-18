// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, Registry, ERC20, Math, SafeTransferLib } from "src/base/Cellar.sol";

contract BaseAdvancedCellar is Cellar {
    using Math for uint256;
    using SafeTransferLib for ERC20;

    error AdvancedCellar__AlternativeAssetFeeTooLarge();

    uint32 internal constant MAX_ALTERNATIVE_ASSET_FEE = 0.1e8;

    // TODO can this be a mapping and a struct

    ERC20 public alternativeAsset;
    uint32 public alternativeHoldingPosition;
    uint32 public alternativeAssetFee;

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

    receive() external payable {}

    function setAlternativeAssetData(
        ERC20 _alternativeAsset,
        uint32 _alternativeHoldingPosition,
        uint32 _alternativeAssetFee
    ) external onlyOwner {
        if (!isPositionUsed[_alternativeHoldingPosition]) revert Cellar__PositionNotUsed(_alternativeHoldingPosition);
        if (_assetOf(_alternativeHoldingPosition) != _alternativeAsset)
            revert Cellar__AssetMismatch(address(_alternativeAsset), address(_assetOf(_alternativeHoldingPosition)));
        if (getPositionData[_alternativeHoldingPosition].isDebt)
            revert Cellar__InvalidHoldingPosition(_alternativeHoldingPosition);
        if (_alternativeAssetFee > MAX_ALTERNATIVE_ASSET_FEE) revert AdvancedCellar__AlternativeAssetFeeTooLarge();

        alternativeAsset = _alternativeAsset;
        alternativeHoldingPosition = _alternativeHoldingPosition;
    }

    /**
     * @notice Deposits assets into the cellar, and returns shares to receiver.
     * @dev If alternativeAsset is not set, depositAlternativeAsset will revert.
     * @param alternativeAssets amount of assets deposited by user.
     * @param receiver address to receive the shares.
     * @return shares amount of shares given for deposit.
     */
    function depositAlternativeAsset(
        uint256 alternativeAssets,
        address receiver
    ) public nonReentrant returns (uint256 shares) {
        // Use `_calculateTotalAssetsOrTotalAssetsWithdrawable` instead of totalAssets bc re-entrancy is already checked in this function.
        (uint256 _totalAssets, uint256 _totalSupply) = _getTotalAssetsAndTotalSupply(true);

        // Need to transfer before minting or ERC777s could reenter.
        alternativeAsset.safeTransferFrom(msg.sender, address(this), alternativeAssets);

        // Convert assets from alternativeAsset to asset.
        uint256 assets = priceRouter.getValue(alternativeAsset, alternativeAssets, asset);

        // Collect alternative asset fee.
        assets = assets.mulDivDown(1e8 - alternativeAssetFee, 1e8);

        // Check for rounding error since we round down in previewDeposit.
        if ((shares = _convertToShares(assets, _totalAssets, _totalSupply)) == 0) revert Cellar__ZeroShares();

        if ((_totalSupply + shares) > shareSupplyCap) revert Cellar__ShareSupplyCapExceeded();

        beforeDeposit(assets, shares, receiver);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        _depositTo(alternativeHoldingPosition, alternativeAssets);
    }
}
