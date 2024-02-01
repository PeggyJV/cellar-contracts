// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Registry, ERC20, Math, SafeTransferLib, Address } from "src/base/Cellar.sol";
import { CellarWithOracleWithAaveFlashLoansWithMultiAssetDeposit } from "src/base/permutations/advanced/CellarWithOracleWithAaveFlashLoansWithMultiAssetDeposit.sol";

contract CellarWithOracleWithAaveFlashLoansWithMultiAssetDepositWithNativeSupport is
    CellarWithOracleWithAaveFlashLoansWithMultiAssetDeposit
{
    //============================== IMMUTABLES ===============================

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
        CellarWithOracleWithAaveFlashLoansWithMultiAssetDeposit(
            _owner,
            _registry,
            _asset,
            _name,
            _symbol,
            _holdingPosition,
            _holdingPositionConfig,
            _initialDeposit,
            _strategistPlatformCut,
            _shareSupplyCap,
            _aavePool
        )
    {}

    /**
     * @notice Implement receive so Cellar can accept native transfers.
     */
    receive() external payable {}
}
