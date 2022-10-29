// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeERC20, Cellar, PriceRouter } from "src/modules/adaptors/BaseAdaptor.sol";
import { CTokenInterface } from "src/interfaces/external/CTokenInterfaces.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

abstract contract CToken is IERC20Upgradeable {
    function supplyRatePerBlock() external view virtual returns (uint256);

    function mint(uint256 mintAmount) external virtual returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external virtual returns (uint256);

    function balanceOfUnderlying(address owner) external virtual returns (uint256);

    function exchangeRateStored() external view virtual returns (uint256);
}

/**
 * @title Compound cToken Adaptor
 * @notice Allows Cellars to interact with Aave aToken positions.
 * @author mnm458 & mrhouzlane
 */

contract CompoundTokenAdapter is BaseAdaptor {
    using SafeERC20 for ERC20;

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
    // Cellars with multiple cToken positions MUST only specify minimum
    // health factor on ONE of the positions. Failing to do so will result
    // in user withdraws temporarily being blocked.
    //====================================================================

    /**
     @notice Attempted withdraw would lower Cellar health factor too low.
     */
    error CompooundTokenAdaptor__HealthFactorTooLow();

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
     * @notice
     */
    function isCETH(address target) internal view returns (bool) {
        return keccak256(abi.encodePacked(IERC20Metadata(target).symbol())) == keccak256(abi.encodePacked("cETH"));
    }

    /**
     * @notice The WETH contract on Ethereum Mainnet.
     */
    function WETH() internal pure returns (ERC20) {
        return ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve Pool to spend its assets, then call deposit to lend its assets.
     * @param assets the amount of assets to lend on Aave
     * @param adaptorData adaptor data containining the abi encoded cToken
     * @dev configurationData is NOT used because this action will only increase the health factor
     */

    function deposit(
        uint256 assets,
        bytes memory adaptorData,
        address receiver,
        bytes memory
    ) public override {
        // Deposit to Compound Market

        IERC20Metadata _underlying = IERC20Metadata(underlying());
        IERC20Metadata cToken = IERC20Metadata(abi.decode(adaptorData, (address)));

        _underlying.safeTransferFrom(msg.sender, address(this), assets); // pulls the underlying

        // --- WETH into ETH
        bool _isCETH = isCETH(address(cToken));
        if (_isCETH) {
            IWETH(WETH).withdraw(assets);
        }

        // mint cToken
        uint256 before = cToken.balanceOf(address(this));
        if (_isCETH) {
            CEther(cToken).mint{ value: assets }();
        } else {
            require(CTokenInterface(cToken).mint(assets) == 0, "Error");
        }
        uint256 final = cToken.balanceOf(address(this)) - before ;
        cToken.safeTransfer(msg.sender, final);
        return final;
    }

    function unWrapUnderlying(
        uint256 assets,
        bytes memory adaptorData,
        bytes memory
    ) public override {
        //Withdraw from Compound market

        IERC20Metadata u = IERC20Metadata(underlying());
        IERC20Metadata target = IERC20Metadata(adapterParams.target);
        bool isCETH = _isCETH(address(target));
    }
}
