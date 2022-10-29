// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20, SafeERC20, Math } from "src/base/ERC4626.sol";
import { Registry } from "src/Registry.sol";
import { Cellar } from "src/base/Cellar.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";

/**
 * @title Base Adaptor
 * @notice Base contract all adaptors must inherit from.
 * @dev Allows Cellars to interact with arbritrary DeFi assets and protocols.
 * @author crispymangoes
 */
contract BaseAdaptor {
    using SafeERC20 for ERC20;
    using Math for uint256;

    /**
     * @notice Attempted to specify an external receiver during a Cellar `callOnAdaptor` call.
     */
    error BaseAdaptor__ExternalReceiverBlocked();

    /**
     * @notice Attempted to deposit to a position where user deposits were not allowed.
     */
    error BaseAdaptor__UserDepositsNotAllowed();

    /**
     * @notice Attempted to withdraw from a position where user withdraws were not allowed.
     */
    error BaseAdaptor__UserWithdrawsNotAllowed();

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual returns (bytes32) {
        return keccak256(abi.encode("Base Adaptor V 0.0"));
    }

    function SWAP_ROUTER_REGISTRY_SLOT() internal pure returns (uint256) {
        return 1;
    }

    function PRICE_ROUTER_REGISTRY_SLOT() internal pure returns (uint256) {
        return 2;
    }

    //============================================ Implement Base Functions ===========================================
    //==================== Base Function Specification ====================
    // Base functions are functions designed to help the Cellar interact with
    // an adaptor position, strategists are not intended to use these functions.
    // Base functions MUST be implemented in adaptor contracts, even if that is just
    // adding a revert statement to make them uncallable by normal user operations.
    //
    // All view Base functions will be called used normal staticcall.
    // All mutative Base functions will be called using delegatecall.
    //=====================================================================
    /**
     * @notice Function Cellars call to deposit users funds into holding position.
     * @param assets the amount of assets to deposit
     * @param adaptorData data needed to deposit into a position
     * @param configurationData data settable when strategists add positions to their Cellar
     *                          Allows strategist to control how the adaptor interacts with the position
     */
    function deposit(
        uint256 assets,
        bytes memory adaptorData,
        bytes memory configurationData
    ) public virtual {}

    /**
     * @notice Function Cellars call to withdraw funds from positions to send to users.
     * @param receiver the address that should receive withdrawn funds
     * @param adaptorData data needed to withdraw from a position
     * @param configurationData data settable when strategists add positions to their Cellar
     *                          Allows strategist to control how the adaptor interacts with the position
     */
    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData,
        bytes memory configurationData
    ) public virtual {}

    /**
     * @notice Function Cellars use to determine `assetOf` balance of an adaptor position.
     * @param adaptorData data needed to interact with the position
     * @return balance of the position in terms of `assetOf`
     */
    function balanceOf(bytes memory adaptorData) public view virtual returns (uint256) {}

    /**
     * @notice Functions Cellars use to determine the withdrawable balance from an adaptor position.
     * @dev Debt positions MUST return 0 for their `withdrawableFrom`
     * @notice accepts adaptorData and configurationData
     * @return withdrawable balance of the position in terms of `assetOf`
     */
    function withdrawableFrom(bytes memory, bytes memory) public view virtual returns (uint256) {
        return 0;
    }

    /**
     * @notice Function Cellars use to determine the underlying ERC20 asset of a position.
     * @param adaptorData data needed to withdraw from a position
     * @return the underlying ERC20 asset of a position
     */
    function assetOf(bytes memory adaptorData) public view virtual returns (ERC20) {}
    
    //============================================ Strategist Functions ===========================================
    //==================== Strategist Function Specification ====================
    // Strategist functions are only callable by strategists through the Cellars
    // `callOnAdaptor` function. A cellar will never call any of these functions,
    // when a normal user interacts with a cellar(depositing/withdrawing)
    //
    // All strategist functions will be called using delegatecall.
    // Strategist functions are intentionally "blind" to what positions the cellar
    // is currently holding. This allows strategists to enter temporary positions
    // while rebalancing.
    // To mitigate strategist from abusing this and moving funds in untracked
    // positions, the cellar will enforce a Total Value Locked check that
    // insures TVL has not deviated too much from `callOnAdaptor`.
    //===========================================================================

    //============================================ Helper Functions ===========================================
    /**
     * @notice Helper function that allows adaptor calls to use the max available of an ERC20 asset
     * by passing in type(uint256).max
     * @param token the ERC20 asset to work with
     * @param amount when `type(uint256).max` is used, this function returns `token`s `balanceOf`
     * otherwise this function returns amount.
     */
    function _maxAvailable(ERC20 token, uint256 amount) internal view virtual returns (uint256) {
        if (amount == type(uint256).max) return token.balanceOf(address(this));
        else return amount;
    }

    /**
     * @notice Helper function that allows adaptors to make swaps using the Swap Router
     * @param assetIn the asset to make a swap with
     * @param assetOut the asset to get out of the swap
     * @param amountIn the amount of `assetIn` to swap with
     * @param exchange enum value that determines what exchange to make the swap on
     *                 see SwapRouter.sol
     * @param params swap params needed to perform the swap, dependent on which exchange is selected
     *               see SwapRouter.sol
     * @return amountOut the amount of `assetOut` received from the swap.
     */
    function swap(
        ERC20 assetIn,
        ERC20 assetOut,
        uint256 amountIn,
        SwapRouter.Exchange exchange,
        bytes memory params
    ) public returns (uint256 amountOut) {
        // Store the expected amount of the asset in that we expect to have after the swap.
        uint256 expectedAssetsInAfter = assetIn.balanceOf(address(this)) - amountIn;

        // Get the address of the latest swap router.
        SwapRouter swapRouter = SwapRouter(Cellar(address(this)).registry().getAddress(SWAP_ROUTER_REGISTRY_SLOT()));

        // Approve swap router to swap assets.
        assetIn.safeApprove(address(swapRouter), amountIn);

        // Perform swap.
        amountOut = swapRouter.swap(exchange, params, address(this), assetIn, assetOut);

        // Check that the amount of assets swapped is what is expected. Will revert if the `params`
        // specified a different amount of assets to swap then `amountIn`.
        require(assetIn.balanceOf(address(this)) == expectedAssetsInAfter, "INCORRECT_PARAMS_AMOUNT");
    }

    /**
     * @notice Helper function that validates external receivers are allowed.
     */
    function _externalReceiverCheck(address receiver) internal view {
        if (receiver != address(this) && Cellar(address(this)).blockExternalReceiver())
            revert BaseAdaptor__ExternalReceiverBlocked();
    }
}
