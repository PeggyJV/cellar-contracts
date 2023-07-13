// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, Registry, ERC20, Math } from "src/base/Cellar.sol";

import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";

contract CellarWithOracle is Cellar {
    using Math for uint256;

    constructor(
        address _owner,
        Registry _registry,
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint32 _holdingPosition,
        bytes memory _holdingPositionConfig,
        uint256 _initialDeposit,
        uint64 _strategistPlatformCut
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
            _strategistPlatformCut
        )
    {}

    ERC4626SharePriceOracle public sharePriceOracle;
    bool public revertOnOracleFailure;

    error Cellar__OracleFailure();

    function toggleRevertOnOracleFailure() external onlyOwner {
        revertOnOracleFailure = revertOnOracleFailure ? false : true;
    }

    function setSharePriceOracle(ERC4626SharePriceOracle _sharePriceOracle) external onlyOwner {
        sharePriceOracle = _sharePriceOracle;
        // TODO emit an event
    }

    // TODO getLatest could return the decimals of the oracle
    function _getTotalAssets(bool useUpper) internal view override returns (uint256 _totalAssets) {
        ERC4626SharePriceOracle _sharePriceOracle = sharePriceOracle;

        uint8 assetDecimals = asset.decimals();

        // Check if sharePriceOracle is set.
        if (address(_sharePriceOracle) != address(0)) {
            // Consult the oracle.
            (uint256 latestAnswer, uint256 timeWeightedAverageAnswer, bool isNotSafeToUse) = _sharePriceOracle
                .getLatest();
            if (isNotSafeToUse) revert Cellar__OracleFailure();
            else {
                uint256 sharePrice;
                if (useUpper)
                    sharePrice = latestAnswer > timeWeightedAverageAnswer ? latestAnswer : timeWeightedAverageAnswer;
                else sharePrice = latestAnswer < timeWeightedAverageAnswer ? latestAnswer : timeWeightedAverageAnswer;
                uint8 oracleDecimals = _sharePriceOracle.decimals();
                if (oracleDecimals != assetDecimals) sharePrice.changeDecimals(oracleDecimals, assetDecimals);
                // Convert share price to totalAssets.
                uint256 totalShares = totalSupply;
                _totalAssets = sharePrice.mulDivDown(totalShares, 10 ** decimals);
                return _totalAssets;
            }
        } else revert Cellar__OracleFailure();
    }
}
