// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StakingAdaptor, IWETH9 } from "./StakingAdaptor.sol";
import { ILiquidityPool, IWithdrawRequestNft, IWEETH } from "src/interfaces/external/IStaking.sol";

/**
 * @title EtherFi Staking Adaptor
 * @notice Allows Cellars to stake with EtherFi.
 * @dev EtherFi supports minting, burning, and wrapping.
 * @author crispymangoes
 */
contract EtherFiStakingAdaptor is StakingAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Address for address;

    /**
     * @notice The EtherFi liquidity pool staking calls are made to.
     */
    ILiquidityPool public immutable liquidityPool;

    /**
     * @notice The EtherFi withdraw request NFT withdraw requests are made to.
     */
    IWithdrawRequestNft public immutable withdrawRequestNft;

    /**
     * @notice The wrapper contract for eETH.
     */
    IWEETH public immutable weETH;

    /**
     * @notice The eETH contract.
     */
    ERC20 public immutable eETH;

    constructor(
        address _wrappedNative,
        uint8 _maxRequests,
        address _liquidityPool,
        address _withdrawRequestNft,
        address _weETH,
        address _eETH
    ) StakingAdaptor(_wrappedNative, _maxRequests) {
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
        return keccak256(abi.encode("EtherFi Staking Adaptor V 0.0"));
    }

    //============================================ Override Functions ===========================================

    /**
     * @notice Stakes into EtherFi using native asset.
     */
    function _mint(uint256 amount, bytes calldata) internal override returns (uint256 amountMinted) {
        amountMinted = eETH.balanceOf(address(this));
        liquidityPool.deposit{ value: amount }();
        amountMinted = eETH.balanceOf(address(this)) - amountMinted;
    }

    /**
     * @notice Wraps derivative asset.
     */
    function _wrap(uint256 amount, bytes calldata) internal override returns (uint256 amountOut) {
        amount = _maxAvailable(eETH, amount);
        eETH.safeApprove(address(weETH), amount);
        amountOut = weETH.wrap(amount);
        _revokeExternalApproval(eETH, address(weETH));
    }

    /**
     * @notice Unwraps derivative asset.
     */
    function _unwrap(uint256 amount, bytes calldata) internal override returns (uint256 amountOut) {
        amount = _maxAvailable(ERC20(address(weETH)), amount);
        amountOut = weETH.unwrap(amount);
    }

    /**
     * @notice Returns balance in pending and finalized withdraw requests.
     * @dev Formula for request value is on line 77 in WithdrawRequestNFT.sol
     *      here https://etherscan.io/address/0xdaaac9488f9934956b55fcdaef6f9d92f8008ca7#code
     */
    function _balanceOf(address account) internal view override returns (uint256 amount) {
        uint256[] memory requests = StakingAdaptor(adaptorAddress).getRequestIds(account);
        uint256 requestsLength = requests.length;
        for (uint256 i; i < requestsLength; ++i) {
            IWithdrawRequestNft.WithdrawRequest memory request = withdrawRequestNft.getRequest(requests[i]);
            // Only check for value if request is valid.
            if (request.isValid) {
                // Take min between valuation at request creation, and current valuation.
                uint256 amountForShares = liquidityPool.amountForShare(request.shareOfEEth);
                uint256 requestValueInPrimitive = (request.amountOfEEth < amountForShares)
                    ? request.amountOfEEth
                    : amountForShares;

                // Remove fee
                uint256 fee = uint256(request.feeGwei) * 1 gwei;
                requestValueInPrimitive = requestValueInPrimitive - fee;
                amount += requestValueInPrimitive;
            }
        }
    }

    /**
     * @notice Request a withdrawal from EtherFi.
     */
    function _requestBurn(uint256 amount, bytes calldata) internal override returns (uint256 id) {
        amount = _maxAvailable(eETH, amount);
        eETH.safeApprove(address(liquidityPool), amount);
        id = liquidityPool.requestWithdraw(address(this), amount);
        _revokeExternalApproval(eETH, address(liquidityPool));
    }

    /**
     * @notice Complete a withdrawal from EtherFi.
     */
    function _completeBurn(uint256 id, bytes calldata) internal override {
        withdrawRequestNft.claimWithdraw(id);
    }

    /**
     * @notice Remove a request from requestIds if it is already claimed.
     */
    function removeClaimedRequest(uint256 id, bytes calldata) external override {
        IWithdrawRequestNft.WithdrawRequest memory request = withdrawRequestNft.getRequest(id);
        if (!request.isValid) StakingAdaptor(adaptorAddress).removeRequestId(id);
        else revert StakingAdaptor__RequestNotClaimed(id);
    }
}
