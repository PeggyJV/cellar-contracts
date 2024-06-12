// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface SimpleStakingERC20 {
    struct Supported {
        bool deposit;
        bool withdraw;
    }

    error ADDRESS_NULL();
    error AMOUNT_NULL();
    error AddressEmptyCode(address target);
    error AddressInsufficientBalance(address account);
    error FailedInnerCall();
    error INSUFFICIENT_BALANCE();
    error OwnableInvalidOwner(address owner);
    error OwnableUnauthorizedAccount(address account);
    error ReentrancyGuardReentrantCall();
    error SafeERC20FailedOperation(address token);
    error TOKEN_NOT_ALLOWED(address token);

    event Deposit(address indexed token, address indexed staker, uint256 amount);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SupportedToken(address indexed token, Supported supported);
    event Withdraw(address indexed token, address indexed staker, uint256 amount);

    function acceptOwnership() external;
    function deposit(address _token, uint256 _amount, address _receiver) external;
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function renounceOwnership() external;
    function rescueERC20(address _token) external;
    function stakedBalances(address, address) external view returns (uint256);
    function supportToken(address _token, Supported memory _supported) external;
    function supportedTokens(address) external view returns (bool deposit, bool withdraw);
    function totalStakedBalance(address) external view returns (uint256);
    function transferOwnership(address newOwner) external;
    function withdraw(address _token, uint256 _amount, address _receiver) external;
}
