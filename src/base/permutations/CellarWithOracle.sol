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
        // TODO require oracle decimals to be the same as the cellars.
        // TODO emit an event
    }

    function _getTotalAssets(bool useUpper) internal view override returns (uint256 _totalAssets) {
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
                uint256 totalShares = totalSupply;
                _totalAssets = sharePrice.mulDivDown(totalShares, 10 ** decimals);
                return _totalAssets;
            }
        } else revert Cellar__OracleFailure();
    }

    /**
     * @notice Allows strategists to manage their Cellar using arbitrary logic calls to adaptors.
     * @dev There are several safety checks in this function to prevent strategists from abusing it.
     *      - `blockExternalReceiver`
     *      - `totalAssets` must not change by much
     *      - `totalShares` must remain constant
     *      - adaptors must be set up to be used with this cellar
     * @dev Since `totalAssets` is allowed to deviate slightly, strategists could abuse this by sending
     *      multiple `callOnAdaptor` calls rapidly, to gradually change the share price.
     *      To mitigate this, rate limiting will be put in place on the Sommelier side.
     */
    function callOnAdaptor(AdaptorCall[] calldata data) external override onlyOwner nonReentrant {
        _whenNotShutdown();
        _checkIfPaused();
        blockExternalReceiver = true;

        // Record `totalAssets` and `totalShares` before making any external calls.
        uint256 assetsBeforeAdaptorCall;
        uint256 minimumAllowedAssets;
        uint256 maximumAllowedAssets;
        uint256 totalShares;

        ERC4626SharePriceOracle _sharePriceOracle = sharePriceOracle;
        // Check if sharePriceOracle is set.
        if (address(_sharePriceOracle) != address(0)) {
            // Consult the oracle.
            (uint256 latestAnswer, , bool isNotSafeToUse) = _sharePriceOracle.getLatest();
            if (isNotSafeToUse) revert Cellar__OracleFailure();
            else {
                uint256 sharePrice;
                sharePrice = latestAnswer;

                // Convert share price to totalAssets.
                totalShares = totalSupply;
                assetsBeforeAdaptorCall = latestAnswer.mulDivDown(totalShares, 10 ** decimals);
            }
        } else {
            totalShares = totalSupply;
            assetsBeforeAdaptorCall = _accounting(false);
        }
        minimumAllowedAssets = assetsBeforeAdaptorCall.mulDivUp((1e18 - allowedRebalanceDeviation), 1e18);
        maximumAllowedAssets = assetsBeforeAdaptorCall.mulDivUp((1e18 + allowedRebalanceDeviation), 1e18);

        // Run all adaptor calls.
        _makeAdaptorCalls(data);

        // After making every external call, check that the totalAssets haas not deviated significantly, and that totalShares is the same.
        uint256 assets = _accounting(false);
        if (assets < minimumAllowedAssets || assets > maximumAllowedAssets) {
            revert Cellar__TotalAssetDeviatedOutsideRange(assets, minimumAllowedAssets, maximumAllowedAssets);
        }
        if (totalShares != totalSupply) revert Cellar__TotalSharesMustRemainConstant(totalSupply, totalShares);

        blockExternalReceiver = false;
    }
}
