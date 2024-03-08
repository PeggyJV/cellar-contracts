// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

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

    /**
     * @notice The ERC4626 Share Price Oracle this Cellar uses to calculate its totalAssets,
     *         during user entry/exits.
     */
    ERC4626SharePriceOracle public sharePriceOracle;

    /**
     * @notice Emitted when Share Price Oracle is changed.
     */
    event SharePriceOracleUpdated(address newOracle);

    /**
     * @notice The decimals the Cellar is expecting the oracle to have.
     */
    uint8 internal constant ORACLE_DECIMALS = 18;

    /**
     * @notice Some failure occurred while trying to setup/use the oracle.
     */
    error Cellar__OracleFailure();

    /**
     * @notice Change the share price oracle this Cellar uses for share price calculations.
     * @dev Only callable through Sommelier Governance.
     * @dev Trying to set the share price oracle to the zero address will revert here.
     * @dev Callable by Sommelier Governance.
     */
    function setSharePriceOracle(uint256 _registryId, ERC4626SharePriceOracle _sharePriceOracle) external requiresAuth {
        _checkRegistryAddressAgainstExpected(_registryId, address(_sharePriceOracle));
        if (_sharePriceOracle.decimals() != ORACLE_DECIMALS || address(_sharePriceOracle.target()) != address(this))
            revert Cellar__OracleFailure();
        sharePriceOracle = _sharePriceOracle;
        emit SharePriceOracleUpdated(address(_sharePriceOracle));
    }

    /**
     * @notice Estimate totalAssets be querying oracle to get latest answer, and time weighted average answer.
     * @dev If useUpper is true, use larger of the 2 to maximize share price
     *      else use smaller of the 2 to minimize share price
     * @dev _totalAssets calculation is dependent on the Cellar having the same amount of decimals as the underlying asset.
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
