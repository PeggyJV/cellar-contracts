// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport} from
    "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport.sol";
import {IChainlinkAggregator} from "src/interfaces/external/IChainlinkAggregator.sol";
import {RolesAuthority, Authority} from "@solmate/auth//authorities/RolesAuthority.sol";
import {Cellar} from "src/base/Cellar.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import {AdaptorHelperFunctions} from "test/resources/AdaptorHelperFunctions.sol";

contract AuthCellarTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport private cellar;
    RolesAuthority private cellarAuthority;

    uint32 private wethPosition = 1;

    uint256 private initialAssets;
    uint256 private initialShares;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);
        // Run Starter setUp code.
        _setUp();

        // Setup pricing
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // Add adaptors and ERC20 positions to the registry.
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));

        string memory cellarName = "Auth Cellar V0.0";
        uint256 initialDeposit = 0.0011e18;
        deal(address(WETH), address(this), initialDeposit);
        WETH.approve(0x2e234DAe75C793f67A35089C9d99245E1C58470b, initialDeposit);
        uint64 platformCut = 0.75e18;
        cellar = new CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport(
            address(this),
            registry,
            WETH,
            cellarName,
            "POG",
            wethPosition,
            abi.encode(true),
            initialDeposit,
            platformCut,
            type(uint192).max,
            vault
        );

        vm.label(multisig, "multisig");
        vm.label(strategist, "strategist");
        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);
        initialAssets = cellar.totalAssets();
        initialShares = cellar.totalSupply();

        cellarAuthority = new RolesAuthority(address(this), Authority(address(0)));
    }

    function testAuth() external {
        // Currently only the owner address can make any authorized calls.
        vm.startPrank(strategist);
        vm.expectRevert(bytes("UNAUTHORIZED"));
        cellar.addPositionToCatalogue(wethPosition);
        vm.stopPrank();

        // In order to allow the strategist to do anything, we need to setup a new role for them, and give that roles all the permissions it needs.
        uint8 strategistRole = 1;
        cellarAuthority.setRoleCapability(strategistRole, address(cellar), Cellar.addPositionToCatalogue.selector, true);
        cellarAuthority.setUserRole(strategist, strategistRole, true);

        // Now the ownder of the cellar must set its authority.
        cellar.setAuthority(cellarAuthority);

        // The strategist is now able to call the authorized function.
        vm.startPrank(strategist);
        cellar.addPositionToCatalogue(wethPosition);
        vm.stopPrank();

        // The owner of the cellar has the option to either set the authority to the zero address to stop calls, or
        // the owner of the authority can either remove the strategist from the role, or
        // the owner can remove the `addPositionToCatalogue` privilege from the strategistRole.

        cellarAuthority.setRoleCapability(
            strategistRole, address(cellar), Cellar.addPositionToCatalogue.selector, false
        );

        vm.startPrank(strategist);
        vm.expectRevert(bytes("UNAUTHORIZED"));
        cellar.addPositionToCatalogue(wethPosition);
        vm.stopPrank();
    }
}
