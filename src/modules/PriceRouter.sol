// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Registry } from "../Registry.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { FeedRegistryInterface } from "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { Math } from "src/utils/Math.sol";

contract PriceRouter is Ownable {
    using Math for uint256;

    FeedRegistryInterface public feedRegistry = FeedRegistryInterface(0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf);

    // =========================================== ASSET CONFIG ===========================================

    mapping(ERC20 => address) public baseAssetOverride;
    mapping(ERC20 => address) public quoteAssetOverride;
    mapping(ERC20 => bool) private _isSupportedQuoteAsset;

    function isSupportedQuoteAsset(ERC20 quoteAsset) public view returns (bool) {
        return _isSupportedQuoteAsset[quoteAsset] || _isSupportedQuoteAsset[ERC20(baseAssetOverride[quoteAsset])];
    }

    function setAssetOverride(ERC20 asset, address _override) external onlyOwner {
        baseAssetOverride[asset] = _override;
    }

    function setIsSupportedQuoteAsset(ERC20 asset, bool isSupported) external onlyOwner {
        _isSupportedQuoteAsset[asset] = isSupported;
    }

    // TODO: transfer ownership to the gravity contract
    constructor() Ownable() {
        _isSupportedQuoteAsset[ERC20(Denominations.ETH)] = true;
        _isSupportedQuoteAsset[ERC20(Denominations.USD)] = true;

        ERC20 WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        baseAssetOverride[WETH] = Denominations.ETH;
        quoteAssetOverride[WETH] = Denominations.ETH;
        _isSupportedQuoteAsset[WETH] = true;

        ERC20 USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        quoteAssetOverride[USDC] = Denominations.USD;
        _isSupportedQuoteAsset[USDC] = true;

        ERC20 WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
        baseAssetOverride[WBTC] = Denominations.BTC;
        quoteAssetOverride[WBTC] = Denominations.BTC;
    }

    // =========================================== PRICING LOGIC ===========================================

    function getValues(
        ERC20[] memory baseAssets,
        uint256[] memory amounts,
        ERC20 quoteAsset
    ) external view returns (uint256 value) {
        uint8 quoteAssetDecimals = quoteAsset.decimals();
        for (uint256 i; i < baseAssets.length; i++)
            value += _getValue(baseAssets[i], amounts[i], quoteAsset, quoteAssetDecimals);
    }

    function getValue(
        ERC20 baseAsset,
        uint256 amounts,
        ERC20 quoteAsset
    ) external view returns (uint256 value) {
        value = _getValue(baseAsset, amounts, quoteAsset, quoteAsset.decimals());
    }

    function getExchangeRate(ERC20 baseAsset, ERC20 quoteAsset) external view returns (uint256 exchangeRate) {
        exchangeRate = _getExchangeRate(baseAsset, quoteAsset, quoteAsset.decimals());
    }

    function _getValue(
        ERC20 baseAsset,
        uint256 amount,
        ERC20 quoteAsset,
        uint8 quoteAssetDecimals
    ) internal view returns (uint256 value) {
        value = amount.mulDivDown(
            _getExchangeRate(baseAsset, quoteAsset, quoteAssetDecimals),
            10**baseAsset.decimals()
        );
    }

    function _getExchangeRate(
        ERC20 baseAsset,
        ERC20 quoteAsset,
        uint8 quoteDecimals
    ) internal view returns (uint256 exchangeRate) {
        address baseOverride = baseAssetOverride[baseAsset];
        address base = baseOverride == address(0) ? address(baseAsset) : baseOverride;

        address quoteOverride = quoteAssetOverride[quoteAsset];
        address quote = quoteOverride == address(0) ? address(quoteAsset) : quoteOverride;

        if (base == quote) return 1e18;

        if (isSupportedQuoteAsset(quoteAsset)) {
            (, int256 price, , , ) = feedRegistry.latestRoundData(base, quote);

            exchangeRate = uint256(price).changeDecimals(feedRegistry.decimals(base, quote), quoteDecimals);
        } else {
            exchangeRate = _getExchangeRateInETH(base).mulDivDown(1e18, _getExchangeRateInETH(quote));
            exchangeRate = exchangeRate.changeDecimals(18, quoteDecimals);
        }
    }

    function _getExchangeRateInETH(address base) internal view returns (uint256 exchangeRate) {
        if (base == Denominations.ETH) return 1e18;

        (, int256 price, , , ) = feedRegistry.latestRoundData(base, Denominations.ETH);

        exchangeRate = uint256(price);
    }
}
