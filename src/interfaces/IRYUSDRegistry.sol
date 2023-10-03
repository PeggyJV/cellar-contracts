// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

/**
 * @title IRYUSDRegistry
 * @author
 * @notice Interface (primarily used for testing) for RYUSD Registry, an older registry version.
 * @dev TODO: trustAdaptor, trustPosition,
 */
interface IRYUSDRegistry {
    function trustPosition(
        address adaptor,
        bytes memory adaptorData,
        uint128 assetRisk,
        uint128 protocolRisk
    ) external returns (uint32 positionId);

    function trustAdaptor(address adaptor, uint128 assetRisk, uint128 protocolRisk) external;

    function addPosition(uint32 index, uint32 positionId, bytes memory configurationData, bool inDebtArray) external;

    function setAddress(uint256 id, address newAddress) external;

    function getAddress(uint256) external returns (address);
}
