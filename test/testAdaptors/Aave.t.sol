// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

// Import Adaptors
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";

import { IPool } from "src/interfaces/external/IPool.sol";

import { CellarWithAaveFlashLoans } from "src/base/permutations/CellarWithAaveFlashLoans.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract CellarAaveTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    AaveATokenAdaptor public aaveATokenAdaptor;
    AaveDebtTokenAdaptor public aaveDebtTokenAdaptor;
    CellarWithAaveFlashLoans public cellar;

    IPool public pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    uint32 public usdcPosition = 1;
    uint32 public aV2USDCPosition = 1_000_001;
    uint32 public debtUSDCPosition = 1_000_002;

    function setUp() public {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(AaveATokenAdaptor).creationCode;
        constructorArgs = abi.encode(address(pool), address(WETH), 1.05e18);
        aaveATokenAdaptor = AaveATokenAdaptor(
            deployer.deployContract("Aave AToken Adaptor V0.0", creationCode, constructorArgs, 0)
        );
        creationCode = type(AaveDebtTokenAdaptor).creationCode;
        constructorArgs = abi.encode(address(pool), 1.05e18);
        aaveDebtTokenAdaptor = AaveDebtTokenAdaptor(
            deployer.deployContract("Aave DebtToken Adaptor V0.0", creationCode, constructorArgs, 0)
        );

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(aaveATokenAdaptor));
        registry.trustAdaptor(address(aaveDebtTokenAdaptor));

        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(aV2USDCPosition, address(aaveATokenAdaptor), abi.encode(address(aV2USDC)));
        registry.trustPosition(debtUSDCPosition, address(aaveDebtTokenAdaptor), abi.encode(address(dV2USDC)));

        uint256 minHealthFactor = 1.1e18;

        string memory cellarName = "AAVE Debt Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(USDC), address(this), initialDeposit);
        USDC.approve(cellarAddress, initialDeposit);

        creationCode = type(CellarWithAaveFlashLoans).creationCode;
        constructorArgs = abi.encode(
            address(this),
            registry,
            USDC,
            cellarName,
            cellarName,
            aV2USDCPosition,
            abi.encode(minHealthFactor),
            initialDeposit,
            platformCut,
            type(uint192).max,
            address(pool)
        );

        cellar = CellarWithAaveFlashLoans(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveDebtTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));

        cellar.addPositionToCatalogue(usdcPosition);
        cellar.addPositionToCatalogue(debtUSDCPosition);

        cellar.addPosition(1, usdcPosition, abi.encode(0), false);
        cellar.addPosition(0, debtUSDCPosition, abi.encode(0), true);

        USDC.safeApprove(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        // stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        uint256 initialAssets = cellar.totalAssets();
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(
            aV2USDC.balanceOf(address(cellar)),
            (assets + initialAssets),
            1,
            "Assets should have been deposited into Aave."
        );
    }

    function testWithdraw(uint256 assets) external {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        deal(address(USDC), address(this), 0);
        uint256 amountToWithdraw = cellar.maxWithdraw(address(this)) - 1; // -1 accounts for rounding errors when supplying liquidity to aTokens.
        cellar.withdraw(amountToWithdraw, address(this), address(this));

        assertEq(
            USDC.balanceOf(address(this)),
            amountToWithdraw,
            "Amount withdrawn should equal callers USDC balance."
        );
    }

    function testTotalAssets(uint256 assets) external {
        uint256 initialAssets = cellar.totalAssets();
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(
            cellar.totalAssets(),
            (assets + initialAssets),
            1,
            "Total assets should equal assets deposited."
        );
    }

    function testTakingOutLoans(uint256 assets) external {
        uint256 initialAssets = cellar.totalAssets();
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        assertApproxEqAbs(
            aV2USDC.balanceOf(address(cellar)),
            (assets + initialAssets),
            1,
            "Cellar should have aV2USDC worth of assets."
        );

        // Take out a USDC loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrowFromAaveV2(dV2USDC, assets / 2);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            dV2USDC.balanceOf(address(cellar)),
            assets / 2,
            1,
            "Cellar should have dV2USDC worth of assets/2."
        );
    }

    function testTakingOutLoansInUntrackedPosition() external {
        uint256 initialAssets = cellar.totalAssets();
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        assertApproxEqAbs(
            aV2USDC.balanceOf(address(cellar)),
            (assets + initialAssets),
            1,
            "Cellar should have aV2USDC worth of assets."
        );

        // Take out a USDC loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        uint256 usdcPrice = priceRouter.getExchangeRate(USDC, WETH);
        uint256 wethLoanAmount = assets.mulDivDown(10 ** WETH.decimals(), usdcPrice) / 2;
        adaptorCalls[0] = _createBytesDataToBorrowFromAaveV2(dV2WETH, wethLoanAmount);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    AaveDebtTokenAdaptor.AaveDebtTokenAdaptor__DebtPositionsMustBeTracked.selector,
                    address(dV2WETH)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testRepayingLoans(uint256 assets) external {
        uint256 initialAssets = cellar.totalAssets();
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        assertApproxEqAbs(
            aV2USDC.balanceOf(address(cellar)),
            (assets + initialAssets),
            1,
            "Cellar should have aV2USDC worth of assets."
        );

        // Take out a USDC loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrowFromAaveV2(dV2USDC, assets / 2);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            dV2USDC.balanceOf(address(cellar)),
            assets / 2,
            1,
            "Cellar should have dV2USDC worth of assets/2."
        );

        // Repay the loan.
        adaptorCalls[0] = _createBytesDataToRepayToAaveV2(USDC, assets / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(dV2USDC.balanceOf(address(cellar)), 0, 1, "Cellar should have no dV2USDC left.");
    }

    function testWithdrawableFromaV2USDC() external {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Take out a USDC loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrowFromAaveV2(dV2USDC, assets / 2);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 maxAssets = cellar.maxWithdraw(address(this));
        cellar.withdraw(maxAssets, address(this), address(this));

        assertEq(USDC.balanceOf(address(this)), maxAssets, "Should have withdraw max assets possible.");

        maxAssets = cellar.maxWithdraw(address(this));
        cellar.withdraw(maxAssets, address(this), address(this));

        assertEq(
            cellar.totalAssetsWithdrawable(),
            0,
            "Cellar should have remaining assets locked until strategist rebalances."
        );
    }

    function testWithdrawableFromaV2WETH() external {
        // First adjust cellar to work primarily with WETH.
        // Make vanilla USDC the holding position.
        cellar.swapPositions(0, 1, false);
        cellar.setHoldingPosition(usdcPosition);

        // Adjust rebalance deviation so we can swap full amount of USDC for WETH.
        cellar.setRebalanceDeviation(0.003e18);

        // Add WETH, aV2WETH, and dV2WETH as trusted positions to the registry.
        uint32 wethPosition = 2;
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        uint32 aV2WETHPosition = 1_000_003;
        registry.trustPosition(aV2WETHPosition, address(aaveATokenAdaptor), abi.encode(address(aV2WETH)));
        uint32 debtWETHPosition = 1_000_004;
        registry.trustPosition(debtWETHPosition, address(aaveDebtTokenAdaptor), abi.encode(address(dV2WETH)));
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(aV2WETHPosition);
        cellar.addPositionToCatalogue(debtWETHPosition);

        // Pull USDC out of Aave.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromAaveV2(USDC, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // Remove dV2USDC and aV2USDC positions.
        cellar.removePosition(1, false);
        cellar.removePosition(0, true);

        cellar.addPosition(1, aV2WETHPosition, abi.encode(1.1e18), false);
        cellar.addPosition(0, debtWETHPosition, abi.encode(0), true);
        cellar.addPosition(2, wethPosition, abi.encode(0), false);

        // Deposit into the cellar.
        uint256 assets = 10_000e6 + cellar.totalAssets();
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Perform several adaptor calls.
        // - Swap all USDC for WETH.
        // - Deposit all WETH into Aave.
        // - Take out a WETH loan on Aave.
        data = new Cellar.AdaptorCall[](3);
        bytes[] memory adaptorCallsForFirstAdaptor = new bytes[](1);
        adaptorCallsForFirstAdaptor[0] = _createBytesDataForSwapWithUniv3(USDC, WETH, 500, assets);
        data[0] = Cellar.AdaptorCall({
            adaptor: address(swapWithUniswapAdaptor),
            callData: adaptorCallsForFirstAdaptor
        });

        bytes[] memory adaptorCallsForSecondAdaptor = new bytes[](1);
        adaptorCallsForSecondAdaptor[0] = _createBytesDataToLendOnAaveV2(WETH, type(uint256).max);
        data[1] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCallsForSecondAdaptor });

        // Figure out roughly how much WETH the cellar has on Aave.
        uint256 approxWETHCollateral = priceRouter.getValue(USDC, assets, WETH);
        bytes[] memory adaptorCallsForThirdAdaptor = new bytes[](1);
        adaptorCallsForThirdAdaptor[0] = _createBytesDataToBorrowFromAaveV2(dV2WETH, approxWETHCollateral / 2);
        data[2] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCallsForThirdAdaptor });
        cellar.callOnAdaptor(data);

        uint256 maxAssets = cellar.maxWithdraw(address(this));
        cellar.withdraw(maxAssets, address(this), address(this));

        assertEq(
            cellar.totalAssetsWithdrawable(),
            0,
            "Cellar should have remaining assets locked until strategist rebalances."
        );
    }

    function testTakingOutAFlashLoan() external {
        uint256 initialAssets = cellar.totalAssets();
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Increase rebalance deviation so we can enter a larger position.
        // Flash loan fee is 0.09%, since we are taking a loan of 4x our assets, the total fee is 4x0.09% or 0.036%
        cellar.setRebalanceDeviation(0.004e18);

        // Perform several adaptor calls.
        // - Use Flash loan to borrow `assets` USDC.
        //      - Deposit extra USDC into AAVE.
        //      - Take out USDC loan of (assets * 1.0009) against new collateral
        //      - Repay flash loan with new USDC loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCallsForFlashLoan = new bytes[](1);
        Cellar.AdaptorCall[] memory dataInsideFlashLoan = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCallsInsideFlashLoanFirstAdaptor = new bytes[](1);
        bytes[] memory adaptorCallsInsideFlashLoanSecondAdaptor = new bytes[](1);
        adaptorCallsInsideFlashLoanFirstAdaptor[0] = _createBytesDataToLendOnAaveV2(USDC, 2 * assets);
        adaptorCallsInsideFlashLoanSecondAdaptor[0] = _createBytesDataToBorrowFromAaveV2(
            dV2USDC,
            2 * assets.mulWadDown(1.009e18)
        );
        dataInsideFlashLoan[0] = Cellar.AdaptorCall({
            adaptor: address(aaveATokenAdaptor),
            callData: adaptorCallsInsideFlashLoanFirstAdaptor
        });
        dataInsideFlashLoan[1] = Cellar.AdaptorCall({
            adaptor: address(aaveDebtTokenAdaptor),
            callData: adaptorCallsInsideFlashLoanSecondAdaptor
        });
        address[] memory loanToken = new address[](1);
        loanToken[0] = address(USDC);
        uint256[] memory loanAmount = new uint256[](1);
        loanAmount[0] = 4 * assets;
        adaptorCallsForFlashLoan[0] = _createBytesDataToFlashLoanFromAaveV2(
            loanToken,
            loanAmount,
            abi.encode(dataInsideFlashLoan)
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCallsForFlashLoan });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            aV2USDC.balanceOf(address(cellar)),
            (3 * assets) + initialAssets,
            1,
            "Cellar should have 3x its aave assets using a flash loan."
        );
    }

    function testMultipleATokensAndDebtTokens() external {
        cellar.setRebalanceDeviation(0.004e18);
        // Add WETH, aV2WETH, and dV2WETH as trusted positions to the registry.
        uint32 wethPosition = 2;
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        uint32 aV2WETHPosition = 1_000_003;
        registry.trustPosition(aV2WETHPosition, address(aaveATokenAdaptor), abi.encode(address(aV2WETH)));
        uint32 debtWETHPosition = 1_000_004;
        registry.trustPosition(debtWETHPosition, address(aaveDebtTokenAdaptor), abi.encode(address(dV2WETH)));
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(aV2WETHPosition);
        cellar.addPositionToCatalogue(debtWETHPosition);

        // Purposely do not set aV2WETH positions min health factor to signal the adaptor the position should return 0 for withdrawableFrom.
        cellar.addPosition(2, aV2WETHPosition, abi.encode(0), false);
        cellar.addPosition(1, debtWETHPosition, abi.encode(0), true);
        cellar.addPosition(3, wethPosition, abi.encode(0), false);

        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Perform several adaptor calls.
        // - Withdraw USDC from Aave.
        // - Swap USDC for WETH.
        // - Deposit WETH into Aave.
        // - Take out USDC loan.
        // - Take out WETH loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](4);
        bytes[] memory adaptorCallsFirstAdaptor = new bytes[](1);
        bytes[] memory adaptorCallsSecondAdaptor = new bytes[](1);
        bytes[] memory adaptorCallsThirdAdaptor = new bytes[](1);
        bytes[] memory adaptorCallsFourthAdaptor = new bytes[](2);
        adaptorCallsFirstAdaptor[0] = _createBytesDataToWithdrawFromAaveV2(USDC, assets / 2);
        adaptorCallsSecondAdaptor[0] = _createBytesDataForSwapWithUniv3(USDC, WETH, 500, assets / 2);
        adaptorCallsThirdAdaptor[0] = _createBytesDataToLendOnAaveV2(WETH, type(uint256).max);
        adaptorCallsFourthAdaptor[0] = _createBytesDataToBorrowFromAaveV2(dV2USDC, assets / 4);
        uint256 wethAmount = priceRouter.getValue(USDC, assets / 2, WETH) / 2; // To get approx a 50% LTV loan.
        adaptorCallsFourthAdaptor[1] = _createBytesDataToBorrowFromAaveV2(dV2WETH, wethAmount);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCallsFirstAdaptor });
        data[1] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCallsSecondAdaptor });
        data[2] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCallsThirdAdaptor });
        data[3] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCallsFourthAdaptor });
        cellar.callOnAdaptor(data);

        uint256 maxAssets = cellar.maxWithdraw(address(this));
        cellar.withdraw(maxAssets, address(this), address(this));
    }

    // This check stops strategists from taking on any debt in positions they do not set up properly.
    // This stops the attack vector or strategists opening up an untracked debt position then depositing the funds into a vesting contract.
    function testTakingOutLoanInUntrackedPosition() external {
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrowFromAaveV2(dV2WETH, 1e18);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    AaveDebtTokenAdaptor.AaveDebtTokenAdaptor__DebtPositionsMustBeTracked.selector,
                    address(dV2WETH)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testRepayingDebtThatIsNotOwed() external {
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToRepayToAaveV2(USDC, 1e6);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });

        // Error code 15: No debt of selected type.
        vm.expectRevert(bytes("15"));
        cellar.callOnAdaptor(data);
    }

    function testBlockExternalReceiver() external {
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist tries to withdraw USDC to their own wallet using Adaptor's `withdraw` function.
        address maliciousStrategist = vm.addr(10);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = abi.encodeWithSelector(
            AaveATokenAdaptor.withdraw.selector,
            100e6,
            maliciousStrategist,
            abi.encode(address(aV2USDC)),
            abi.encode(0)
        );

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });

        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
        cellar.callOnAdaptor(data);
    }

    function testAddingPositionWithUnsupportedAssetsReverts() external {
        uint32 aV2TUSDPositionId = 1_000_003;
        // trust position fails because TUSD is not set up for pricing.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(Registry.Registry__PositionPricingNotSetUp.selector, address(TUSD)))
        );
        registry.trustPosition(aV2TUSDPositionId, address(aaveATokenAdaptor), abi.encode(address(aV2TUSD)));

        // Add TUSD.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(TUSD_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, TUSD_USD_FEED);
        priceRouter.addAsset(TUSD, settings, abi.encode(stor), price);

        // trust position works now.
        registry.trustPosition(aV2TUSDPositionId, address(aaveATokenAdaptor), abi.encode(address(aV2TUSD)));
    }

    // ========================================== INTEGRATION TEST ==========================================

    function testIntegration() external {
        // Manage positions to reflect the following
        // 0) aV2USDC (holding)
        // 1) aV2WETH
        // 2) aV2WBTC

        // Debt Position
        // 0) dV2USDC
        uint32 aV2WETHPosition = 1_000_003;
        registry.trustPosition(aV2WETHPosition, address(aaveATokenAdaptor), abi.encode(address(aV2WETH)));
        uint32 aV2WBTCPosition = 1_000_004;
        registry.trustPosition(aV2WBTCPosition, address(aaveATokenAdaptor), abi.encode(address(aV2WBTC)));
        cellar.addPositionToCatalogue(aV2WETHPosition);
        cellar.addPositionToCatalogue(aV2WBTCPosition);
        cellar.addPosition(1, aV2WETHPosition, abi.encode(0), false);
        cellar.addPosition(2, aV2WBTCPosition, abi.encode(0), false);
        cellar.removePosition(3, false);

        // Have whale join the cellar with 1M USDC.
        uint256 assets = 1_000_000e6;
        address whale = vm.addr(777);
        deal(address(USDC), whale, assets);
        vm.startPrank(whale);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, whale);
        vm.stopPrank();

        // Strategist manages cellar in order to achieve the following portfolio.
        // ~20% in aV2USDC.
        // ~40% Aave aV2WETH/dV2USDC with 2x LONG on WETH.
        // ~40% Aave aV2WBTC/dV2USDC with 3x LONG on WBTC.

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](5);
        // Create data to withdraw USDC, swap for WETH and WBTC and lend them on Aave.
        uint256 amountToSwap = assets.mulDivDown(8, 10);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromAaveV2(USDC, assets.mulDivDown(8, 10));

            data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](2);
            adaptorCalls[0] = _createBytesDataForSwapWithUniv3(USDC, WETH, 500, amountToSwap);
            amountToSwap = priceRouter.getValue(USDC, amountToSwap / 2, WETH);
            adaptorCalls[1] = _createBytesDataForSwapWithUniv3(WETH, WBTC, 500, amountToSwap);
            data[1] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }

        {
            bytes[] memory adaptorCalls = new bytes[](2);

            adaptorCalls[0] = _createBytesDataToLendOnAaveV2(WETH, type(uint256).max);
            adaptorCalls[1] = _createBytesDataToLendOnAaveV2(WBTC, type(uint256).max);
            data[2] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        }

        // Create data to flash loan USDC, sell it, and lend more WETH and WBTC on Aave.
        {
            // Want to borrow 3x 40% of assets
            uint256 USDCtoFlashLoan = assets.mulDivDown(12, 10);
            // Borrow the flash loan amount + premium.
            uint256 USDCtoBorrow = USDCtoFlashLoan.mulDivDown(1e3 + pool.FLASHLOAN_PREMIUM_TOTAL(), 1e3);

            bytes[] memory adaptorCallsForFlashLoan = new bytes[](1);
            Cellar.AdaptorCall[] memory dataInsideFlashLoan = new Cellar.AdaptorCall[](3);
            bytes[] memory adaptorCallsInsideFlashLoanFirstAdaptor = new bytes[](2);
            bytes[] memory adaptorCallsInsideFlashLoanSecondAdaptor = new bytes[](2);
            bytes[] memory adaptorCallsInsideFlashLoanThirdAdaptor = new bytes[](1);
            // Swap USDC for WETH.
            adaptorCallsInsideFlashLoanFirstAdaptor[0] = _createBytesDataForSwapWithUniv3(
                USDC,
                WETH,
                500,
                USDCtoFlashLoan
            );
            // Swap USDC for WBTC.
            amountToSwap = priceRouter.getValue(USDC, USDCtoFlashLoan.mulDivDown(2, 3), WETH);
            adaptorCallsInsideFlashLoanFirstAdaptor[1] = _createBytesDataForSwapWithUniv3(
                WETH,
                WBTC,
                500,
                amountToSwap
            );
            // Lend USDC on Aave specifying to use the max amount available.
            adaptorCallsInsideFlashLoanSecondAdaptor[0] = _createBytesDataToLendOnAaveV2(WETH, type(uint256).max);
            adaptorCallsInsideFlashLoanSecondAdaptor[1] = _createBytesDataToLendOnAaveV2(WBTC, type(uint256).max);
            adaptorCallsInsideFlashLoanThirdAdaptor[0] = _createBytesDataToBorrowFromAaveV2(dV2USDC, USDCtoBorrow);
            dataInsideFlashLoan[0] = Cellar.AdaptorCall({
                adaptor: address(swapWithUniswapAdaptor),
                callData: adaptorCallsInsideFlashLoanFirstAdaptor
            });
            dataInsideFlashLoan[1] = Cellar.AdaptorCall({
                adaptor: address(aaveATokenAdaptor),
                callData: adaptorCallsInsideFlashLoanSecondAdaptor
            });
            dataInsideFlashLoan[2] = Cellar.AdaptorCall({
                adaptor: address(aaveDebtTokenAdaptor),
                callData: adaptorCallsInsideFlashLoanThirdAdaptor
            });
            address[] memory loanToken = new address[](1);
            loanToken[0] = address(USDC);
            uint256[] memory loanAmount = new uint256[](1);
            loanAmount[0] = USDCtoFlashLoan;
            adaptorCallsForFlashLoan[0] = _createBytesDataToFlashLoanFromAaveV2(
                loanToken,
                loanAmount,
                abi.encode(dataInsideFlashLoan)
            );
            data[3] = Cellar.AdaptorCall({
                adaptor: address(aaveDebtTokenAdaptor),
                callData: adaptorCallsForFlashLoan
            });
        }

        // Create data to lend remaining USDC on Aave.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnAaveV2(USDC, type(uint256).max);

            data[4] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        }
        // Adjust rebalance deviation to account for slippage and fees(swap and flash loan).
        cellar.setRebalanceDeviation(0.03e18);
        cellar.callOnAdaptor(data);

        assertLt(cellar.totalAssetsWithdrawable(), assets, "Assets withdrawable should be less than assets.");

        // Whale withdraws as much as they can.
        vm.startPrank(whale);
        uint256 assetsToWithdraw = cellar.maxWithdraw(whale);
        cellar.withdraw(assetsToWithdraw, whale, whale);
        vm.stopPrank();

        assertEq(USDC.balanceOf(whale), assetsToWithdraw, "Amount withdrawn should equal maxWithdraw for Whale.");

        // Other user joins.
        assets = 100_000e6;
        address user = vm.addr(777);
        deal(address(USDC), user, assets);
        vm.startPrank(user);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, user);
        vm.stopPrank();

        assertApproxEqAbs(
            cellar.totalAssetsWithdrawable(),
            assets,
            1,
            "Total assets withdrawable should equal user deposit."
        );

        // Whale withdraws as much as they can.
        vm.startPrank(whale);
        assetsToWithdraw = cellar.maxWithdraw(whale);
        cellar.withdraw(assetsToWithdraw, whale, whale);
        vm.stopPrank();

        // Strategist must unwind strategy before any more withdraws can be made.
        assertEq(cellar.totalAssetsWithdrawable(), 0, "There should be no more assets withdrawable.");

        // Strategist is more Bullish on WBTC than WETH, so they unwind the WETH position and keep the WBTC position.
        data = new Cellar.AdaptorCall[](2);
        {
            uint256 cellarAV2WETH = aV2WETH.balanceOf(address(cellar));
            // By lowering the USDC flash loan amount, we free up more aV2USDC for withdraw, but lower the health factor
            uint256 USDCtoFlashLoan = priceRouter.getValue(WETH, cellarAV2WETH, USDC).mulDivDown(8, 10);

            bytes[] memory adaptorCallsForFlashLoan = new bytes[](1);
            Cellar.AdaptorCall[] memory dataInsideFlashLoan = new Cellar.AdaptorCall[](3);
            bytes[] memory adaptorCallsInsideFlashLoanFirstAdaptor = new bytes[](1);
            bytes[] memory adaptorCallsInsideFlashLoanSecondAdaptor = new bytes[](1);
            bytes[] memory adaptorCallsInsideFlashLoanThirdAdaptor = new bytes[](1);
            // Repay USDC debt.
            adaptorCallsInsideFlashLoanFirstAdaptor[0] = _createBytesDataToRepayToAaveV2(USDC, USDCtoFlashLoan);
            // Withdraw WETH and swap for USDC.
            adaptorCallsInsideFlashLoanSecondAdaptor[0] = _createBytesDataToWithdrawFromAaveV2(WETH, cellarAV2WETH);
            adaptorCallsInsideFlashLoanThirdAdaptor[0] = _createBytesDataForSwapWithUniv3(
                WETH,
                USDC,
                500,
                cellarAV2WETH
            );
            dataInsideFlashLoan[0] = Cellar.AdaptorCall({
                adaptor: address(aaveDebtTokenAdaptor),
                callData: adaptorCallsInsideFlashLoanFirstAdaptor
            });
            dataInsideFlashLoan[1] = Cellar.AdaptorCall({
                adaptor: address(aaveATokenAdaptor),
                callData: adaptorCallsInsideFlashLoanSecondAdaptor
            });
            dataInsideFlashLoan[2] = Cellar.AdaptorCall({
                adaptor: address(swapWithUniswapAdaptor),
                callData: adaptorCallsInsideFlashLoanThirdAdaptor
            });
            address[] memory loanToken = new address[](1);
            loanToken[0] = address(USDC);
            uint256[] memory loanAmount = new uint256[](1);
            loanAmount[0] = USDCtoFlashLoan;
            adaptorCallsForFlashLoan[0] = _createBytesDataToFlashLoanFromAaveV2(
                loanToken,
                loanAmount,
                abi.encode(dataInsideFlashLoan)
            );
            data[0] = Cellar.AdaptorCall({
                adaptor: address(aaveDebtTokenAdaptor),
                callData: adaptorCallsForFlashLoan
            });
        }

        // Create data to lend remaining USDC on Aave.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnAaveV2(USDC, type(uint256).max);

            data[1] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        assertGt(
            cellar.totalAssetsWithdrawable(),
            100_000e6,
            "There should a significant amount of assets withdrawable."
        );
    }
}
