// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface IRegistrar {
    struct RegistrationParams {
        string name;
        bytes encryptedEmail;
        address upkeepContract;
        uint32 gasLimit;
        address adminAddress;
        uint8 triggerType;
        bytes checkData;
        bytes triggerConfig;
        bytes offchainConfig;
        uint96 amount;
    }

    enum AutoApproveType {
        DISABLED,
        ENABLED_SENDER_ALLOWLIST,
        ENABLED_ALL
    }

    function registerUpkeep(RegistrationParams calldata requestParams) external returns (uint256 id);

    function setTriggerConfig(
        uint8 triggerType,
        AutoApproveType autoApproveType,
        uint32 autoApproveMaxAllowed
    ) external;

    function owner() external view returns (address);

    function approve(
        string memory name,
        address upkeepContract,
        uint32 gasLimit,
        address adminAddress,
        uint8 triggerType,
        bytes calldata checkData,
        bytes memory triggerConfig,
        bytes calldata offchainConfig,
        bytes32 hash
    ) external;
}
