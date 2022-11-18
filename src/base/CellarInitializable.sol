// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, Registry, ERC20 } from "src/base/Cellar.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { console } from "@forge-std/Test.sol";

contract CellarInitializable is Cellar, Initializable {
    constructor(Registry _registry)
        Cellar(
            _registry,
            ERC20(address(0)),
            "",
            "",
            abi.encode(
                new uint32[](0),
                new uint32[](0),
                new bytes[](0),
                new bytes[](0),
                100, // Pick an invalid holding index so we skip the asset check.
                address(0),
                0,
                0
            )
        )
    {}

    function initialize(bytes calldata params) external initializer {
        (Registry _registry, ERC20 _asset, string memory _name, string memory _symbol, bytes memory _params) = abi
            .decode(params, (Registry, ERC20, string, string, bytes));
        // Initialize Cellar
        registry = _registry;
        asset = _asset;
        owner = _registry.getAddress(0);
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
        // Initialize last accrual timestamp to time that cellar was initialized, otherwise the first
        // `accrue` will take platform fees from 1970 to the time it is called.
        (
            uint32[] memory _creditPositions,
            uint32[] memory _debtPositions,
            bytes[] memory _creditConfigurationData,
            bytes[] memory _debtConfigurationData,
            uint8 _holdingIndex,
            address _strategistPayout,
            uint128 _assetRiskTolerance,
            uint128 _protocolRiskTolerance
        ) = abi.decode(_params, (uint32[], uint32[], bytes[], bytes[], uint8, address, uint128, uint128));
        // Initialize positions.
        holdingIndex = _holdingIndex;
        for (uint32 i; i < _creditPositions.length; i++)
            _addPosition(i, _creditPositions[i], _creditConfigurationData[i], false);
        for (uint32 i; i < _debtPositions.length; i++)
            _addPosition(i, _debtPositions[i], _debtConfigurationData[i], true);

        assetRiskTolerance = _assetRiskTolerance;
        protocolRiskTolerance = _protocolRiskTolerance;
        feeData = FeeData({
            strategistPlatformCut: 0.75e18,
            platformFee: 0.01e18,
            lastAccrual: uint64(block.timestamp),
            strategistPayoutAddress: _strategistPayout
        });
    }
}
