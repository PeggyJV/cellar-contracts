// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Cellar } from "src/base/Cellar.sol";

import { console } from "@forge-std/Test.sol";

/**
 * @title Uniswap V3 Adaptor
 * @notice Cellars make delegate call to this contract in order to interact with other Cellar contracts.
 * @author crispymangoes
 */

//TODO
/**
So I am thinking the best way to do this is to create a custom external contract that allows cellars to create UniV3 LP positions.
The adaptor data would have some ID or hash(maybe of the address of the two tokens they want to LP). then on adaptor calls SPs can call a function in this contract to send some of their tokens to be added
to liquidity 
This contract would need to track the cellars balanceOf and assets of, and do the conversion from NFT to underlying. I guess each cellar will need to pass in their position ID, then this contract would go okay, they have this NFT related to this position and then break down the underlying tokens and return the balance
 */
contract UniswapV3Adaptor is BaseAdaptor {
    using SafeERC20 for ERC20;

    /*
        adaptorData = abi.encode(token0, token1)
        adaptorStroage(written in registry) = abi.encode(uint256[] tokenIds)
    */

    //============================================ Global Functions ===========================================

    //============================================ Implement Base Functions ===========================================
    function deposit(
        uint256,
        bytes memory,
        bytes memory
    ) public override {
        revert("User Deposits not allowed");
    }

    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData,
        bytes memory
    ) public override {
        revert("User Withdraws not allowed");
    }

    function withdrawableFrom(bytes memory adaptorData, bytes memory) public view override returns (uint256) {
        return 0;
    }

    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        // Makes a call to registry to get tokenId array from adaptor storage.
        // Does a ton of math to determine the underlying value of all LP tokens it owns
        // This could also get away with making 1 call to the price router to get the exchange rate between the two tokens?
        return 0;
    }

    // Grabs token0 in adaptor data.
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        ERC20 token = abi.decode(adaptorData, (ERC20));
        return token;
    }

    //============================================ High Level Callable Functions ============================================
    // Positions are arbitrary UniV3 positions that could be range orders, limit orders, or normal LP positions.
    function openPosition(uint256 amount0, uint256 amount1) public {
        // Creates a new NFT position and stores the NFT in the token Id array in adaptor storage
    }

    function closePosition(uint256 positionId) public {
        // Grabs array of token Ids from registry, finds corresponding token Id, then removes it from array, and closes position.
    }

    function addToPosition(
        uint256 amount0,
        uint256 amount1,
        uint256 positionId
    ) public {}

    function takeFromPosition(
        uint256 amount0,
        uint256 amount1,
        uint256 positionId
    ) public {}

    //Collects fees from all positions or maybe can specify from which ones?
    function collectFees() public {}
}
