// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import { IAllocatorConduit } from "./IAllocatorConduit.sol";

/**
 *  @title IArrangerConduit
 *  @dev   Conduits are to be used to manage positions for multiple Allocators.
 *         After funds are deposited into a Conduit, they can be deployed by Arrangers to earn
 *         yield. When Allocators want funds back, they can request funds from the Arrangers and
 *         then withdraw once liquidity is available.
 */
interface IArrangerConduit is IAllocatorConduit {
    /**********************************************************************************************/
    /*** Administrative Events                                                                  ***/
    /**********************************************************************************************/

    /**
     *  @dev   Event emitted when a value is changed by an admin.
     *  @param what The identifier of the value changed.
     *  @param data The new value of the identifier.
     */
    event File(bytes32 indexed what, address data);

    /**
     *  @dev   Event emitted when a broker is added or removed from the whitelist.
     *  @param broker The address of the broker.
     *  @param asset  The address of the asset.
     *  @param valid  Boolean value indicating if the broker is whitelisted or not.
     */
    event SetBroker(address indexed broker, address indexed asset, bool valid);

    /**********************************************************************************************/
    /*** Fund Events                                                                            ***/
    /**********************************************************************************************/

    /**
     *  @dev   Event emitted when a fund request is cancelled.
     *  @param fundRequestId The ID of the cancelled fund request.
     */
    event CancelFundRequest(uint256 fundRequestId);

    /**
     *  @dev   Event emitted when funds are drawn from the Conduit by the Arranger.
     *  @param asset       The address of the asset to be withdrawn.
     *  @param destination The address to transfer the funds to.
     *  @param amount      The amount of asset to be withdrawn.
     */
    event DrawFunds(address indexed asset, address indexed destination, uint256 amount);

    /**
     *  @dev   Event emitted when a fund request is made.
     *  @param ilk           The unique identifier of the ilk.
     *  @param asset         The address of the asset to be withdrawn.
     *  @param fundRequestId The ID of the fund request.
     *  @param amount        The amount of asset to be withdrawn.
     *  @param info          Arbitrary string to provide additional info to the Arranger.
     */
    event RequestFunds(bytes32 indexed ilk, address indexed asset, uint256 fundRequestId, uint256 amount, string info);

    /**
     *  @dev   Event emitted when an Arranger returns funds to the Conduit to fill a fund request.
     *  @param ilk             The unique identifier of the ilk.
     *  @param asset           The address of the asset to be withdrawn.
     *  @param fundRequestId   The ID of the fund request.
     *  @param amountRequested The amount of asset that was requested by the ilk to be withdrawn.
     *  @param returnAmount    The resulting amount that was returned by the Arranger.
     */
    event ReturnFunds(
        bytes32 indexed ilk,
        address indexed asset,
        uint256 fundRequestId,
        uint256 amountRequested,
        uint256 returnAmount
    );

    /**********************************************************************************************/
    /*** Data Types                                                                             ***/
    /**********************************************************************************************/

    /**
     *  @dev   Struct representing a fund request.
     *  @param status          The current status of the fund request.
     *  @param asset           The address of the asset requested in the fund request.
     *  @param ilk             The unique identifier of the ilk.
     *  @param amountRequested The amount of asset requested in the fund request.
     *  @param amountFilled    The amount of asset filled in the fund request.
     *  @param info            Arbitrary string to provide additional info to the Arranger.
     */
    struct FundRequest {
        StatusEnum status;
        address asset;
        bytes32 ilk;
        uint256 amountRequested;
        uint256 amountFilled;
        string info;
    }

    /**
     *  @dev    Enum representing the status of a fund request.
     *  @notice PENDING   - Null state before the fund request has been made.
     *  @notice PENDING   - The fund request has been made, but not yet processed.
     *  @notice CANCELLED - The fund request has been cancelled by the ilk.
     *  @notice COMPLETED - The fund request has been fully processed and completed.
     */
    enum StatusEnum {
        UNINITIALIZED,
        PENDING,
        CANCELLED,
        COMPLETED
    }

    /**********************************************************************************************/
    /*** Storage Variables                                                                      ***/
    /**********************************************************************************************/

    /**
     *  @dev    Returns the arranger address.
     *  @return arranger_ The address of the arranger.
     */
    function arranger() external view returns (address arranger_);

    /**
     *  @dev    Returns the AllocationRegistry address.
     *  @return registry_ The address of the registry contract.
     */
    function registry() external view returns (address registry_);

    /**
     *  @dev    Returns the roles address.
     *  @return roles_ The address of the roles.
     */
    function roles() external view returns (address roles_);

    /**
     *  @dev    Returns the total deposits for a given asset.
     *  @param  asset          The address of the asset.
     *  @return totalDeposits_ The total deposits held in the asset.
     */
    function totalDeposits(address asset) external view returns (uint256 totalDeposits_);

    /**
     *  @dev    Returns the total requested funds for a given asset.
     *  @param  asset          The address of the asset.
     *  @return totalRequestedFunds_ The total requested funds held in the asset.
     */
    function totalRequestedFunds(address asset) external view returns (uint256 totalRequestedFunds_);

    /**
     *  @dev    Returns the total amount that can be withdrawn for a given asset.
     *  @param  asset              The address of the asset.
     *  @return totalWithdrawableFunds_ The total amount that can be withdrawn from the asset.
     */
    function totalWithdrawableFunds(address asset) external view returns (uint256 totalWithdrawableFunds_);

