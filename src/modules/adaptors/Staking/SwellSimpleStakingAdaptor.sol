// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {BaseAdaptor, ERC20, SafeTransferLib} from "src/modules/adaptors/BaseAdaptor.sol";
import {SimpleStakingERC20 as SwellSimpleStaking} from "src/interfaces/external/SwellSimpleStaking.sol";

/**
 * @title Swell Simple Staking Adaptor
 * @notice Allows Cellars to stake with Swell Simple Staking.
 * @author crispymangoes
 */
contract SwellSimpleStakingAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(ERC20 token)
    // Where:
    // `token` is the underlying ERC20 used with the Swell Simple Staking contract
    //================= Configuration Data Specification =================
    // configurationData = abi.encode(bool isLiquid)
    // Where:
    // `isLiquid` dictates whether the position is liquid or not
    // If true:
    //      position can support use withdraws
    // else:
    //      position can not support user withdraws
    //
    //====================================================================

    /**
     * @notice The Swell Simple Staking contract staking calls are made to.
     */
    SwellSimpleStaking internal immutable swellSimpleStaking;

    constructor(address _swellSimpleStaking) {
        swellSimpleStaking = SwellSimpleStaking(_swellSimpleStaking);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Swell Simple Staking Adaptor V 0.0"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Not supported.
     */
    function deposit(uint256, bytes memory, bytes memory) public virtual override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice Cellar needs to withdraw ERC20's from SwellSimpleStaking.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from the SwellSimpleStaking position
     * @param receiver address to send assets to'
     * @param adaptorData data needed to withdraw from the SwellSimpleStaking position
     * @param configurationData abi encoded bool indicating whether the position is liquid or not
     */
    function withdraw(uint256 assets, address receiver, bytes memory adaptorData, bytes memory configurationData)
        public
        virtual
        override
    {
        // Check that position is setup to be liquid.
        bool isLiquid = abi.decode(configurationData, (bool));
        if (!isLiquid) revert BaseAdaptor__UserWithdrawsNotAllowed();

        // Run external receiver check.
        _externalReceiverCheck(receiver);

        address token = abi.decode(adaptorData, (address));

        // Withdraw assets from `Vault`.
        swellSimpleStaking.withdraw(token, assets, receiver);
    }

    /**
     * @notice Check if position is liquid, then return the amount of assets that can be withdrawn.
     */
    function withdrawableFrom(bytes memory adaptorData, bytes memory configurationData)
        public
        view
        virtual
        override
        returns (uint256)
    {
        bool isLiquid = abi.decode(configurationData, (bool));
        if (isLiquid) {
            address token = abi.decode(adaptorData, (address));
            return swellSimpleStaking.stakedBalances(msg.sender, token);
        } else {
            return 0;
        }
    }

    /**
     * @notice Call `stakedBalances` to get the balance of the Cellar.
     */
    function balanceOf(bytes memory adaptorData) public view virtual override returns (uint256) {
        address token = abi.decode(adaptorData, (address));
        return swellSimpleStaking.stakedBalances(msg.sender, token);
    }

    /**
     * @notice Returns the token in the adaptorData
     */
    function assetOf(bytes memory adaptorData) public view virtual override returns (ERC20) {
        ERC20 token = abi.decode(adaptorData, (ERC20));
        return token;
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure virtual override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Deposits ERC20 tokens into the Swell Simple Staking contract.
     * @dev We are not checking if the position is tracked for simplicity,
     *      this is safe to do since the SwellSimpleStaking contract is immutable,
     *      so we know the Cellar is interacting with a safe contract.
     */
    function depositIntoSimpleStaking(ERC20 token, uint256 amount) external {
        amount = _maxAvailable(token, amount);
        token.safeApprove(address(swellSimpleStaking), amount);
        swellSimpleStaking.deposit(address(token), amount, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(token, address(swellSimpleStaking));
    }

    /**
     * @notice Withdraws ERC20 tokens from the Swell Simple Staking contract.
     * @dev We are not checking if the position is tracked for simplicity,
     *      this is safe to do since the SwellSimpleStaking contract is immutable,
     *      so we know the Cellar is interacting with a safe contract.
     */
    function withdrawFromSimpleStaking(ERC20 token, uint256 amount) external {
        if (amount == type(uint256).max) {
            amount = swellSimpleStaking.stakedBalances(address(this), address(token));
        }
        swellSimpleStaking.withdraw(address(token), amount, address(this));
    }
}
