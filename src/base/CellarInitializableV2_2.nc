// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, Registry, ERC20, PriceRouter } from "src/base/Cellar.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract CellarInitializableV2_2 is Cellar, Initializable {
    /**
     * @notice Constructor is only called for the implementation contract,
     *         so it can be safely filled with mostly zero inputs.
     */
    constructor(
        Registry _registry
    )
        Cellar(
            _registry,
            ERC20(address(0)),
            "",
            "",
            abi.encode(new uint32[](0), new uint32[](0), new bytes[](0), new bytes[](0), 0, address(0), 0, 0)
        )
    {}

    /**
     * @notice Initialize function called by factory contract immediately after deployment.
     * @param params abi encoded parameter containing
     *               - Registry contract
     *               - ERC20 cellar asset
     *               - String name of cellar
     *               - String symbol of cellar
     *               - uint32 holding position
     *               - bytes holding position config
     *               - address strategist payout address
     */
    function initialize(bytes calldata params) external initializer {
        (
            address _owner,
            Registry _registry,
            ERC20 _asset,
            string memory _name,
            string memory _symbol,
            uint32 _holdingPosition,
            bytes memory _holdingPositionConfig,
            address _strategistPayout
        ) = abi.decode(params, (address, Registry, ERC20, string, string, uint32, bytes, address));

        // Initialize Cellar
        registry = _registry;
        asset = _asset;
        owner = _owner;
        shareLockPeriod = MAXIMUM_SHARE_LOCK_PERIOD;
        allowedRebalanceDeviation = 0.003e18;
        priceRouter = PriceRouter(registry.getAddress(PRICE_ROUTER_REGISTRY_SLOT));

        // Aave V3 pool contract on ETH Mainnet
        aavePool = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

        // Initialize ERC20
        name = _name;
        symbol = _symbol;
        decimals = 18;
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();

        // Initialize Reentrancy Guard
        locked = 1;

        // Initialize Holding Position.
        _addPositionToCatalogue(_holdingPosition);
        _addPosition(0, _holdingPosition, _holdingPositionConfig, false);
        _setHoldingPosition(_holdingPosition);

        // Initialize remaining values.
        feeData.strategistPlatformCut = 0.8e18;
        feeData.strategistPayoutAddress = _strategistPayout;
        // feeData = FeeData({
        //     strategistPlatformCut: 0.8e18,
        //     platformFee: 0.005e18,
        //     lastAccrual: uint64(block.timestamp),
        //     strategistPayoutAddress: _strategistPayout
        // });
    }
}
