// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib } from "src/modules/adaptors/BaseAdaptor.sol";
import { IMorphoV3 } from "src/interfaces/external/Morpho/IMorphoV3.sol";
import { MorphoRewardHandler } from "src/modules/adaptors/Morpho/MorphoRewardHandler.sol";

/**
 * @title Morpho Aave V3 aToken Adaptor
 * @notice Allows Cellars to interact with Morpho Aave V3 positions.
 * @author crispymangoes
 */
contract MorphoAaveV3ATokenP2PAdaptor is BaseAdaptor, MorphoRewardHandler {
    using SafeTransferLib for ERC20;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address underlying)
    // Where:
    // `underlying` is the ERC20 position this adaptor is working with
    //================= Configuration Data Specification =================
    // configurationData = abi.encode(uint256 maxIterations);
    // Where:
    // `maxIterations` is some number greater than 0 but less than MAX_ITERATIONS,
    // allows assets to be P2P matched.
    //====================================================================

    uint256 internal constant MAX_ITERATIONS = 10;
    uint256 internal constant OPTIMAL_ITERATIONS = 4;

    /**
     * @notice The Morpho Aave V3 contract on current network.
     * @notice For mainnet use 0x33333aea097c193e66081E930c33020272b33333.
     */
    IMorphoV3 public immutable morpho;

    constructor(address _morpho, address rewardDistributor) MorphoRewardHandler(rewardDistributor) {
        morpho = IMorphoV3(_morpho);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Morpho Aave V3 aToken P2P Adaptor V 1.2"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve Morpho to spend its assets, then call supply to lend its assets.
     * @param assets the amount of assets to lend on Morpho
     * @param adaptorData adaptor data containining the abi encoded aToken
     * @param configurationData abi encoded maxIterations
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory configurationData) public override {
        // Deposit assets to Morpho.
        ERC20 underlying = abi.decode(adaptorData, (ERC20));
        underlying.safeApprove(address(morpho), assets);

        uint256 iterations = abi.decode(configurationData, (uint256));
        if (iterations == 0 || iterations > MAX_ITERATIONS) iterations = OPTIMAL_ITERATIONS;
        morpho.supply(address(underlying), assets, address(this), iterations);

        // Zero out approvals if necessary.
        _revokeExternalApproval(underlying, address(morpho));
    }

    /**
     @notice Allows cellars to withdraw Morpho.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from Morpho
     * @param receiver the address to send withdrawn assets to
     * @param adaptorData adaptor data containining the abi encoded ERC20 token
     * @param configurationData abi encoded maximum iterations.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData,
        bytes memory configurationData
    ) public override {
        // Run external receiver check.
        _externalReceiverCheck(receiver);

        address underlying = abi.decode(adaptorData, (address));
        uint256 iterations = abi.decode(configurationData, (uint256));

        // Withdraw assets from Morpho.
        morpho.withdraw(underlying, assets, address(this), receiver, iterations);
    }

    /**
     * @notice Returns the p2p balance of the cellar.
     */
    function withdrawableFrom(bytes memory adaptorData, bytes memory) public view override returns (uint256) {
        address underlying = abi.decode(adaptorData, (address));
        return morpho.supplyBalance(underlying, msg.sender);
    }

    /**
     * @notice Returns the cellars p2p balance.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        address underlying = abi.decode(adaptorData, (address));
        return morpho.supplyBalance(underlying, msg.sender);
    }

    /**
     * @notice Returns the positions underlying asset.
     */
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        ERC20 underlying = abi.decode(adaptorData, (ERC20));
        return underlying;
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================
    /**
     * @notice Allows strategists to lend assets on Morpho.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param tokenToDeposit the token to lend on Morpho
     * @param amountToDeposit the amount of `tokenToDeposit` to lend on Morpho.
     * @param maxIterations maximum number of iterations for Morphos p2p matching engine
     */
    function depositToAaveV3Morpho(ERC20 tokenToDeposit, uint256 amountToDeposit, uint256 maxIterations) public {
        // Sanitize maxIterations to prevent strategists from gas griefing Somm relayer.
        if (maxIterations == 0 || maxIterations > MAX_ITERATIONS) maxIterations = OPTIMAL_ITERATIONS;

        amountToDeposit = _maxAvailable(tokenToDeposit, amountToDeposit);
        tokenToDeposit.safeApprove(address(morpho), amountToDeposit);
        morpho.supply(address(tokenToDeposit), amountToDeposit, address(this), maxIterations);

        // Zero out approvals if necessary.
        _revokeExternalApproval(tokenToDeposit, address(morpho));
    }

    /**
     * @notice Allows strategists to withdraw assets from Morpho.
     * @param tokenToWithdraw the token to withdraw from Morpho.
     * @param amountToWithdraw the amount of `tokenToWithdraw` to withdraw from Morpho
     * @param maxIterations maximum number of iterations for Morphos p2p matching engine
     */
    function withdrawFromAaveV3Morpho(ERC20 tokenToWithdraw, uint256 amountToWithdraw, uint256 maxIterations) public {
        /// Sanitize maxIterations to prevent strategists from gas griefing Somm relayer.
        if (maxIterations == 0 || maxIterations > MAX_ITERATIONS) maxIterations = OPTIMAL_ITERATIONS;
        morpho.withdraw(address(tokenToWithdraw), amountToWithdraw, address(this), address(this), maxIterations);
    }
}
