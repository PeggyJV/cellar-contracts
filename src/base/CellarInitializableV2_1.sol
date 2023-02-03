// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, Registry, ERC20 } from "src/base/Cellar.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract CellarInitializableV2_1 is Cellar, Initializable {
    /**
     * @notice Constructor is only called for the implementation contract,
     *         so it can be safely filled with mostly zero inputs.
     */
    constructor(Registry _registry)
        Cellar(
            _registry,
            ERC20(address(0)),
            "",
            "",
            abi.encode(new uint32[](0), new uint32[](0), new bytes[](0), new bytes[](0), 0, address(0), 0, 0)
        )
    {}

    /**
     * @notice Initialize function called by factory contract immediately after deployment.
     * @param params abi encoded parameter containing
     *               - Registry contract
     *               - ERC20 cellar asset
     *               - String name of cellar
     *               - String symbol of cellar
     *               - bytes abi encoded parameter containing
     *                 - uint32[] array of credit positions
     *                 - uint32[] array of debt positions
     *                 - bytes[] array of credit config data
     *                 - bytes[] array of debt config data
     *                 - uint32 holding position id
     *                 - address strategist payout address
     *                 - uint128 asset risk tolerance
     *                 - uint128 protocol risk tolerance
     */
    function initialize(bytes calldata params) external initializer {
        (
            address tmpOwner,
            Registry _registry,
            ERC20 _asset,
            string memory _name,
            string memory _symbol,
            bytes memory _params
        ) = abi.decode(params, (address, Registry, ERC20, string, string, bytes));
        // Initialize Cellar
        registry = _registry;
        asset = _asset;
        owner = tmpOwner;
        shareLockPeriod = MAXIMUM_SHARE_LOCK_PERIOD;
        allowedRebalanceDeviation = 0.003e18;
        aavePool = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
        // Initialize ERC20
        name = _name;
        symbol = _symbol;
        decimals = 18;
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
        // Initialize Reentrancy Guard
        locked = 1;

        // Initialize positions.
        (
            uint32[] memory _creditPositions,
            uint32[] memory _debtPositions,
            bytes[] memory _creditConfigurationData,
            bytes[] memory _debtConfigurationData,
            uint32 _holdingPosition,
            address _strategistPayout,
            uint128 _assetRiskTolerance,
            uint128 _protocolRiskTolerance
        ) = abi.decode(_params, (uint32[], uint32[], bytes[], bytes[], uint32, address, uint128, uint128));

        for (uint32 i; i < _creditPositions.length; i++)
            _addPosition(i, _creditPositions[i], _creditConfigurationData[i], false);
        for (uint32 i; i < _debtPositions.length; i++)
            _addPosition(i, _debtPositions[i], _debtConfigurationData[i], true);
        _setHoldingPosition(_holdingPosition);

        // Initialize remaining values.
        assetRiskTolerance = _assetRiskTolerance;
        protocolRiskTolerance = _protocolRiskTolerance;
        feeData = FeeData({
            strategistPlatformCut: 0.8e18,
            platformFee: 0.005e18,
            lastAccrual: uint64(block.timestamp),
            strategistPayoutAddress: _strategistPayout
        });
    }
}
