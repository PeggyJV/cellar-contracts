// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import { UpgradeableProxied } from "./UpgradeableProxied.sol";

import { IArrangerConduit } from "./IArrangerConduit.sol";

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);

    function transfer(address, uint256) external;

    function transferFrom(address, address, uint256) external;
}

interface RolesLike {
    function canCall(bytes32, address, address, bytes4) external view returns (bool);
}

interface RegistryLike {
    function buffers(bytes32 ilk) external view returns (address buffer);
}

contract ArrangerConduit is UpgradeableProxied, IArrangerConduit {
    /**********************************************************************************************/
    /*** Declarations and Constructor                                                           ***/
    /**********************************************************************************************/

    FundRequest[] internal fundRequests;

    address public override arranger;
    address public override registry;
    address public override roles;

    mapping(address => uint256) public override totalDeposits;
    mapping(address => uint256) public override totalRequestedFunds;
    mapping(address => uint256) public override totalWithdrawableFunds;
    mapping(address => uint256) public override totalWithdrawals;

    mapping(address => mapping(address => bool)) public override isBroker;

    mapping(address => mapping(bytes32 => uint256)) public override deposits;
    mapping(address => mapping(bytes32 => uint256)) public override requestedFunds;
    mapping(address => mapping(bytes32 => uint256)) public override withdrawableFunds;
    mapping(address => mapping(bytes32 => uint256)) public override withdrawals;

    /**********************************************************************************************/
    /*** Modifiers                                                                              ***/
    /**********************************************************************************************/

    // modifier atop of wards which are from UpgradeableProxied.sol
    modifier auth() {
        require(wards[msg.sender] == 1, "ArrangerConduit/not-authorized");
        _;
    }

    // ilk is from this contract and used to identify buffer (contracts containing assets from allocators) to move into arrangers posession.
    modifier ilkAuth(bytes32 ilk) {
        _checkAuth(ilk); // modifier checking if the msg.sender if authorized to carry out a respective function call.
        _;
    }

    modifier isArranger() {
        require(msg.sender == arranger, "ArrangerConduit/not-arranger");
        _;
    }

    /**********************************************************************************************/
    /*** Administrative Functions                                                               ***/
    /**********************************************************************************************/

    function file(bytes32 what, address data) external auth {
        if (what == "arranger") arranger = data;
        else if (what == "registry") registry = data;
        else if (what == "roles") roles = data;
        else revert("ArrangerConduit/file-unrecognized-param");
        emit File(what, data);
    }

    function setBroker(address broker, address asset, bool valid) external auth {
        isBroker[broker][asset] = valid;
        emit SetBroker(broker, asset, valid);
    }

    /**********************************************************************************************/
    /*** Operator Functions                                                                     ***/
    /**********************************************************************************************/

    function deposit(bytes32 ilk, address asset, uint256 amount) external override ilkAuth(ilk) {
        deposits[asset][ilk] += amount;
        totalDeposits[asset] += amount;

        address source = RegistryLike(registry).buffers(ilk);

        require(source != address(0), "ArrangerConduit/no-buffer-registered");

        IERC20Like(asset).transferFrom(source, address(this), amount);

        emit Deposit(ilk, asset, source, amount);
    }

    function withdraw(
        bytes32 ilk,
        address asset,
        uint256 maxAmount
    ) external override ilkAuth(ilk) returns (uint256 amount) {
        uint256 withdrawableFunds_ = withdrawableFunds[asset][ilk];

        amount = maxAmount > withdrawableFunds_ ? withdrawableFunds_ : maxAmount;

        withdrawableFunds[asset][ilk] -= amount;
        totalWithdrawableFunds[asset] -= amount;

        withdrawals[asset][ilk] += amount;
        totalWithdrawals[asset] += amount;

        address destination = RegistryLike(registry).buffers(ilk);

        require(destination != address(0), "ArrangerConduit/no-buffer-registered");

        IERC20Like(asset).transfer(destination, amount);

        emit Withdraw(ilk, asset, destination, amount);
    }

    function requestFunds(
        bytes32 ilk,
        address asset,
        uint256 amount,
        string memory info
    ) external override ilkAuth(ilk) returns (uint256 fundRequestId) {
        fundRequestId = fundRequests.length; // Current length will be the next index

        fundRequests.push(
            FundRequest({
                status: StatusEnum.PENDING,
                asset: asset,
                ilk: ilk,
                amountRequested: amount,
                amountFilled: 0,
                info: info
            })
        );

        requestedFunds[asset][ilk] += amount;
        totalRequestedFunds[asset] += amount;

        emit RequestFunds(ilk, asset, fundRequestId, amount, info);
    }

    function cancelFundRequest(uint256 fundRequestId) external override {
        FundRequest memory fundRequest = fundRequests[fundRequestId];

        require(fundRequest.status == StatusEnum.PENDING, "ArrangerConduit/invalid-status");

        address asset = fundRequest.asset;
        bytes32 ilk = fundRequest.ilk;

        _checkAuth(ilk);

        uint256 amountRequested = fundRequest.amountRequested;

        fundRequests[fundRequestId].status = StatusEnum.CANCELLED;

        requestedFunds[asset][ilk] -= amountRequested;
        totalRequestedFunds[asset] -= amountRequested;

        emit CancelFundRequest(fundRequestId);
    }

    /**********************************************************************************************/
    /*** Fund Manager Functions                                                                 ***/
    /**********************************************************************************************/

    // TODO: These functions are where there could be customization in the implementation in accordance to interacting with the `destination` contract
    function drawFunds(address asset, address destination, uint256 amount) external override isArranger {
        require(amount <= availableFunds(asset), "ArrangerConduit/insufficient-funds");
        require(isBroker[destination][asset], "ArrangerConduit/invalid-broker");

        IERC20Like(asset).transfer(destination, amount); // 

        emit DrawFunds(asset, destination, amount);
    }

    // TODO: need to carry out actual transferring of funds within this function
    function returnFunds(uint256 fundRequestId, uint256 returnAmount) external override isArranger {
        FundRequest storage fundRequest = fundRequests[fundRequestId];

        address asset = fundRequest.asset;

        require(fundRequest.status == StatusEnum.PENDING, "ArrangerConduit/invalid-status");
        require(returnAmount <= availableFunds(asset), "ArrangerConduit/insufficient-funds");

        bytes32 ilk = fundRequest.ilk;

        withdrawableFunds[asset][ilk] += returnAmount;
        totalWithdrawableFunds[asset] += returnAmount;

        uint256 amountRequested = fundRequest.amountRequested;

        requestedFunds[asset][ilk] -= amountRequested;
        totalRequestedFunds[asset] -= amountRequested;

        fundRequest.amountFilled = returnAmount;

        fundRequest.status = StatusEnum.COMPLETED;

        emit ReturnFunds(ilk, asset, fundRequestId, amountRequested, returnAmount);
    }

    /**********************************************************************************************/
    /*** View Functions                                                                         ***/
    /**********************************************************************************************/

    function availableFunds(address asset) public view override returns (uint256 availableFunds_) {
        availableFunds_ = IERC20Like(asset).balanceOf(address(this)) - totalWithdrawableFunds[asset];
    }

    function getFundRequest(uint256 fundRequestId) external view override returns (FundRequest memory fundRequest) {
        fundRequest = fundRequests[fundRequestId];
    }

    function getFundRequestsLength() external view override returns (uint256 fundRequestsLength) {
        fundRequestsLength = fundRequests.length;
    }

    function isCancelable(uint256 fundRequestId) external view override returns (bool isCancelable_) {
        isCancelable_ = fundRequests[fundRequestId].status == StatusEnum.PENDING;
    }

    function maxDeposit(bytes32, address) external pure override returns (uint256 maxDeposit_) {
        maxDeposit_ = type(uint256).max;
    }

    function maxWithdraw(bytes32 ilk, address asset) external view override returns (uint256 maxWithdraw_) {
        maxWithdraw_ = withdrawableFunds[asset][ilk];
    }

    /**********************************************************************************************/
    /*** Internal Functions                                                                     ***/
    /**********************************************************************************************/

    function _checkAuth(bytes32 ilk) internal view {
        require(RolesLike(roles).canCall(ilk, msg.sender, address(this), msg.sig), "ArrangerConduit/not-authorized");
    }
}
