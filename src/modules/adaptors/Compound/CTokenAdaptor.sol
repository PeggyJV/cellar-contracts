// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math, SwapRouter } from "src/modules/adaptors/BaseAdaptor.sol";
import { CErc20 } from "@compound/CErc20.sol";
import { ComptrollerG7 as Comptroller } from "@compound/ComptrollerG7.sol";
import { console } from "@forge-std/Test.sol";

/**
 * @title Compound CToken Adaptor
 * @notice Allows Cellars to interact with Compound CToken positions.
 * @author crispymangoes
 */
contract CTokenAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address cToken)
    // Where:
    // `cToken` is the cToken address position this adaptor is working with
    //================= Configuration Data Specification =================
    // configurationData = abi.encode(minimumHealthFactor uint256)
    // Where:
    // `minimumHealthFactor` dictates how much assets can be taken from this position
    // If zero:
    //      position returns ZERO for `withdrawableFrom`
    // else:
    //      position calculates `withdrawableFrom` based off minimum specified
    //      position reverts if a user withdraw lowers health factor below minimum
    //
    // **************************** IMPORTANT ****************************
    // Cellars with multiple aToken positions MUST only specify minimum
    // health factor on ONE of the positions. Failing to do so will result
    // in user withdraws temporarily being blocked.
    //====================================================================

    /**
     @notice Attempted withdraw would lower Cellar health factor too low.
     */
    // error AaveATokenAdaptor__HealthFactorTooLow();

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Compound cToken Adaptor V 0.0"));
    }

    /**
     * @notice The Compound V2 Comptroller contract on Ethereum Mainnet.
     */
    function comptroller() internal pure returns (Comptroller) {
        return Comptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
    }

    /**
     * @notice The WETH contract on Ethereum Mainnet.
     */
    function COMP() internal pure returns (ERC20) {
        return ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve Pool to spend its assets, then call deposit to lend its assets.
     * @param assets the amount of assets to lend on Compound
     * @param adaptorData adaptor data containining the abi encoded cToken
     * @dev configurationData is NOT used because this action will only increase the health factor
     */
    function deposit(
        uint256 assets,
        bytes memory adaptorData,
        bytes memory
    ) public override {
        // Deposit assets to Aave.
        CErc20 cToken = CErc20(abi.decode(adaptorData, (address)));
        ERC20 token = ERC20(cToken.underlying());
        token.safeApprove(address(cToken), assets);
        cToken.mint(assets);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData,
        bytes memory configData
    ) public override {
        // Run external receiver check.
        _externalReceiverCheck(receiver);

        // Withdraw assets from Aave.
        CErc20 cToken = CErc20(abi.decode(adaptorData, (address)));
        cToken.redeemUnderlying(assets);

        //TODO need to do some health factor check.

        // Transfer assets to receiver.
        ERC20(cToken.underlying()).safeTransfer(receiver, assets);
    }

    function withdrawableFrom(bytes memory adaptorData, bytes memory configData)
        public
        view
        override
        returns (uint256)
    {
        CErc20 cToken = CErc20(abi.decode(adaptorData, (address)));
        uint256 cTokenBalance = cToken.balanceOf(msg.sender);
        return cTokenBalance.mulDivDown(cToken.exchangeRateStored(), 1e18);
        //TODO need to do some health factor check.
    }

    /**
     * @notice Returns the cellars balance of the positions cToken underlying.
     * @dev Relies on `exchangeRateStored`, so if the stored exchange rate diverges
     *      from the current exchange rate, an arbitrage oppurtunity is created for
     *      people to enter the cellar right before the stored value is updated, then
     *      leave immediately after
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        CErc20 cToken = CErc20(abi.decode(adaptorData, (address)));
        uint256 cTokenBalance = cToken.balanceOf(msg.sender);
        return cTokenBalance.mulDivDown(cToken.exchangeRateStored(), 1e18);
    }

    /**
     * @notice Returns the positions cToken underlying asset.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        CErc20 cToken = CErc20(abi.decode(adaptorData, (address)));
        return ERC20(cToken.underlying());
    }

    //============================================ Strategist Functions ===========================================
    /**
     * @notice Allows strategists to lend assets on Compound.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param market the market to deposit to.
     * @param amountToDeposit the amount of `tokenToDeposit` to lend on Compound.
     */
    function depositToCompound(CErc20 market, uint256 amountToDeposit) public {
        ERC20 tokenToDeposit = ERC20(market.underlying());
        amountToDeposit = _maxAvailable(tokenToDeposit, amountToDeposit);
        tokenToDeposit.safeApprove(address(comptroller()), amountToDeposit);
        market.mint(amountToDeposit);
    }

    /**
     * @notice Allows strategists to withdraw assets from Compound.
     * @param market the market to withdraw from.
     * @param amountToWithdraw the amount of `market.underlying()` to withdraw from Compound
     */
    function withdrawFromCompound(CErc20 market, uint256 amountToWithdraw) public {
        market.redeemUnderlying(amountToWithdraw);
    }

    /**
     * @notice Allows strategists to claim COMP rewards.
     */
    function claimComp() public {
        comptroller().claimComp(address(this));
        console.log("Comp claimed", COMP().balanceOf(address(this)));
    }

    function claimCompAndSwap(
        ERC20 assetOut,
        SwapRouter.Exchange exchange,
        bytes memory params
    ) public {
        uint256 balance = COMP().balanceOf(address(this));
        claimComp();
        balance = COMP().balanceOf(address(this)) - balance;
        swap(COMP(), assetOut, balance, exchange, params);
    }
}
