// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, SwapRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IEuler, IEulerMarkets, IEulerExec, IEulerDToken, IEulerEToken, IEulerEulDistributor, EUL } from "src/interfaces/external/IEuler.sol";
// TODO remove this
import { console } from "@forge-std/Test.sol";

/**
 * @title Euler debtToken Adaptor
 * @notice Allows Cellars to interact with Euler debtToken positions.
 * @author crispymangoes
 */
contract EulerDebtTokenAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(IEulerDToken dToken, uint256 subAccountId)
    // Where:
    // `dToken` is the Euler debt token address position this adaptor is working with
    // `subAccountId` is the sub account id the position uses
    //================= Configuration Data Specification =================
    // NOT USED
    //====================================================================

    /**
     @notice Attempted borrow would lower Cellar health factor too low.
     */
    error EulerDebtTokenAdaptor__HealthFactorTooLow();

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Euler debtToken Adaptor V 0.0"));
    }

    /**
     * @notice The Euler Markets contract on Ethereum Mainnet.
     */
    function markets() internal pure returns (IEulerMarkets) {
        return IEulerMarkets(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);
    }

    function exec() internal pure returns (IEulerExec) {
        return IEulerExec(0x59828FdF7ee634AaaD3f58B19fDBa3b03E2D9d80);
    }

    function euler() internal pure returns (address) {
        return 0x27182842E098f60e3D576794A5bFFb0777E025d3;
    }

    function distributor() internal pure returns (IEulerEulDistributor) {
        return IEulerEulDistributor(0xd524E29E3BAF5BB085403Ca5665301E94387A7e2);
    }

    function eul() internal pure returns (EUL) {
        return EUL(0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b);
    }

    /**
     * @notice Minimum HF enforced after every eToken withdraw/market exiting.
     */
    function HFMIN() internal pure returns (uint256) {
        return 1.01e18;
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice User deposits are NOT allowed into this position.
     */
    function deposit(
        uint256,
        bytes memory,
        bytes memory
    ) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     */
    function withdraw(
        uint256,
        address,
        bytes memory,
        bytes memory
    ) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice This position is a debt position, and user withdraws are not allowed so
     *         this position must return 0 for withdrawableFrom.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the cellars balance of the positions debtToken.
     */
    //  TODO could use the exact version of balance of which has extra decimals.
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        (IEulerDToken dToken, uint256 subAccountId) = abi.decode(adaptorData, (IEulerDToken, uint256));
        return dToken.balanceOf(_getSubAccount(msg.sender, subAccountId));
    }

    /**
     * @notice Returns the positions debtToken underlying asset.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IEulerDToken dToken = abi.decode(adaptorData, (IEulerDToken));
        return ERC20(dToken.underlyingAsset());
    }

    /**
     * @notice This adaptor reports values in terms of debt.
     */
    function isDebt() public pure override returns (bool) {
        return true;
    }

    //============================================ Strategist Functions ===========================================
    /**
     * @notice Strategist attempted to open an untracked Euler loan.
     * @param untrackedDebtPosition the address of the untracked loan
     */
    error EulerDebtTokenAdaptor__DebtPositionsMustBeTracked(address untrackedDebtPosition);

    function borrowFromEuler(
        IEulerDToken debtTokenToBorrow,
        uint256 subAccountId,
        uint256 amountToBorrow
    ) public {
        // Check that debt position is properly set up to be tracked in the Cellar.
        bytes32 positionHash = keccak256(abi.encode(identifier(), true, abi.encode(debtTokenToBorrow, subAccountId)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert EulerDebtTokenAdaptor__DebtPositionsMustBeTracked(address(debtTokenToBorrow));
        debtTokenToBorrow.borrow(subAccountId, amountToBorrow);

        // Check that health factor is above adaptor minimum.
        uint256 healthFactor = _calculateHF(_getSubAccount(address(this), subAccountId));
        if (healthFactor < HFMIN()) revert EulerDebtTokenAdaptor__HealthFactorTooLow();
    }

    function repayEulerDebt(
        IEulerDToken debtTokenToRepay,
        uint256 subAccountId,
        uint256 amountToRepay
    ) public {
        // Think Euler by default allows the type(uint256).max logic
        // amountToRepay = _maxAvailable(tokenToRepay, amountToRepay);
        ERC20(debtTokenToRepay.underlyingAsset()).safeApprove(euler(), amountToRepay);
        debtTokenToRepay.repay(subAccountId, amountToRepay);
    }

    /**
     * @notice Allows strategists to swap assets and repay loans in one call.
     * @dev see `repayEulerDebt`, and BaseAdaptor.sol `swap`
     */
    function swapAndRepay(
        ERC20 tokenIn,
        uint256 subAccountId,
        IEulerDToken debtTokenToRepay,
        uint256 amountIn,
        SwapRouter.Exchange exchange,
        bytes memory params
    ) public {
        uint256 amountToRepay = swap(tokenIn, ERC20(debtTokenToRepay.underlyingAsset()), amountIn, exchange, params);
        repayEulerDebt(debtTokenToRepay, subAccountId, amountToRepay);
    }

    function selfBorrow(
        address target,
        uint256 subAccountId,
        uint256 amount
    ) public {
        // Check that debt position is properly set up to be tracked in the Cellar.
        address debtToken = markets().underlyingToDToken(target);
        bytes32 positionHash = keccak256(abi.encode(identifier(), true, abi.encode(debtToken, subAccountId)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert EulerDebtTokenAdaptor__DebtPositionsMustBeTracked(debtToken);

        IEulerEToken eToken = IEulerEToken(markets().underlyingToEToken(target));
        eToken.mint(subAccountId, amount);

        // Check that health factor is above adaptor minimum.
        uint256 healthFactor = _calculateHF(_getSubAccount(address(this), subAccountId));
        console.log("Health Factor", healthFactor);
        if (healthFactor < HFMIN()) revert EulerDebtTokenAdaptor__HealthFactorTooLow();
    }

    function selfRepay(
        address target,
        uint256 subAccountId,
        uint256 amount
    ) public {
        IEulerEToken eToken = IEulerEToken(markets().underlyingToEToken(target));
        eToken.burn(subAccountId, amount);
        // No need to check HF since burn will raise it.
    }

    function claim(
        address token,
        uint256 claimable,
        bytes32[] calldata proof
    ) public {
        distributor().claim(address(this), token, claimable, proof, address(0));
    }

    function delegate(address delegatee) public {
        eul().delegate(delegatee);
    }

    function _calculateHF(address target) internal view returns (uint256) {
        IEulerExec.AssetLiquidity[] memory assets = exec().detailedLiquidity(target);
        uint256 riskAdjustedCollateral;
        uint256 riskAdjustedLiabilities;

        for (uint256 i; i < assets.length; ++i) {
            IEuler.AssetConfig memory config;
            if (assets[i].status.liabilityValue > 0 || assets[i].status.collateralValue > 0) {
                config = markets().underlyingToAssetConfig(assets[i].underlying);
                if (assets[i].status.liabilityValue > 0) {
                    riskAdjustedLiabilities += assets[i].status.liabilityValue.mulDivDown(config.borrowFactor, 4e9);
                }
                if (assets[i].status.collateralValue > 0) {
                    riskAdjustedCollateral += assets[i].status.collateralValue.mulDivDown(config.collateralFactor, 4e9);
                }
                // 4e9 is the max possible value CF can be, so a CF of 1 would equal 4e9.
                console.log("Collateral Value", assets[i].status.collateralValue);
                console.log("Liability Value", assets[i].status.liabilityValue);
                console.log("Collateral Factor", config.collateralFactor);
                console.log("Borrow Factor", config.borrowFactor);
            }
        }
        // Left here for derivation of actual return value.
        // uint256 avgCollateralFactor = riskAdjustedCollateral / totalCollateral;
        // return totalCollateral.mulDivDown(avgCollateralFactor, totalLiabilites);
        console.log("Risk Adjusted Collateral", riskAdjustedCollateral);
        console.log("Risk Adjusted Liabilities", riskAdjustedLiabilities);
        return riskAdjustedCollateral.mulDivDown(1e18, riskAdjustedLiabilities);
    }

    function _getSubAccount(address primary, uint256 subAccountId) internal pure returns (address) {
        require(subAccountId < 256, "e/sub-account-id-too-big");
        return address(uint160(primary) ^ uint160(subAccountId));
    }
}
