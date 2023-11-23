// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, ERC20, Registry } from "src/base/Cellar.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";

contract MockCellarWithOracle is Cellar {
    /// @notice Add this so that CurveAdaptor thinks this mock contract has a share price oracle.
    ERC4626SharePriceOracle internal _sharePriceOracle;

    function sharePriceOracle() external view returns (ERC4626SharePriceOracle) {
        return _sharePriceOracle;
    }

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
}
