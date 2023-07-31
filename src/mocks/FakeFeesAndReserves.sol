// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, ERC20 } from "src/base/Cellar.sol";

contract FakeFeesAndReserves {
    constructor() {}

    function metaData(
        Cellar cellar
    )
        public
        view
        returns (
            ERC20 reserveAsset,
            uint32 managementFee,
            uint64 timestamp,
            uint256 reserves,
            uint256 exactHighWatermark,
            uint256 totalAssets,
            uint256 feesOwed,
            uint8 cellarDecimals,
            uint8 reserveAssetDecimals,
            uint32 performanceFee
        )
    {
        reserveAsset = cellar.asset();
        managementFee = 0;
        timestamp = 0;
        reserves = 0;
        exactHighWatermark = 0;
        totalAssets = 0;
        totalAssets = 0;
        feesOwed = 0;
        cellarDecimals = 0;
        reserveAssetDecimals = 0;
        performanceFee = 0;
    }

    function addAssetsToReserves(uint256 amount) public view {}
}
