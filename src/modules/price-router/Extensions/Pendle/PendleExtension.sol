// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Extension, PriceRouter, ERC20, Math} from "src/modules/price-router/Extensions/Extension.sol";
import {IRateProvider} from "src/interfaces/external/EtherFi/IRateProvider.sol";
import {IPendleOracle} from "src/interfaces/external/Pendle/IPendleOracle.sol";
import {ISyToken} from "src/interfaces/external/Pendle/IPendle.sol";

contract PendleExtension is Extension {
    using Math for uint256;

    /**
     * @notice The PT oracle that implements `getOracleState`, `getLpToAssetRate`,  and `getPtToAssetRate`.
     */
    IPendleOracle public immutable ptOracle;

    constructor(PriceRouter _priceRouter, address _ptOracle) Extension(_priceRouter) {
        ptOracle = IPendleOracle(_ptOracle);
    }

    /**
     * @notice Attempted to add eETH support when weETH is not supported.
     */
    error PendleExtension__UNDERLYING_NOT_SUPPORTED();

    /**
     * @notice Oracle is not ready.
     */
    error PendleExtension__ORACLE_NOT_READY();

    /**
     * @notice Tried pricing an unknown Pendle Asset Type.
     */
    error PendleExtension__UNKNOWN_TYPE();

    /**
     * @notice Enum containing all the possible Pendle Asset Types.
     */
    enum PendleAsset {
        SY,
        PT,
        YT,
        LP
    }

    /**
     * @param kind the Pendle Asset Type
     * @param market the Pendle Market
     * @param duration the TWAP duration
     * @param underlying the underlying asset of the Pendle Asset Type
     */
    struct ExtensionStorage {
        PendleAsset kind;
        address market;
        uint32 duration;
        ERC20 underlying;
    }

    /**
     * @notice Maps ERC20 Pendle Assets to ExtensionStorage structs.
     */
    mapping(ERC20 => ExtensionStorage) public extensionStorage;

    /**
     * @notice Called by the price router during `_updateAsset` calls.
     * @param asset a pendle asset
     * @param _storage ExtensionStorage needed to price asset
     */
    function setupSource(ERC20 asset, bytes memory _storage) external override onlyPriceRouter {
        ExtensionStorage memory stor = abi.decode(_storage, (ExtensionStorage));
        if (!priceRouter.isSupported(stor.underlying)) revert PendleExtension__UNDERLYING_NOT_SUPPORTED();
        if (stor.kind == PendleAsset.SY) {} else {
            // Verify TWAP stuff is supported
            (bool increaseCardinalityRequired,, bool oldestObservationSatisfied) =
                ptOracle.getOracleState(stor.market, stor.duration);
            if (increaseCardinalityRequired || !oldestObservationSatisfied) revert PendleExtension__ORACLE_NOT_READY();
        }
        extensionStorage[asset] = stor;
    }

    /**
     * @notice Called during pricing operations.
     * @return price of Pendle Asset in USD
     */
    function getPriceInUSD(ERC20 asset) external view override returns (uint256) {
        ExtensionStorage memory stor = extensionStorage[asset];
        uint256 underlyingAssetInUsd = priceRouter.getPriceInUSD(stor.underlying);
        if (stor.kind == PendleAsset.SY) {
            uint256 exchangeRate = ISyToken(address(asset)).exchangeRate();
            uint256 underlyingAssetMulExchangeRateInUsd = underlyingAssetInUsd.mulDivDown(exchangeRate, 1e18);
            return underlyingAssetMulExchangeRateInUsd;
        } else {
            // Call Pendle oracle contract
            if (stor.kind == PendleAsset.LP) {
                uint256 lpToAssetRate = ptOracle.getLpToAssetRate(stor.market, stor.duration);
                return lpToAssetRate.mulDivDown(underlyingAssetInUsd, 1e18);
            } else {
                uint256 ptToAssetRate = ptOracle.getPtToAssetRate(stor.market, stor.duration);
                uint256 ptPriceInUsd = ptToAssetRate.mulDivDown(underlyingAssetInUsd, 1e18);
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
                    revert PendleExtension__UNKNOWN_TYPE();
                }
            }
        }
    }
}
