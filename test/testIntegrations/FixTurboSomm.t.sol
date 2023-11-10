// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { PoolAddress } from "@uniswapV3P/libraries/PoolAddress.sol";
import { IUniswapV3Factory } from "@uniswapV3C/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswapV3C/interfaces/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import "@uniswapV3C/libraries/FixedPoint128.sol";
import "@uniswapV3C/libraries/FullMath.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";
import { CellarWithOracle } from "src/base/permutations/CellarWithOracle.sol";
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

// Will test the swapping and cellar position management using adaptors
contract FixTurboSommTest is MainnetStarterTest, AdaptorHelperFunctions, ERC721Holder {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    CellarWithOracle public cellar;
    uint32 public vestingPosition = 100000004;
    address public automationAdmin = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;
    address public sommDev = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address public sommVesting = 0xeFBc79744F4A53bB9C565e4B0895d99Fc4A5cEcB;
    address public vestingAdaptor = 0x3b98BA00f981342664969e609Fb88280704ac479;
    address public feesAndReservesAdaptor = 0x647d264d800A2461E594796af61a39b7735d8933;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18536488;
        _startFork(rpcKey, blockNumber);

        registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);
        priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);

        cellar = CellarWithOracle(0x5195222f69c5821f8095ec565E71e18aB6A2298f);
        deployer = Deployer(deployerAddress);
    }

    function testFix() external {
        vm.prank(multisig);
        registry.distrustPosition(vestingPosition);

        vm.prank(gravityBridgeAddress);
        cellar.forcePositionOut(2, vestingPosition, false);

        console.log("TotalAssets", cellar.totalAssets());
        console.log("TotalSupply", cellar.totalSupply());

        uint64 heartbeat = 1 days / 24;
        uint64 deviationTrigger = 0.0050e4;
        uint64 gracePeriod = 10 days;
        uint16 observationsToUse = 2;
        uint216 startingAnswer = 1e18;
        uint256 allowedAnswerChangeLower = 0.8e4;
        uint256 allowedAnswerChangeUpper = 2e4;

        vm.startPrank(sommDev);
        ERC4626SharePriceOracle temp = _createSharePriceOracle(
            "Turbo SOMM Share Price Oracle V0.2",
            address(cellar),
            heartbeat,
            deviationTrigger,
            gracePeriod,
            observationsToUse,
            automationAdmin,
            startingAnswer,
            allowedAnswerChangeLower,
            allowedAnswerChangeUpper
        );

        vm.stopPrank();

        deal(address(LINK), address(this), 10e18);
        LINK.approve(address(temp), 10e18);
        temp.initialize(10e18);

        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = temp.checkUpkeep(abi.encode(0));

        vm.startPrank(temp.automationForwarder());
        temp.performUpkeep(performData);

        skip(1 days / 24);

        (upkeepNeeded, performData) = temp.checkUpkeep(abi.encode(0));
        temp.performUpkeep(performData);

        skip(1 days / 24);

        (upkeepNeeded, performData) = temp.checkUpkeep(abi.encode(0));
        temp.performUpkeep(performData);
        vm.stopPrank();

        (, , bool notSafeToUse) = temp.getLatest();

        assertTrue(!notSafeToUse, "Oracle should be safe to use.");

        vm.prank(multisig);
        registry.setAddress(8, address(temp));

        vm.prank(gravityBridgeAddress);
        cellar.setSharePriceOracle(8, temp);

        uint256 assetsToDeposit = 100_000e6;
        deal(address(SOMM), address(this), assetsToDeposit);
        SOMM.safeApprove(address(cellar), assetsToDeposit);

        cellar.deposit(assetsToDeposit, address(this));

        assertEq(cellar.balanceOf(address(this)), assetsToDeposit, "Should have minted shares 1:1");

        // Fix somm vesting.
        uint32 newVestingPosition = vestingPosition + 1;
        address newVestingAdaptor = address(new VestingSimpleAdaptor());
        vm.startPrank(multisig);
        registry.trustAdaptor(newVestingAdaptor);
        registry.trustPosition(newVestingPosition, newVestingAdaptor, abi.encode(sommVesting));
        vm.stopPrank();

        vm.startPrank(gravityBridgeAddress);
        cellar.addAdaptorToCatalogue(newVestingAdaptor);
        cellar.addPositionToCatalogue(newVestingPosition);

        // Call addPosition.
        cellar.addPosition(0, newVestingPosition, abi.encode(0), false);

        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(VestingSimpleAdaptor.withdrawAllFromVesting.selector, sommVesting);
            data[0] = Cellar.AdaptorCall({ adaptor: address(newVestingAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }
        vm.stopPrank();

        console.log("TotalAssets", cellar.totalAssets());
        console.log("TotalSupply", cellar.totalSupply());

        // During these 9 days we change the cellar to use the real oracle.
        skip(9 days);

        (uint256 ans, uint256 a, bool notSafeToUse0) = temp.getLatest();

        console.log(ans);
        console.log(a);

        assertTrue(!notSafeToUse0, "Oracle should be safe to use.");
    }

    function _createSharePriceOracle(
        string memory _name,
        address _target,
        uint64 _heartbeat,
        uint64 _deviationTrigger,
        uint64 _gracePeriod,
        uint16 _observationsToUse,
        address _automationAdmin,
        uint216 _startingAnswer,
        uint256 _allowedAnswerChangeLower,
        uint256 _allowedAnswerChangeUpper
    ) internal returns (ERC4626SharePriceOracle) {
        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(ERC4626SharePriceOracle).creationCode;
        constructorArgs = abi.encode(
            ERC4626(_target),
            _heartbeat,
            _deviationTrigger,
            _gracePeriod,
            _observationsToUse,
            automationRegistryV2,
            automationRegistrarV2,
            _automationAdmin,
            address(LINK),
            _startingAnswer,
            _allowedAnswerChangeLower,
            _allowedAnswerChangeUpper
        );

        return ERC4626SharePriceOracle(deployer.deployContract(_name, creationCode, constructorArgs, 0));
    }
}
