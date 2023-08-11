// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IFToken } from "src/interfaces/external/Frax/IFToken.sol";
import { FraxlendHealthFactorLogic } from "src/modules/adaptors/Frax/FraxlendHealthFactorLogic.sol";

/**
 * @title FraxLend Collateral Adaptor
 * @notice Allows addition and removal of collateralAssets to Fraxlend pairs for a Cellar.
 * @author crispymangoes, 0xEinCodes
 */
contract CollateralFTokenAdaptorV2 is BaseAdaptor, FraxlendHealthFactorLogic {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(IFToken fraxlendPair)
    // Where:
    // `fraxlendPair` is the fraxlend pair this adaptor position is working with. It is also synomous to fToken used in `FTokenAdaptor.sol` and `FTokenAdaptorV1.sol`
    //================= Configuration Data Specification =================
    // N/A because the DebtFTokenAdaptor handles actual deposits and withdrawals.
    // ==================================================================

    /**
     * @notice Attempted to interact with an fraxlendPair the Cellar is not using.
     */
    error CollateralFTokenAdaptor__FraxlendPairPositionsMustBeTracked(address fraxlendPair);

    /**
     * @notice Removal of collateral causes Cellar Health Factor below what is required
     */
    error CollateralFTokenAdaptor__HealthFactorTooLow(address fraxlendPair);

    /**
     * @notice The FRAX contract on current network.
     * @notice For mainnet use 0x853d955aCEf822Db058eb8505911ED77F175b99e.
     */
    ERC20 public immutable FRAX;

    /**
     * @notice Minimum Health Factor enforced after every removeCollateral() strategist function call.
     * @notice Overwrites strategist set minimums if they are lower.
     */
    uint256 public immutable minimumHealthFactor;

    constructor(address _frax, uint256 _healthFactor) {
        _verifyConstructorMinimumHealthFactor(_healthFactor);
        FRAX = ERC20(_frax);
        minimumHealthFactor = _healthFactor;
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("FraxLend Collateral fToken Adaptor V 0.1"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice User deposits collateralToken to Fraxlend pair
     * @param assets the amount of assets to provide as collateral on FraxLend
     * @param adaptorData adaptor data containing the abi encoded fraxlendPair
     * @dev configurationData is NOT used
     */
    function deposit(
        uint256 assets,
        bytes memory adaptorData,
        bytes memory
    ) public override {
        // use addCollateral() from fraxlendCore.sol
        IFToken fraxlendPair = abi.decode(adaptorData, (IFToken));
        ERC20 collateralToken = ERC20(fraxlendPair.collateralContract());

        _validateFToken(fraxlendPair);
        address fraxlendPairAddress = address(fraxlendPair);
        collateralToken.safeApprove(fraxlendPairAddress, assets);
        fraxlendPair.addCollateral(assets, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(collateralToken, fraxlendPairAddress);
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     * NOTE: collateral withdrawal calls directly from users disallowed for now.
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
     * NOTE: collateral withdrawal calls directly from users disallowed for now.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the cellar's balance of the collateralAsset position.
     * @param adaptorData the collateral asset deposited into Fraxlend
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        IFToken fraxlendPair = abi.decode(adaptorData, (IFToken));
        return fraxlendPair.userCollateralBalance(msg.sender);
    }

    /**
     * @notice Returns collateral asset
     */
    function assetOf(bytes memory _adaptorData) public view override returns (ERC20) {
        IFToken fraxlendPair = abi.decode(_adaptorData, (IFToken));
        return ERC20(fraxlendPair.collateralContract());
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to add collateral to the respective cellar position on FraxLend, enabling borrowing.
     */
    function addCollateral(IFToken _fraxlendPair, uint256 _collateralToDeposit) public {
        ERC20 _collateralToken = ERC20(_fraxlendPair.collateralContract());
        _validateFToken(_fraxlendPair);

        uint256 amountToDeposit = _maxAvailable(_collateralToken, _collateralToDeposit);
        address fraxlendPair = address(_fraxlendPair);
        _collateralToken.safeApprove(fraxlendPair, amountToDeposit);
        _addCollateral(_fraxlendPair, amountToDeposit);

        // Zero out approvals if necessary.
        _revokeExternalApproval(_collateralToken, fraxlendPair);
    }

    function _addCollateral(IFToken _fraxlendPair, uint256 amountToDeposit) internal {
        _fraxlendPair.addCollateral(amountToDeposit, address(this));
    }

    /**
     * @notice Allows strategists to remove collateral from the respective cellar position on FraxLend.
     */
    function removeCollateral(uint256 _collateralAmount, IFToken _fraxlendPair) public {
        // TODO: I don't think that Fraxlend pairs check whether or not cellar even has a position to start with. So we need to add a check/revert to disallow Strategists from calling this when they have zero collateral in fraxlend pair position. Otherwise, it just reverts I assume, could protect strategist from wasting gas.

        // remove collateral
        _fraxlendPair.removeCollateral(_collateralAmount, address(this));
        (, uint256 _exchangeRate, ) = _fraxlendPair.updateExchangeRate(); // need to calculate LTV
        // Check if borrower is insolvent (AKA they have bad LTV), revert if they are
        if (minimumHealthFactor > (_isSolvent(_fraxlendPair, _exchangeRate))) {
            revert CollateralFTokenAdaptor__HealthFactorTooLow(address(_fraxlendPair));
        }
    }

    //============================================ Interface Helper Functions ===========================================

    //============================== Interface Details ==============================
    // The Frax Pair interface can slightly change between versions.
    // To account for this, FTokenAdaptors (including debt and collateral adaptors) will use the below internal functions when
    // interacting with Frax Pairs, this way new pairs can be added by creating a
    // new contract that inherits from this one, and overrides any function it needs
    // so it conforms with the new Frax Pair interface.

    // Current versions in use for `FraxLendPair` include v1 and v2.

    // IMPORTANT: TODO: This `CollateralFTokenAdaptorV2.sol` is associated to the v2 version of `FraxLendPair`
    // whereas CollateralFTokenAdaptorV1 is actually associated to `FraxLendPairv1`.
    // The reasoning to name it like this was to set up the base CollateralFTokenAdaptorV2 for the
    // most current version, v2. This is in anticipation that more FraxLendPairs will
    // be deployed following v2 in the near future. When later versions are deployed,
    // then the described inheritance pattern above will be used.
    //===============================================================================

    /**
     * @notice Validates that a given fToken is set up as a position in the Cellar.
     * @dev This function uses `address(this)` as the address of the Cellar.
     */
    function _validateFToken(IFToken _fraxlendPair) internal view virtual {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(address(_fraxlendPair))));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert CollateralFTokenAdaptor__FraxlendPairPositionsMustBeTracked(address(_fraxlendPair));
    }
}
