pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeERC20, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


interface ILekkerFinance is IERC20 {
    function addToPosition(uint256 _collateralAmountToAdd) external;
    function removeFromPosition(uint256 _tokensToBurn) external;
    function tokenCollateral() external view returns (address);
    function tokenBorrow() external view returns (address);
}

contract LekkerFinanceAdaptor is BaseAdaptor {
    using SafeERC20 for ERC20;
    using Math for uint256;
    using SafeCast for uint256;
    using Address for address;
    
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Lekker Finance Adaptor V 0.0"));
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
     * @notice User withdraws are not allowed so this position must return 0 for withdrawableFrom.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    //calculates LP positions user has.
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {

    }

    //============================================ Strategist Functions ===========================================
    /**
     * @notice Allows strategist to open up Lekker Finance positions.
     * @param leverageToken the leverage token users want to open position in.
     * @param amount the amount of tokens users want to invest
     */
    function openPosition(
        ILekkerFinance leverageToken,
        uint256 amount
    ) public {
        //approve manager to spend specified amount of funds
        ERC20(leverageToken.tokenCollateral()).safeApprove(address(leverageToken), amount);
        // Create mint params.
        leverageToken.addToPosition(amount);
    }

    /**
     * @notice Strategist attempted to interact with a Lekker Finance position the cellar does not own.
     * @param positionId the id of the position the cellar does not own
     */
    error UniswapV3Adaptor__NotTheOwner(uint256 positionId);

    /**
     * @notice Allows strategist to close Uniswap V3 positions.
     * @dev transfers NFT to DEAD address to save on gas while looping in `balanceOf`.
     */
    function closePosition(
        ILekkerFinance leverageToken,
        uint256 amount
    ) public {
        //approve because of the token burn
        // leverageToken.safeApprove(address(leverageToken), amount);
        //the adapter receives collateral token when removing position
        leverageToken.removeFromPosition(amount);
    }
}