// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, Registry, ERC20 } from "src/base/Cellar.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract CellarImplementation is Cellar, Initializable {
    constructor()
        Cellar(Registry(address(0)), ERC20(address(0)), new uint32[](0), new bytes[](0), "", "", address(0), 0, 0)
    {}

    function initialize(
        Registry _registry,
        ERC20 _asset,
        uint32[] memory _positions,
        bytes[] memory _configurationData,
        string memory _name,
        string memory _symbol,
        address _strategistPayout,
        uint128 _assetRiskTolerance,
        uint128 _protocolRiskTolerance
    ) external initializer {
        registry = _registry;
        asset = _asset;
        name = _name;
        symbol = _symbol;
        decimals = 18;
        assetRiskTolerance = _assetRiskTolerance;
        protocolRiskTolerance = _protocolRiskTolerance;
        owner = _registry.getAddress(0);
        shareLockPeriod = MAXIMUM_SHARE_LOCK_PERIOD;
        allowedRebalanceDeviation = 0.003e18;
        aavePool = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;

        // Initialize last accrual timestamp to time that cellar was initialized, otherwise the first
        // `accrue` will take platform fees from 1970 to the time it is called.
        feeData = FeeData({
            strategistPlatformCut: 0.75e18,
            platformFee: 0.01e18,
            lastAccrual: uint64(block.timestamp),
            feesDistributor: hex"000000000000000000000000b813554b423266bbd4c16c32fa383394868c1f55", // 20 bytes, so need 12 bytes of zero
            strategistPayoutAddress: _strategistPayout
        });

        // Initialize positions.
        positions = _positions;
        for (uint256 i; i < _positions.length; i++) {
            uint32 position = _positions[i];

            if (isPositionUsed[position]) revert Cellar__PositionAlreadyUsed(position);

            (address adaptor, bool isDebt, bytes memory adaptorData) = registry.cellarAddPosition(
                position,
                _assetRiskTolerance,
                _protocolRiskTolerance
            );

            isPositionUsed[position] = true;
            getPositionData[position] = Registry.PositionData({
                adaptor: adaptor,
                isDebt: isDebt,
                adaptorData: adaptorData,
                configurationData: _configurationData[i]
            });
            if (isDebt) numberOfDebtPositions++;
        }

        // Initialize holding position.
        // Holding position is the zero position.
        ERC20 holdingPositionAsset = _assetOf(_positions[0]);
        if (holdingPositionAsset != _asset)
            revert Cellar__AssetMismatch(address(holdingPositionAsset), address(_asset));
    }
}
