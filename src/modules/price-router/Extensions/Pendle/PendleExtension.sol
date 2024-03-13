// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Extension, PriceRouter, ERC20, Math} from "src/modules/price-router/Extensions/Extension.sol";
import {IRateProvider} from "src/interfaces/external/EtherFi/IRateProvider.sol";
import {IPendleOracle} from "src/interfaces/external/Pendle/IPendleOracle.sol";

/**
 * @title Sommelier Price Router eETH Extension.
 * @notice Allows the Price Router to price eETH.
 * @author 0xEinCodes
 */
contract PendleExtension is Extension {
    using Math for uint256;

    IPendleOracle public immutable ptOracle;

    constructor(PriceRouter _priceRouter, address _ptOracle) Extension(_priceRouter) {
        ptOracle = IPendleOracle(_ptOracle);
    }

    /**
     * @notice Attempted to add eETH support when weETH is not supported.
     */
    error PendleExtension__UNDERLYING_NOT_SUPPORTED();

    /**
     * @notice Attempted to use this extension to price something other than eETH.
     */
    error eEthExtension__ASSET_NOT_EETH();

    enum PendleAsset {
        SY,
        PT,
        YT,
        LP
    }

    struct ExtensionStorage {
        PendleAsset kind;
        address market;
        uint32 duration;
        ERC20 underlying;
        uint8 underlyingDecimals;
    }

    mapping(ERC20 => ExtensionStorage) public extensionStorage;

    /**
     * @notice Called by the price router during `_updateAsset` calls.
     * @param asset a pendle asset
     * @param _storage ExtensionStorage with kind, and underlying
     */
    function setupSource(ERC20 asset, bytes memory _storage) external override onlyPriceRouter {
        ExtensionStorage memory stor = abi.decode(_storage, (ExtensionStorage));
        if (!priceRouter.isSupported(stor.underlying)) revert PendleExtension__UNDERLYING_NOT_SUPPORTED();
        if (stor.kind == PendleAsset.SY) {} else {
            // Verify TWAP stuff is supported
            (bool increaseCardinalityRequired,, bool oldestObservationSatisfied) =
                ptOracle.getOracleState(stor.market, stor.duration);
            if (increaseCardinalityRequired || !oldestObservationSatisfied) revert("Oracle not ready");
        }
        stor.underlyingDecimals = stor.underlying.decimals();
        extensionStorage[asset] = stor;
    }

    /**
     * @notice Called during pricing operations.
     * @return price of eETH in USD [USD/eETH]
     */
    function getPriceInUSD(ERC20 asset) external view override returns (uint256) {
        ExtensionStorage memory stor = extensionStorage[asset];
        uint256 underlyingAssetInUsd = priceRouter.getPriceInUSD(stor.underlying);
        if (stor.kind == PendleAsset.SY) {
            return underlyingAssetInUsd;
        } else {
            // Call Pendle oracle contract
            if (stor.kind == PendleAsset.LP) {
                uint256 lpToAssetRate = ptOracle.getLpToAssetRate(stor.market, stor.duration);
                return lpToAssetRate.mulDivDown(underlyingAssetInUsd, 10 ** stor.underlyingDecimals);
            } else {
                uint256 ptToAssetRate = ptOracle.getPtToAssetRate(stor.market, stor.duration);
                uint256 ptPriceInUsd = ptToAssetRate.mulDivDown(underlyingAssetInUsd, 10 ** stor.underlyingDecimals);
                if (stor.kind == PendleAsset.PT) {
                    // Use PT pricing logic
                    return ptPriceInUsd;
                } else if (stor.kind == PendleAsset.YT) {
                    // Use YT pricing logic
                    if (ptPriceInUsd > underlyingAssetInUsd) {
                        return 0;
                    } else {
                        return underlyingAssetInUsd - ptPriceInUsd;
                    }
                } else {
                    revert("unknown");
                }
            }
        }
    }
}
