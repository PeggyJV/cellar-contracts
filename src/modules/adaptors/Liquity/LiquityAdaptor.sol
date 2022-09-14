// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Cellar } from "src/base/Cellar.sol";
import { ITroveManager as TroveManager } from "src/interfaces/external/Liquity/ITroveManager.sol";
import { IBorrowerOperations as BorrowerOperations } from "src/interfaces/external/Liquity/IBorrowerOperations.sol";
import { IWETH9 } from "src/interfaces/external/IWETH9.sol";

import { console } from "@forge-std/Test.sol";

/**
 * @title Lending Adaptor
 * @notice Cellars make delegate call to this contract in order touse
 * @author crispymangoes, Brian Le
 * @dev while testing on forked mainnet, aave deposits would sometimes return 1 less aUSDC, and sometimes return the exact amount of USDC you put in
 * Block where USDC in == aUSDC out 15174148
 * Block where USDC-1 in == aUSDC out 15000000
 */

contract LiquityAdaptor {
    using SafeTransferLib for ERC20;

    /*
        adaptorData = abi.encode(aToken address)
    */

    //============================================ Global Functions ===========================================
    function borrowerOperations() internal pure returns (BorrowerOperations) {
        return BorrowerOperations(0x24179CD81c9e782A4096035f7eC97fB8B783e007);
    }

    function troveManager() internal pure returns (TroveManager) {
        return TroveManager(0xA39739EF8b0231DbFA0DcdA07d7e29faAbCf4bb2);
    }

    function LUSD() internal pure returns (ERC20) {
        return ERC20(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0);
    }

    function WETH() internal pure returns (IWETH9) {
        return IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    }

    function WETHERC20() internal pure returns (ERC20) {
        return ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    }

    //============================================ High Level Callable Functions ============================================
    //TODO might need to add a check that toggles use reserve as collateral
    function openTrove(
        uint256 _value,
        uint256 _maxFee,
        uint256 _LUSDAmount,
        address _upperHint,
        address _lowerHint
    ) public {
        WETH().withdraw(_value);
        borrowerOperations().openTrove{ value: _value }(_maxFee, _LUSDAmount, _upperHint, _lowerHint);
    }

    function addColl(
        uint256 _value,
        address _upperHint,
        address _lowerHint
    ) public {
        WETH().withdraw(_value);
        borrowerOperations().addColl{ value: _value }(_upperHint, _lowerHint);
    }

    //function moveETHGainToTrove(
    //    address _user,
    //    address _upperHint,
    //    address _lowerHint
    //) external payable;

    function withdrawColl(
        uint256 _amount,
        address _upperHint,
        address _lowerHint
    ) public {
        borrowerOperations().withdrawColl(_amount, _upperHint, _lowerHint);
        WETH().deposit{ value: _amount }();
    }

    function withdrawLUSD(
        uint256 _maxFee,
        uint256 _amount,
        address _upperHint,
        address _lowerHint
    ) public {
        borrowerOperations().withdrawLUSD(_maxFee, _amount, _upperHint, _lowerHint);
    }

    function repayLUSD(
        uint256 _amount,
        address _upperHint,
        address _lowerHint
    ) external {
        borrowerOperations().repayLUSD(_amount, _upperHint, _lowerHint);
    }

    // Closes Trove and converts all ETH to WETH.
    function closeTrove() external {
        borrowerOperations().closeTrove();
        WETH().deposit{ value: address(this).balance }();
    }

    //function adjustTrove(
    //    uint256 _maxFee,
    //    uint256 _collWithdrawal,
    //    uint256 _debtChange,
    //    bool isDebtIncrease,
    //    address _upperHint,
    //    address _lowerHint
    //) external payable;

    //function claimCollateral() external;
}
