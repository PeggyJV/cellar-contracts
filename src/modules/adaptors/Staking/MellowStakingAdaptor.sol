// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StakingAdaptor, IWETH9 } from "./StakingAdaptor.sol";
import { IVault } from "src/interfaces/external/IStaking.sol";
/**
 * @title Mellow Staking Adaptor
 * @notice Allows Cellars to stake with Mellow.
 * @dev Mellow supports deposits, withdrawls.
 * @author zmanian
 */

 contract MellowStakingAdaptor is StakingAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Address for address;

    /**
     * @notice The Mellow LRT vault for this adapter instance.
     */
    IVault public immutable mellowVault;


    /**
     * @notice The eMellow contract.
     */
    ERC20 public immutable vaultToken;


    ERC20 public immutable baseAsset;
    
    constructor(
        address _baseAsset,
        uint8 _maxRequests,
        address _mellowVault,
        address _vaultToken
    ) StakingAdaptor(_baseAsset, _maxRequests) {
        baseAsset = ERC20(_baseAsset);
        mellowVault = IVault(_mellowVault);
        vaultToken = ERC20(_vaultToken);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public override pure returns (bytes32) {
        return keccak256(abi.encodePacked("MellowStakingAdaptor"));
    }

    /**
     * @dev Deposit funds into the Mellow staking contract.
     * @param _amount The amount of funds to deposit.
     */
    function _mintERC20(ERC20, uint256 _amount, uint256, bytes calldata) internal override returns (uint256 shares) {

        baseAsset.safeApprove(address(vaultToken), _amount);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _amount;
        (,uint256 shares) = mellowVault.deposit(address(this), amounts, 0, type(uint256).max);
    }

    /**
     * @dev Withdraw funds from the Mellow staking contract.
     * @param _amount The amount of funds to withdraw.
     */
    function _requestBurn(uint256 _amount, bytes calldata) internal override returns (uint256) {
        uint256[] memory min_amounts = new uint256[](1);
        min_amounts[0] = 0;
        mellowVault.registerWithdrawal(address(this),_amount, min_amounts, type(uint256).max, type(uint256).max, false);
        return 0;
    }

    function _cancelBurn(uint256, bytes calldata) internal override {
        mellowVault.cancelWithdrawalRequest();
    }
 }
