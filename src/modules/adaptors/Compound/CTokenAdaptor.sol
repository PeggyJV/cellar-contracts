// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { ComptrollerG7 as Comptroller, CErc20 } from "src/interfaces/external/ICompound.sol";
// import { CompoundV2HelperLogic } from "src/modules/adaptors/Compound/CompoundV2HelperLogic.sol";
import {CompoundV2HelperLogic} from "src/modules/adaptors/Compound/CompoundV2HelperLogicVersionB.sol";


// TODO to handle ETH based markets, do a similar setup to the curve adaptor where we use the adaptor to act as a middle man to wrap and unwrap eth.
/**
 * @title Compound CToken Adaptor
 * @notice Allows Cellars to interact with CompoundV2 CToken positions AND enter compound markets such that the calling cellar has an active collateral position (enabling the cellar to borrow).
 * @dev As of December 2023, this is the newer version of `CTokenAdaptor.sol` whereas the prior version had no functionality for marking lent assets as supplied Collateral for open borrow positions using the `CompoundV2DebtAdaptor.sol`
 * @author crispymangoes, 0xEinCodes
 */
contract CTokenAdaptor is CompoundV2HelperLogic, BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(CERC20 cToken)
    // Where:
    // `cToken` is the cToken position this adaptor is working with
    //================= Configuration Data Specification =================
    // NOT USED

    /**
     @notice Compound action returned a non zero error code.
     */
    error CTokenAdaptor__NonZeroCompoundErrorCode(uint256 errorCode);

    /**
     * @notice Strategist attempted to interact with a market that is not listed.
     */
    error CTokenAdaptor__MarketNotListed(address market);

    /**
     * @notice Strategist attempted to enter a market but failed
     */
    error CTokenAdaptor__UnsuccessfulEnterMarket(address market);

    /**
     * @notice Attempted tx that results in unhealthy cellar
     */
    error CTokenAdaptor__HealthFactorTooLow(address market);

    /**
     * @notice Attempted tx that results in unhealthy cellar
     */
    error CTokenAdaptor__AlreadyInMarket(address market);

    /**
     * @notice The Compound V2 Comptroller contract on current network.
     * @dev For mainnet use 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B.
     */
    Comptroller public immutable comptroller;

    /**
     * @notice Address of the COMP token.
     * @notice For mainnet use 0xc00e94Cb662C3520282E6f5717214004A7f26888.
     */
    ERC20 public immutable COMP;

    /**
     * @notice Minimum Health Factor enforced after every removeCollateral() strategist function call.
     * @notice Overwrites strategist set minimums if they are lower.
     */
    uint256 public immutable minimumHealthFactor;

    constructor(address v2Comptroller, address comp, uint256 _healthFactor) {
        _verifyConstructorMinimumHealthFactor(_healthFactor);
        comptroller = Comptroller(v2Comptroller);
        COMP = ERC20(comp);
        minimumHealthFactor = _healthFactor;
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("CompoundV2 cToken AdaptorV2 V 0.0"));
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice Cellar must approve market to spend its assets, then call mint to lend its assets.
     * @param assets the amount of assets to lend on Compound
     * @param adaptorData adaptor data containing the abi encoded cToken
     * @dev configurationData is NOT used
     * @dev strategist function `enterMarket()` is used to mark cTokens as collateral provision for cellar. `exitMarket()` removes compound-internal toggle marking and thus marks this position's assets no longer as collateral.
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        // Deposit assets to Compound.
        CErc20 cToken = abi.decode(adaptorData, (CErc20));
        ERC20 token = ERC20(cToken.underlying());
        token.safeApprove(address(cToken), assets);
        uint256 errorCode = cToken.mint(assets);

        // Check for errors.
        if (errorCode != 0) revert CTokenAdaptor__NonZeroCompoundErrorCode(errorCode);

        // Zero out approvals if necessary.
        _revokeExternalApproval(token, address(cToken));
    }

    /**
     @notice Allows users to withdraw from Compound through interacting with the cellar IF cellar is not using this position to "provide collateral"
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from Compound
     * @param receiver the address to send withdrawn assets to
     * @param adaptorData adaptor data containing the abi encoded cToken
     * @dev configurationData is NOT used
     * @dev Conditional logic with`marketJoinCheck` ensures that any withdrawal does not affect health factor.
     */
    function withdraw(uint256 assets, address receiver, bytes memory adaptorData, bytes memory) public override {
        CErc20 cToken = abi.decode(adaptorData, (CErc20));
        // Run external receiver check.
        _externalReceiverCheck(receiver);

        if (_checkMarketsEntered(cToken)) revert CTokenAdaptor__AlreadyInMarket(address(cToken)); // we could allow withdraws but that would add gas and overcomplicates things (HF checks, etc.). It is ideal for a strategist to be strategic on having a market position used as collateral (recall that compoundV2 allows multiple underlying assets to collateralize different assets being borrowed).

        // Withdraw assets from Compound.
        uint256 errorCode = cToken.redeemUnderlying(assets);

        // Check for errors.
        if (errorCode != 0) revert CTokenAdaptor__NonZeroCompoundErrorCode(errorCode);

        // Transfer assets to receiver.
        ERC20(cToken.underlying()).safeTransfer(receiver, assets);

        // TODO: need to figure out how to handle native ETH if that is the underlying asset
    }

    /**
     * @notice Returns balanceOf underlying assets for cToken, regardless of if they are used as supplied collateral or only as lent out assets.
     */
    function withdrawableFrom(bytes memory adaptorData, bytes memory) public view override returns (uint256) {
        CErc20 cToken = abi.decode(adaptorData, (CErc20));
        if (_checkMarketsEntered(cToken)) return 0;
        uint256 cTokenBalance = cToken.balanceOf(msg.sender);
        return cTokenBalance.mulDivDown(cToken.exchangeRateStored(), 1e18);
    }

    /**
     * @notice Returns the cellars balance of the positions cToken underlying.
     * @dev Relies on `exchangeRateStored`, so if the stored exchange rate diverges
     *      from the current exchange rate, an arbitrage opportunity is created for
     *      people to enter the cellar right before the stored value is updated, then
     *      leave immediately after. This is mitigated by the shareLockPeriod,
     *      and because it is rare for the exchange rates to diverge significantly.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        CErc20 cToken = abi.decode(adaptorData, (CErc20));
        uint256 cTokenBalance = cToken.balanceOf(msg.sender);
        return cTokenBalance.mulDivDown(cToken.exchangeRateStored(), 1e18);
    }

    /**
     * @notice Returns the positions cToken underlying asset.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        CErc20 cToken = abi.decode(adaptorData, (CErc20));
        return ERC20(cToken.underlying());
    }

    /**
     * @notice When positions are added to the Registry, this function can be used in order to figure out
     *         what assets this adaptor needs to price, and confirm pricing is properly setup.
     * @dev COMP is used when claiming COMP and swapping.
     */
    function assetsUsed(bytes memory adaptorData) public view override returns (ERC20[] memory assets) {
        assets = new ERC20[](2);
        assets[0] = assetOf(adaptorData);
        assets[1] = COMP;
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================
    /**
     * @notice Allows strategists to lend assets on Compound or add to existing collateral supply for cellar wrt specified market.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param market the market to deposit to.
     * @param amountToDeposit the amount of `tokenToDeposit` to lend on Compound.
     */
    function depositToCompound(CErc20 market, uint256 amountToDeposit) public {

        ERC20 tokenToDeposit = ERC20(market.underlying());
        amountToDeposit = _maxAvailable(tokenToDeposit, amountToDeposit);
        tokenToDeposit.safeApprove(address(market), amountToDeposit);
        uint256 errorCode = market.mint(amountToDeposit);

        // Check for errors.
        if (errorCode != 0) revert CTokenAdaptor__NonZeroCompoundErrorCode(errorCode);

        // Zero out approvals if necessary.
        _revokeExternalApproval(tokenToDeposit, address(market));
    }

    /**
     * @notice Allows strategists to withdraw assets from Compound.
     * @param market the market to withdraw from.
     * @param amountToWithdraw the amount of `market.underlying()` to withdraw from Compound
     * NOTE: `redeem()` is used for redeeming a specified amount of cToken, whereas `redeemUnderlying()` is used for obtaining a specified amount of underlying tokens no matter what amount of cTokens required.
     */
    function withdrawFromCompound(CErc20 market, uint256 amountToWithdraw) public {

        uint256 errorCode;
        if (amountToWithdraw == type(uint256).max) errorCode = market.redeem(market.balanceOf(address(this)));
        else errorCode = market.redeemUnderlying(amountToWithdraw);

        // Check for errors.
        if (errorCode != 0) revert CTokenAdaptor__NonZeroCompoundErrorCode(errorCode);

        // Check new HF from redemption
        if (minimumHealthFactor > (_getHealthFactor(address(this), comptroller))) {
            revert CTokenAdaptor__HealthFactorTooLow(address(this));
        }
    }

    /**
     * @notice Allows strategists to enter the compound market and thus mark its assets as supplied collateral that can support an open borrow position.
     * @param market the market to mark alotted assets as supplied collateral.
     * @dev NOTE: this must be called in order to support for a CToken in order to open a borrow position within that market.
     */
    function enterMarket(CErc20 market) public {
        if (_checkMarketsEntered(market)) revert CTokenAdaptor__AlreadyInMarket(address(market)); // so as to not waste gas

        address[] memory cToken = new address[](1);
        uint256[] memory result = new uint256[](1);
        cToken[0] = address(market);
        result = comptroller.enterMarkets(cToken); // enter the market

        if (result[0] > 0) revert CTokenAdaptor__NonZeroCompoundErrorCode(result[0]);
    }

    /**
     * @notice Allows strategists to exit the compound market and unmark its assets as supplied collateral; thus no longer supporting an open borrow position.
     * @param market the market to unmark alotted assets as supplied collateral.
     * @dev This function is not needed to be called if redeeming cTokens, but it is available if Strategists want to toggle a `CTokenAdaptor` position w/ a specific cToken as "not supporting an open-borrow position" for w/e reason.
     */
    function exitMarket(CErc20 market) public {

        uint256 errorCode = comptroller.exitMarket(address(market)); // exit the market as supplied collateral (still in lending position though)
        if (errorCode != 0) revert CTokenAdaptor__NonZeroCompoundErrorCode(errorCode);

        // TODO - Check new HF from exiting the market
        if (minimumHealthFactor > (_getHealthFactor(address(this), comptroller))) {
            revert CTokenAdaptor__HealthFactorTooLow(address(this));
        }
    }

    /**
     * @notice Allows strategists to claim COMP rewards.
     */
    function claimComp() public {
        comptroller.claimComp(address(this));
    }

    //============================================ Helper Functions ============================================

    /**
     * @notice Helper function that checks if passed market is within list of markets that the cellar is in.
     * @return inCTokenMarket bool that is true if position has entered the market already
     */
    function _checkMarketsEntered(CErc20 cToken) internal view returns (bool inCTokenMarket) {
        // Check cellar has entered the market and thus is illiquid (used for open-borrows possibly)
        CErc20[] memory marketsEntered = comptroller.getAssetsIn(address(this));
        uint256 marketsEnteredLength = marketsEntered.length;
        for (uint256 i = 0; i < marketsEnteredLength; i++) {
            // check if cToken is one of the markets cellar position is in.
            if (marketsEntered[i] == cToken) {
                inCTokenMarket = true;
            }
        }
    }
}
