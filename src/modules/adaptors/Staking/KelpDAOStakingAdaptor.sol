// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StakingAdaptor, IWETH9 } from "./StakingAdaptor.sol";
import { ILRTDepositPool } from "src/interfaces/external/IStaking.sol";

/**
 * @title Kelp DAO Staking Adaptor
 * @notice Allows Cellars to stake with Kelp.
 * @dev Kelp DAO only supports minting.
 * @author crispymangoes
 */
contract KelpDAOStakingAdaptor is StakingAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Address for address;

    /**
     * @notice Attempted mint had high slippage.
     */
    error KelpDAOStakingAdaptor__Slippage(uint256 valueOut, uint256 minValueOut);

    /**
     * @notice LRT deposit pool deposits are made to.
     */
    ILRTDepositPool public immutable lrtDepositPool;

    /**
     * @notice Token returned from deposits.
     */
    ERC20 public immutable rsETH;

    constructor(
        address _wrappedNative,
        uint8 _maxRequests,
        address _lrtDepositPool,
        address _rsETH
    ) StakingAdaptor(_wrappedNative, _maxRequests) {
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
        return keccak256(abi.encode("Kelp DAO Staking Adaptor V 0.0"));
    }

    //============================================ Override Functions ===========================================

    /**
     * @notice Deposit into Kelp LRT pool to get rsETH.
     */
    function _mintERC20(
        ERC20 depositAsset,
        uint256 amount,
        uint256 minAmountOut,
        bytes calldata
    ) internal override returns (uint256 valueOut) {
        depositAsset.safeApprove(address(lrtDepositPool), amount);
        valueOut = rsETH.balanceOf(address(this));
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
