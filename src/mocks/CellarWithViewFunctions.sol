// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, Registry, ERC20 } from "src/base/Cellar.sol";

contract CellarWithViewFunctions is Cellar {
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

    function getCreditPosition(uint256 index) external view returns (uint32 position) {
        return creditPositions[index];
    }

    function getPositionDataView(
        uint32 position
    ) external view returns (address adaptor, bool isDebt, bytes memory adaptorData, bytes memory configurationData) {
        Registry.PositionData memory data = getPositionData[position];
        return (data.adaptor, data.isDebt, data.adaptorData, data.configurationData);
    }
}
