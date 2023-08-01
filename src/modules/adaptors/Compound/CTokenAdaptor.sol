// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { ComptrollerG7 as Comptroller, CErc20 } from "src/interfaces/external/ICompound.sol";

/**
 * @title Compound CToken Adaptor
 * @notice Allows Cellars to interact with Compound CToken positions.
 * @author crispymangoes
 */
contract CTokenAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(CERC20 cToken)
    // Where:
    // `cToken` is the cToken position this adaptor is working with
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // There is no way for a Cellar to take out loans on Compound, so there
    // are NO health factor checks done for `withdraw` or `withdrawableFrom`
    // In the future if a Compound debt adaptor is created, then this adaptor
    // must be changed to include some health factor checks like the
    // Aave aToken adaptor.
    //====================================================================

    /**
     @notice Compound action returned a non zero error code.
     */
    error CTokenAdaptor__NonZeroCompoundErrorCode(uint256 errorCode);

    /**
     * @notice Strategist attempted to interact with a market that is not listed.
     */
    error CTokenAdaptor__MarketNotListed(address market);

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

    constructor(address v2Comptroller, address comp) {
        comptroller = Comptroller(v2Comptroller);
        COMP = ERC20(comp);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Compound cToken Adaptor V 1.1"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve market to spend its assets, then call mint to lend its assets.
     * @param assets the amount of assets to lend on Compound
     * @param adaptorData adaptor data containing the abi encoded cToken
     * @dev configurationData is NOT used
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        // Deposit assets to Compound.
        CErc20 cToken = abi.decode(adaptorData, (CErc20));
        _validateMarketInput(address(cToken));
        ERC20 token = ERC20(cToken.underlying());
        token.safeApprove(address(cToken), assets);
        uint256 errorCode = cToken.mint(assets);

        // Check for errors.
        if (errorCode != 0) revert CTokenAdaptor__NonZeroCompoundErrorCode(errorCode);

        // Zero out approvals if necessary.
        _revokeExternalApproval(token, address(cToken));
    }

    /**
     @notice Cellars must withdraw from Compound.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from Compound
     * @param receiver the address to send withdrawn assets to
     * @param adaptorData adaptor data containing the abi encoded cToken
     * @dev configurationData is NOT used
     * @dev There are NO health factor checks done in `withdraw`, or `withdrawableFrom`.
     *      If cellars ever take on Compound Debt it is crucial these checks are added,
     *      see "IMPORTANT" above.
     */
    function withdraw(uint256 assets, address receiver, bytes memory adaptorData, bytes memory) public override {
        // Run external receiver check.
        _externalReceiverCheck(receiver);

        // Withdraw assets from Compound.
        CErc20 cToken = abi.decode(adaptorData, (CErc20));
        _validateMarketInput(address(cToken));
        uint256 errorCode = cToken.redeemUnderlying(assets);

        // Check for errors.
        if (errorCode != 0) revert CTokenAdaptor__NonZeroCompoundErrorCode(errorCode);

        // Transfer assets to receiver.
        ERC20(cToken.underlying()).safeTransfer(receiver, assets);
    }

    /**
     * @notice Identical to `balanceOf`.
     * @dev There are NO health factor checks done in `withdraw`, or `withdrawableFrom`.
     *      If cellars ever take on Compound Debt it is crucial these checks are added,
     *      see "IMPORTANT" above.
     */
    function withdrawableFrom(bytes memory adaptorData, bytes memory) public view override returns (uint256) {
        CErc20 cToken = abi.decode(adaptorData, (CErc20));
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
     * @notice Allows strategists to lend assets on Compound.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param market the market to deposit to.
     * @param amountToDeposit the amount of `tokenToDeposit` to lend on Compound.
     */
    function depositToCompound(CErc20 market, uint256 amountToDeposit) public {
        _validateMarketInput(address(market));

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
     */
    function withdrawFromCompound(CErc20 market, uint256 amountToWithdraw) public {
        _validateMarketInput(address(market));

        uint256 errorCode;
        if (amountToWithdraw == type(uint256).max) errorCode = market.redeem(market.balanceOf(address(this)));
        else errorCode = market.redeemUnderlying(amountToWithdraw);

        // Check for errors.
        if (errorCode != 0) revert CTokenAdaptor__NonZeroCompoundErrorCode(errorCode);
    }

    /**
     * @notice Allows strategists to claim COMP rewards.
     */
    function claimComp() public {
        comptroller.claimComp(address(this));
    }

    //============================================ Helper Functions ============================================

    /**
     * @notice Helper function that reverts if market is not listed in Comptroller.
     */
    function _validateMarketInput(address input) internal view {
        (bool isListed, , ) = comptroller.markets(input);

        if (!isListed) revert CTokenAdaptor__MarketNotListed(input);
    }
}
