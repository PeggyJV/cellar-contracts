// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StakingAdaptor, IWETH9 } from "./StakingAdaptor.sol";

interface ILRTDepositPool {
    function depositAsset(
        address asset,
        uint256 depositAmount,
        uint256 minRSETHAmountToReceive,
        string calldata referralId
    ) external;
}

/**
 * @title Kelp DAO Staking Adaptor
 * @notice Allows Cellars to swap with 0x.
 * @author crispymangoes
 */
contract KelpDAOStakingAdaptor is StakingAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Address for address;

    //==================== Adaptor Data Specification ====================
    // NOT USED
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // This adaptor has NO underlying position, its only purpose is to
    // expose the swap function to strategists during rebalances.
    //====================================================================

    error KelpDAOStakingAdaptor__Slippage(uint256 valueOut, uint256 minValueOut);

    ILRTDepositPool public immutable lrtDepositPool;
    ERC20 public immutable rsETH;

    constructor(address _wrappedNative, address _lrtDepositPool, address _rsETH) StakingAdaptor(_wrappedNative, 8) {
        lrtDepositPool = ILRTDepositPool(_lrtDepositPool);
        rsETH = ERC20(_rsETH);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Kelp DAO Staking Adaptor V 1.1"));
    }

    //============================================ Override Functions ===========================================

    function _mintERC20(ERC20 depositAsset, uint256 amount, uint256 minAmountOut) internal override {
        depositAsset.safeApprove(address(lrtDepositPool), amount);
        uint256 valueOut = rsETH.balanceOf(address(this));
        lrtDepositPool.depositAsset(address(depositAsset), amount, minAmountOut, "");
        valueOut = rsETH.balanceOf(address(this)) - valueOut;
        _revokeExternalApproval(depositAsset, address(lrtDepositPool));

        // Perform value in vs value out check.
        PriceRouter priceRouter = Cellar(address(this)).priceRouter();
        uint256 valueIn = priceRouter.getValue(depositAsset, amount, rsETH);

        uint256 minValueOut = valueIn.mulDivDown(slippage(), 1e4);

        if (valueOut < minValueOut) revert KelpDAOStakingAdaptor__Slippage(valueOut, minValueOut);
    }
}
