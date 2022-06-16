// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
//import { ISwapRouter } from "./interfaces/ISwapRouter.sol";
import { IAggregationRouterV4 as AggregationRouterV4 } from "./interfaces/IAggregationRouterV4.sol";

contract SwapRouter {
    using SafeTransferLib for ERC20;

    enum Exchanges {
        ONEINCH
    }

    mapping(Exchanges => bytes4) public idToSelector;

    // ========================================== CONSTRUCTOR ==========================================
    /**
     * @notice 1Inch Dex Aggregation Router
     */
    AggregationRouterV4 public immutable aggRouterV4; // 0x1111111254fb6c44bAC0beD2854e76F90643097d

    /**
     * @param _aggRouterV4 1 Inch Router Address
     */
    constructor(AggregationRouterV4 _aggRouterV4) {
        //set up all aggregators
        aggRouterV4 = _aggRouterV4;

        //set up mapping between ids and selectors
        idToSelector[Exchanges.ONEINCH] = SwapRouter(this).swapWith1Inch.selector;
    }

    // ======================================= SWAP OPERATIONS =======================================

    function swap(Exchanges id, bytes memory swapData) external returns (uint256 swapOutAmount) {
        //TODO should we add a require here to make sure id is valid? Otherwise it calls the 0x0000 function in this contract which I'm not sure what that would be
        (bool success, bytes memory result) = address(this).call(abi.encodeWithSelector(idToSelector[id], swapData));
        require(success, "Failed to perform swap");
        swapOutAmount = abi.decode(result, (uint256));
    }

    function swapWith1Inch(bytes memory swapData) public returns (uint256 swapOutAmount) {}
}