    /**
     *  @dev    Returns the total amount of cumulative withdrawals for a given asset.
     *  @param  asset             The address of the asset.
     *  @return totalWithdrawals_ The total amount that can be withdrawn from the asset.
     */
    function totalWithdrawals(address asset) external view returns (uint256 totalWithdrawals_);

    /**
     *  @dev    Returns if an address is a valid broker for a given asset.
     *  @param  broker    The address of the broker to check.
     *  @param  asset     The address of the asset that the broker is valid for.
     *  @return isBroker_ Boolean value indicating if the broker is valid or not.
     */
    function isBroker(address broker, address asset) external view returns (bool isBroker_);

    /**
     *  @dev    Returns the aggregate deposits for a given ilk and asset.
     *  @param  asset     The address of the asset.
     *  @param  ilk       The unique identifier for a particular ilk.
     *  @return deposits_ The deposits for the given ilk and asset.
     */
    function deposits(address asset, bytes32 ilk) external view returns (uint256 deposits_);

    /**
     *  @dev    Returns the aggregate requested funds for a given ilk and asset.
     *  @param  asset           The address of the asset.
     *  @param  ilk             The unique identifier for a particular ilk.
     *  @return requestedFunds_ The requested funds for the given ilk and asset.
     */
    function requestedFunds(address asset, bytes32 ilk) external view returns (uint256 requestedFunds_);

    /**
     *  @dev    Returns the aggregate withdrawable funds for a given ilk and asset.
     *  @param  asset              The address of the asset.
     *  @param  ilk                The unique identifier for a particular ilk.
     *  @return withdrawableFunds_ The withdrawableFunds funds for the given ilk and asset.
     */
    function withdrawableFunds(address asset, bytes32 ilk) external view returns (uint256 withdrawableFunds_);

    /**
     *  @dev    Returns the aggregate cumulative withdraws for a given ilk and asset.
     *  @param  asset        The address of the asset.
     *  @param  ilk          The unique identifier for a particular ilk.
     *  @return withdrawals_ The withdrawals funds for the given ilk and asset.
     */
    function withdrawals(address asset, bytes32 ilk) external view returns (uint256 withdrawals_);

    /**********************************************************************************************/
    /*** Administrative Functions                                                               ***/
    /**********************************************************************************************/

    /**
     *  @dev   Function to set a value in the contract, called by the admin.
     *  @param what The identifier for the value to be set.
     *  @param data The value to be set.
     */
    function file(bytes32 what, address data) external;

    /**********************************************************************************************/
    /*** Operator Functions                                                                     ***/
    /**********************************************************************************************/

    /**
     *  @dev   Function to cancel a withdrawal request from a Arranger.
     *  @param fundRequestId The ID of the withdrawal request.
     */
    function cancelFundRequest(uint256 fundRequestId) external;

    /**
     *  @dev    Function to initiate a withdrawal request from a Arranger.
     *  @param  ilk           The unique identifier for a particular ilk.
     *  @param  asset         The asset to withdraw.
     *  @param  amount        The amount of tokens to withdraw.
     *  @param  info          Arbitrary string to provide additional info to the Arranger.
     *  @return fundRequestId The ID of the withdrawal request.
     */
    function requestFunds(
        bytes32 ilk,
        address asset,
        uint256 amount,
        string memory info
    ) external returns (uint256 fundRequestId);

    /**********************************************************************************************/
    /*** Arranger Functions                                                                     ***/
    /**********************************************************************************************/

    /**
     * @notice Draw funds from the contract to a `destination` that the Arranger specifies. This
     *         destination MUST be a whitelisted `broker` address for the given `asset`.
     * @dev    Only the Arranger is authorized to call this function.
     * @param  asset       The ERC20 token contract address from which funds are being drawn.
     * @param  destination The destination to transfer the funds to.
     * @param  amount      The amount of tokens to be drawn.
     */
    function drawFunds(address asset, address destination, uint256 amount) external;

    /**
     * @notice Return funds (principal only) from the Arranger back to the contract.
     * @dev    Only the Arranger is authorized to call this function.
     * @param  fundRequestId The ID of the withdrawal request.
     * @param  amount        The amount of tokens to be returned.
     */
    function returnFunds(uint256 fundRequestId, uint256 amount) external;

    /**********************************************************************************************/
    /*** View Functions                                                                         ***/
    /**********************************************************************************************/

    /**
     *  @dev    Function to get the amount of funds that can be drawn by the Arranger.
     *  @param  asset           The asset to check.
     *  @return availableFunds_ The amount of funds that can be drawn by the Arranger.
     */
    function availableFunds(address asset) external view returns (uint256 availableFunds_);

    /**
     *  @dev    Returns a FundRequest struct at a given fundRequestId.
     *  @param  fundRequestId The id of the fund request.
     *  @return fundRequest   The FundRequest struct at the fundRequestId.
     */
    function getFundRequest(uint256 fundRequestId) external view returns (FundRequest memory fundRequest);

    /**
     * @dev    Returns the length of the fundRequests array.
     * @return fundRequestsLength The length of the fundRequests array.
     */
    function getFundRequestsLength() external view returns (uint256 fundRequestsLength);

    /**
     *  @dev    Function to check if a withdrawal request can be cancelled.
     *  @param  fundRequestId  The ID of the withdrawal request.
     *  @return isCancelable_  True if the withdrawal request can be cancelled, false otherwise.
     */
    function isCancelable(uint256 fundRequestId) external view returns (bool isCancelable_);
}
