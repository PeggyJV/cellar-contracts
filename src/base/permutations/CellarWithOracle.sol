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

    ERC4626SharePriceOracle public sharePriceOracle;
    event SharePriceOracleUpdated(address newOracle);

    uint8 public constant ORACLE_DECIMALS = 18;

    error Cellar__OracleFailure();

    //TODO governance only
    function setSharePriceOracle(ERC4626SharePriceOracle _sharePriceOracle) external onlyOwner {
        if (_sharePriceOracle.ORACLE_DECIMALS() != ORACLE_DECIMALS) revert Cellar__OracleFailure();
        sharePriceOracle = _sharePriceOracle;
        emit SharePriceOracleUpdated(address(_sharePriceOracle));
    }

    /**
     * @notice _totalAssets calculation is dependent on the Cellar having the same amount of decimals as the underlying asset.
     */
    function _getTotalAssetsAndTotalSupply(
        bool useUpper
    ) internal view override returns (uint256 _totalAssets, uint256 _totalSupply) {
        ERC4626SharePriceOracle _sharePriceOracle = sharePriceOracle;

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
                // Convert share price to totalAssets.
                _totalSupply = totalSupply;
                _totalAssets = sharePrice.mulDivDown(_totalSupply, 10 ** ORACLE_DECIMALS);
            }
        } else revert Cellar__OracleFailure();
    }
}
