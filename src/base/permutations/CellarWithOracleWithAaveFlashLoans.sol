// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, Registry, ERC20, Math, SafeTransferLib } from "src/base/Cellar.sol";

import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";

contract CellarWithOracleWithAaveFlashLoans is Cellar {
    using Math for uint256;
    using SafeTransferLib for ERC20;

    /**
     * @notice The Aave V2 Pool contract on current network.
     * @dev For mainnet use 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9.
     */
    address public immutable aavePool;

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
        uint192 _shareSupplyCap,
        address _aavePool
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
    {
        aavePool = _aavePool;
    }

    // ========================================= Share Price Oracle Support =========================================

    ERC4626SharePriceOracle public sharePriceOracle;

    event SharePriceOracleUpdated(address newOracle);

    error Cellar__OracleFailure();

    function setSharePriceOracle(ERC4626SharePriceOracle _sharePriceOracle) external onlyOwner {
        if (decimals != _sharePriceOracle.decimals()) revert Cellar__OracleFailure();
        sharePriceOracle = _sharePriceOracle;
        emit SharePriceOracleUpdated(address(_sharePriceOracle));
    }

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
                _totalAssets = sharePrice.mulDivDown(_totalSupply, 10 ** decimals);
            }
        } else revert Cellar__OracleFailure();
    }

    // ========================================= Aave Flash Loan Support =========================================
    /**
     * @notice External contract attempted to initiate a flash loan.
     */
    error Cellar__ExternalInitiator();

    /**
     * @notice executeOperation was not called by the Aave Pool.
     */
    error Cellar__CallerNotAavePool();

    /**
     * @notice Allows strategist to utilize Aave flashloans while rebalancing the cellar.
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        if (initiator != address(this)) revert Cellar__ExternalInitiator();
        if (msg.sender != aavePool) revert Cellar__CallerNotAavePool();

        AdaptorCall[] memory data = abi.decode(params, (AdaptorCall[]));

        // Run all adaptor calls.
        _makeAdaptorCalls(data);

        // Approve pool to repay all debt.
        for (uint256 i = 0; i < amounts.length; ++i) {
            ERC20(assets[i]).safeApprove(aavePool, (amounts[i] + premiums[i]));
        }

        return true;
    }
}
