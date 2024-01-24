// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StakingAdaptor, IWETH9 } from "./StakingAdaptor.sol";

interface ILiquidityPool {
    function deposit() external payable;

    function requestWithdraw(address recipient, uint256 amount) external returns (uint256);

    function amountForShare(uint256 shares) external view returns (uint256);
}

interface IWithdrawRequestNft {
    struct WithdrawRequest {
        uint96 amountOfEEth;
        uint96 shareOfEEth;
        bool isValid;
        uint32 feeGwei;
    }

    function claimWithdraw(uint256 tokenId) external;

    function getRequest(uint256 requestId) external view returns (WithdrawRequest memory);

    function finalizeRequests(uint256 requestId) external;

    function owner() external view returns (address);

    function updateAdmin(address admin, bool isAdmin) external;
}

interface IWEETH {
    function wrap(uint256 amount) external;

    function unwrap(uint256 amount) external;
}

/**
 * @title 0x Adaptor
 * @notice Allows Cellars to swap with 0x.
 * @author crispymangoes
 */
contract EtherFiStakingAdaptor is StakingAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Address for address;

    //==================== Adaptor Data Specification ====================
    // NOT USED
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // This adaptor has NO underlying position, its only purpose is to
    // expose the swap function to strategists during rebalances.
    //====================================================================

    ILiquidityPool public immutable liquidityPool;
    IWithdrawRequestNft public immutable withdrawRequestNft;
    IWEETH public immutable weETH;
    ERC20 public immutable eETH;

    constructor(
        address _wrappedNative,
        address _liquidityPool,
        address _withdrawRequestNft,
        address _weETH,
        address _eETH
    ) StakingAdaptor(_wrappedNative, 8) {
        liquidityPool = ILiquidityPool(_liquidityPool);
        withdrawRequestNft = IWithdrawRequestNft(_withdrawRequestNft);
        weETH = IWEETH(_weETH);
        eETH = ERC20(_eETH);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("0x Adaptor V 1.1"));
    }

    //============================================ Override Functions ===========================================
    function _mint(uint256 amount) internal override {
        liquidityPool.deposit{ value: amount }();
    }

    function _wrap(uint256 amount) internal override {
        amount = _maxAvailable(eETH, amount);
        eETH.safeApprove(address(weETH), amount);
        weETH.wrap(amount);
        _revokeExternalApproval(eETH, address(weETH));
    }

    function _unwrap(uint256 amount) internal override {
        amount = _maxAvailable(ERC20(address(weETH)), amount);
        weETH.unwrap(amount);
    }

    // Formula for request value is on line 77 in WithdrawRequestNFT.sol here https://etherscan.io/address/0xdaaac9488f9934956b55fcdaef6f9d92f8008ca7#code
    function _balanceOf(address account) internal view override returns (uint256 amount) {
        uint256[] memory requests = StakingAdaptor(adaptorAddress).getRequestIds(account);
        for (uint256 i; i < requests.length; ++i) {
            IWithdrawRequestNft.WithdrawRequest memory request = withdrawRequestNft.getRequest(requests[i]);
            // Take min between valuation at request creation, and current valuation.
            uint256 amountForShares = liquidityPool.amountForShare(request.shareOfEEth);
            uint256 requestValueInPrimitive = (request.amountOfEEth < amountForShares)
                ? request.amountOfEEth
                : amountForShares;

            // Remove fee
            uint256 fee = request.feeGwei * 1 gwei;
            requestValueInPrimitive = requestValueInPrimitive - fee;
            amount += requestValueInPrimitive;
        }
    }

    function _requestBurn(uint256 amount) internal override returns (uint256 id) {
        amount = _maxAvailable(eETH, amount);
        eETH.safeApprove(address(liquidityPool), amount);
        id = liquidityPool.requestWithdraw(address(this), amount);
        _revokeExternalApproval(eETH, address(liquidityPool));
    }

    function _completeBurn(uint256 id) internal override {
        withdrawRequestNft.claimWithdraw(id);
    }
}
