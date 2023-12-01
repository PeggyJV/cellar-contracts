// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Extension, PriceRouter, ERC20, Math } from "src/modules/price-router/Extensions/Extension.sol";
import { ERC4626SharePriceOracle, Math, ERC4626 } from "src/base/ERC4626SharePriceOracle.sol";

// TODO other important note is the oracle is technically giving a value in terms of Arbitrum USDC, but the mainnet price router will be pricing Mainnet USDC.
// So there is an assumption that USDC on Arb is == USDC on Mainnet.
/**
 * @title Sommelier Price Router ERC4626 Extension
 * @notice Allows the Price Router to price ERC4626 shares.
 * @author crispymangoes
 */
contract XChainShareExtension is Extension {
    using Math for uint256;

    constructor(PriceRouter _priceRouter) Extension(_priceRouter) {}

    /**
     * @notice ERC4626.asset() is not supported in the price router.
     */
    error XChainShareExtension_ASSET_NOT_SUPPORTED();
    error XChainShareExtension_OracleNotSafeToUse();

    /**
     * @notice Extension storage
     * @param oracle address of the curve pool to use as an oracle
     * @param oracleDecimals the underlying or constituent for coins 1
     * @param asset the underlying or constituent for coins 0
     */
    struct ExtensionStorage {
        ERC4626SharePriceOracle oracle;
        uint8 oracleDecimals;
        ERC20 asset;
    }

    /**
     * @notice Curve EMA Extension Storage
     */
    mapping(ERC20 => ExtensionStorage) public extensionStorage;

    /**
     * @notice Called by the price router during `_updateAsset` calls.
     * @param asset the XChainShare vault share to price
     */
    function setupSource(ERC20 asset, bytes memory _storage) external override onlyPriceRouter {
        ExtensionStorage memory mstor = abi.decode(_storage, (ExtensionStorage));

        // Make sure price router supports Asset.
        if (!priceRouter.isSupported(mstor.asset)) revert XChainShareExtension_ASSET_NOT_SUPPORTED();

        ExtensionStorage storage sstor = extensionStorage[asset];
        sstor.oracle = mstor.oracle;
        sstor.oracleDecimals = mstor.oracle.decimals();
        sstor.asset = mstor.asset;
    }

    /**
     * @notice Called during pricing operations.
     * @param asset the ERC4626 vault share to price
     */
    function getPriceInUSD(ERC20 asset) external view override returns (uint256 price) {
        ExtensionStorage memory mstor = extensionStorage[asset];

        (uint256 ans, uint256 timeWeightedAverageAnswer, bool notSafeToUse) = mstor.oracle.getLatest();

        if (notSafeToUse) revert XChainShareExtension_OracleNotSafeToUse();

        uint256 assetPrice = priceRouter.getPriceInUSD(mstor.asset);
        price = assetPrice.mulDivDown(ans.min(timeWeightedAverageAnswer), 10 ** mstor.oracleDecimals);
    }
}
