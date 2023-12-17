// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Math } from "src/modules/adaptors/BaseAdaptor.sol";

import { ComptrollerG7 as Comptroller, CErc20, PriceOracle, CEther } from "src/interfaces/external/ICompound.sol";
import { IWETH9 } from "src/interfaces/external/IWETH9.sol";
// import "lib/forge-std/src/console.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "lib/forge-std/src/Test.sol";

// import { console } from "lib/forge-std/src/Test.sol";

/**
 * @title CompoundV2 Helper Logic contract.
 * @notice Implements health factor logic used by both
 *         the CTokenAdaptorV2 && CompoundV2DebtAdaptor
 * @author crispymangoes, 0xEinCodes
 */
contract CompoundV2HelperLogic is Test {
    using Math for uint256;
    using SafeTransferLib for ERC20;

    /**
     @notice Compound action returned a non zero error code.
     */
    error CompoundV2HelperLogic__NonZeroCompoundErrorCode(uint256 errorCode);

    /**
     @notice Compound oracle returned a zero oracle value.
     @param asset that oracle query is associated to
     */
    error CompoundV2HelperLogic__OracleCannotBeZero(CErc20 asset);

    /**
     * @notice The ```_getHealthFactor``` function returns the current health factor
     * TODO: fix decimals aspects in this
     */
    function _getHealthFactor(address _account, Comptroller comptroller) public view returns (uint256 healthFactor) {
        // Health Factor Calculations

        // get the array of markets currently being used
        CErc20[] memory marketsEntered = comptroller.getAssetsIn(address(_account));

        PriceOracle oracle = comptroller.oracle();
        uint256 sumCollateral;
        uint256 sumBorrow;
        console.log("Oracle, also setting console.log: %s", address(oracle));

        for (uint256 i = 0; i < marketsEntered.length; i++) {
            CErc20 asset = marketsEntered[i];
            // call accrueInterest() to update exchange rates before going through the loop --> TODO --> test if we need this by seeing if the exchange rates are 'kicked' when going through the rest of it. If so, remove this line of code.
            // uint256 errorCode = asset.accrueInterest(); // TODO: resolve error about potentially modifying state
            // if (errorCode != 0) revert CompoundV2HelperLogic__NonZeroCompoundErrorCode(errorCode);

            // TODO We're going through a loop to calculate total collateral & total borrow for HF calcs (Starting below) w/ assets we're in.
            (uint256 oErr, uint256 cTokenBalance, uint256 borrowBalance, uint256 exchangeRateMantissa) = asset
                .getAccountSnapshot(_account);
            if (oErr != 0) revert CompoundV2HelperLogic__NonZeroCompoundErrorCode(oErr);
            // console.log(
            //     "oErr: %s, cTokenBalance: %s, borrowBalance: %s, exchangeRateMantissa: %s",
            //     oErr,
            //     cTokenBalance,
            //     borrowBalance,
            //     exchangeRateMantissa
            // );

            // get collateral factor from markets
            (, uint256 collateralFactor, ) = comptroller.markets(address(asset));
            // console.log("CollateralFactor: %s", collateralFactor);

            // TODO console.log to see what the values look like (decimals, etc.)

            // TODO Then normalize the values and get the HF with them. If it's safe, then we're good, if not revert.
            uint256 oraclePriceMantissa = oracle.getUnderlyingPrice(asset);
            // console.log("oraclePriceMantissa: %s", oraclePriceMantissa);

            if (oraclePriceMantissa == 0) revert CompoundV2HelperLogic__OracleCannotBeZero(asset);

            // TODO: possibly convert oraclePriceMantissa to Exp format (like compound where it is 18 decimals representation)
            uint256 tokensToDenom = (collateralFactor * exchangeRateMantissa) * oraclePriceMantissa; // TODO: make this 18 decimals --> units are underlying/cToken *
            // console.log("tokensToDenom: %s", tokensToDenom);

            // What are the units of exchangeRate, oraclePrice, tokensToDenom? Is it underlying/cToken, usd/underlying, usd/cToken, respectively?
            sumCollateral = (tokensToDenom * cTokenBalance) + sumCollateral; // Units --> usd/CToken * cToken --> equates to usd
            // console.log("sumCollateral: %s", sumCollateral);

            sumBorrow = (oraclePriceMantissa * borrowBalance) + sumBorrow; // Units --> usd/underlying * underlying --> equates to usd
            // console.log("sumBorrow: %s", sumBorrow);
        }

        // now we can calculate health factor with sumCollateral and sumBorrow
        healthFactor = sumCollateral / sumBorrow;
    }

    //========================================= Reentrancy Guard Functions =======================================

    /**
     * @notice Attempted to read `locked` from unstructured storage, but found uninitialized value.
     * @dev Most likely an external contract made a delegate call to this contract.
     */
    error CompoundV2HelperLogic___StorageSlotNotInitialized();

    /**
     * @notice Attempted to reenter into this contract.
     */
    error CompoundV2HelperLogic___Reentrancy();

    /**
     * @notice Helper function to read `locked` from unstructured storage.
     */
    function readLockedStorage() internal view returns (uint256 locked) {
        bytes32 position = lockedStoragePosition;
        assembly {
            locked := sload(position)
        }
    }

    /**
     * @notice Helper function to set `locked` to unstructured storage.
     */
    function setLockedStorage(uint256 state) internal {
        bytes32 position = lockedStoragePosition;
        assembly {
            sstore(position, state)
        }
    }

    /**
     * @notice nonReentrant modifier that uses unstructured storage.
     */
    modifier nonReentrant() virtual {
        uint256 locked = readLockedStorage();
        if (locked == 0) revert CompoundV2HelperLogic___StorageSlotNotInitialized();
        if (locked != 1) revert CompoundV2HelperLogic___Reentrancy();

        setLockedStorage(2);

        _;

        setLockedStorage(1);
    }

    /**
     * @notice Address of Native cToken Market.
     * @dev Use for 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5 for mainnet.
     */
    address public immutable cNative;

    /**
     * @notice The slot to store value needed to check for re-entrancy.
     */
    bytes32 public immutable lockedStoragePosition;

    /**
     * @notice The native token Wrapper contract on current chain.
     */
    address public immutable nativeWrapper;

    constructor(address _cNative, address _nativeWrapper) {
        cNative = _cNative;
        nativeWrapper = _nativeWrapper;

        lockedStoragePosition =
            keccak256(abi.encode(uint256(keccak256("curve.helper.storage")) - 1)) &
            ~bytes32(uint256(0xff));

        // Initialize locked storage to 1;
        setLockedStorage(1);
    }

    receive() external payable {}

    function mintNativeViaProxy(uint256 wrappedNativeIn) external nonReentrant returns (uint256 errorCode) {
        // Transfer wrapped native in.
        ERC20 wrappedNative = ERC20(nativeWrapper);
        wrappedNative.safeTransferFrom(msg.sender, address(this), wrappedNativeIn);

        // Unwrap it
        IWETH9(nativeWrapper).withdraw(wrappedNativeIn);

        ERC20 cNativeErc20 = ERC20(cNative);
        uint256 nativeCTokenDelta = cNativeErc20.balanceOf(address(this));

        // call mint on market
        CEther(cNative).mint{ value: wrappedNativeIn }();

        nativeCTokenDelta = cNativeErc20.balanceOf(address(this)) - nativeCTokenDelta;

        // transfer delta balance of cTokens to caller
        cNativeErc20.safeTransfer(msg.sender, nativeCTokenDelta);

        // No errors occurred.
        errorCode = 0;
    }

    function redeemNativeViaProxy(uint256 cNativeIn) external nonReentrant returns (uint256 errorCode) {
        ERC20 cNativeErc20 = ERC20(cNative);
        cNativeErc20.safeTransferFrom(msg.sender, address(this), cNativeIn);

        uint256 nativeDelta = address(this).balance;

        errorCode = CEther(cNative).redeem(cNativeIn);

        nativeDelta = address(this).balance - nativeDelta;

        // Wrap Native.
        IWETH9(nativeWrapper).deposit{ value: nativeDelta }();

        // Transfer wrapped native to sender.
        ERC20(nativeWrapper).safeTransfer(msg.sender, nativeDelta);
    }

    function repayNativeViaProxy(uint256 amountToRepay) external nonReentrant returns (uint256 errorCode) {
        // Transfer wrapped native in.
        ERC20 wrappedNative = ERC20(nativeWrapper);
        wrappedNative.safeTransferFrom(msg.sender, address(this), amountToRepay);

        // Unwrap it
        IWETH9(nativeWrapper).withdraw(amountToRepay);

        CEther(cNative).repayBorrowBehalf{ value: amountToRepay }(msg.sender);

        // No errors occurred.
        errorCode = 0;
    }

    function borrowNativeViaProxy(uint256 amountToBorrow) external nonReentrant returns (uint256 errorCode) {
        uint256 nativeDelta = address(this).balance;

        errorCode = CEther(cNative).borrow(amountToBorrow);

        nativeDelta = address(this).balance - nativeDelta;

        // Wrap Native.
        IWETH9(nativeWrapper).deposit{ value: nativeDelta }();

        // Transfer wrapped native to sender.
        ERC20(nativeWrapper).safeTransfer(msg.sender, nativeDelta);
    }
}
