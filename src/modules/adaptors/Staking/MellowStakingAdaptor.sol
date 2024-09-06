import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StakingAdaptor, IWETH9 } from "./StakingAdaptor.sol";
import { IVault } from "src/interfaces/external/IStaking.sol";
/**
 * @title Mellow Staking Adaptor
 * @notice Allows Cellars to stake with Mellow.
 * @dev Mellow supports deposits, withdrawls.
 * @author zmanian
 */

 contract MellowStakingAdaptor is StakingAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Address for address;

    /**
     * @notice The Mellow LRT vault for this adapter instance.
     */
    IVault public immutable mellowVault;


    /**
     * @notice The eMellow contract.
     */
    ERC20 public immutable vaultToken;

    constructor(
        address _baseAsset,
        uint8 _maxRequests,
        address _mellowVault,
        address _vaultToken,
    ) StakingAdaptor(_baseAsset, _maxRequests) {
        mellowVault = IVault(_mellowVault);
        vaultToken = ERC20(_vaultToken);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() external view override returns (bytes32) {
        return keccak256(abi.encodePacked("MellowStakingAdaptor", vaultToken.name(), address(this)));
    }

    /**
     * @dev Deposit funds into the Mellow staking contract.
     * @param _amount The amount of funds to deposit.
     */
    function deposit(uint256 _amount) internal returns (uint256[] memory actualAmounts, uint256 lpAmount) {
        vaultToken.safeTransferFrom(msg.sender, address(this), _amount);
        vaultToken.safeApprove(address(mellowStaking), _amount);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _amount;
        mellowStaking.deposit(this, amounts, 0,type(uint256).max,0);
    }

    /**
     * @dev Withdraw funds from the Mellow staking contract.
     * @param _amount The amount of funds to withdraw.
     */
    function registerWithdrawl(uint256 _amount) internal {
        uint256[] memory min_amounts = new uint256[](1);
        min_amounts[0] = 0;
        mellowStaking.registerWithdrawal(this,_amount, amounts, type(uint256).max, type(uint256).max, false);
    }

    function cancelWithdrawalRequest() internal {
        mellowStaking.cancelWithdrawal();
    }
 }
