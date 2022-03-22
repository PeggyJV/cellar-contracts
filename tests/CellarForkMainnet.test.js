const hre = require("hardhat");
const { expect } = require("chai");
const { BigNumber } = require("ethers");
const ethers = hre.ethers;
const { alchemyApiKey } = require('../secrets.json');

describe("AaveV2StablecoinCellar", () => {
  let owner;
  let alice;

  let usdc;
  let usdt;
  let dai;
  let aave;
  let hex;
  
  let aUSDC;
  let aDAI;

  let swapRouter;
  let cellar;
  let lendingPool;
  let incentivesController;
  let stkAAVE;

  let tx;
  
  // addresses of smart contracts in the mainnet
  const routerAddress = "0xE592427A0AEce92De3Edee1F18E0157C05861564"; // Uniswap V3 SwapRouter
  const sushiSwapRouterAddress = "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F" // SushiSwap V2 Router
  const lendingPoolAddress = "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9"; // Aave LendingPool
  const incentivesControllerAddress =
    "0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5"; // StakedTokenIncentivesController
  const gravityBridgeAddress = "0x69592e6f9d21989a043646fE8225da2600e5A0f7" // Cosmos Gravity Bridge contract
  const stkAAVEAddress = "0x4da27a545c0c5B758a6BA100e3a049001de870f5"; // StakedTokenV2Rev3

  // addresses of tokens in the mainnet
  const aaveAddress = "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9";
  const usdcAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
  const usdtAddress = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
  const daiAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
  const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const aUSDCAddress = "0xBcca60bB61934080951369a648Fb03DF4F96263C";
  const aDAIAddress = "0x028171bCA77440897B824Ca71D1c56caC55b68A3";
  const hexAddress = "0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39";
  
  const timestamp = async () => {
    const latestBlock = await ethers.provider.getBlock(
      await ethers.provider.getBlockNumber()
    );

    return latestBlock.timestamp;
  };

  const timetravel = async (addTime) => {
    await network.provider.send("evm_increaseTime", [addTime]);
    await network.provider.send("evm_mine");
  };
  
  const Num = (number, decimals) => {
    const [characteristic, mantissa] = number.toString().split(".");
    const padding = mantissa ? decimals - mantissa.length : decimals;
    return characteristic + (mantissa ?? "") + "0".repeat(padding);
  };
  
  beforeEach(async () => {
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${alchemyApiKey}`,
            blockNumber: 13837533
          },
        },
      ],
    });
    
    [owner, alice] = await ethers.getSigners();

    // stablecoins contracts
    const Token = await ethers.getContractFactory(
      "@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20"
    );
    usdc = await Token.attach(usdcAddress);
    usdt = await Token.attach(usdtAddress);
    dai = await Token.attach(daiAddress);
    aave = await Token.attach(aaveAddress);
    aDAI = await Token.attach(aDAIAddress);
    aUSDC = await Token.attach(aUSDCAddress);
    hex = await Token.attach(hexAddress);

    // uniswap v3 router contract
    swapRouter = await ethers.getContractAt("ISwapRouter", routerAddress);

    lendingPool = await ethers.getContractAt(
      "ILendingPool",
      lendingPoolAddress
    );

    stkAAVE = await ethers.getContractAt("IStakedTokenV2", stkAAVEAddress);

    incentivesController = await ethers.getContractAt(
      "IAaveIncentivesController",
      incentivesControllerAddress
    );

    // Deploy cellar contract
    const AaveV2StablecoinCellar = await ethers.getContractFactory(
      "AaveV2StablecoinCellar"
    );

    cellar = await AaveV2StablecoinCellar.deploy(
      routerAddress,
      sushiSwapRouterAddress,
      lendingPoolAddress,
      incentivesControllerAddress,
      gravityBridgeAddress,
      stkAAVEAddress,
      aaveAddress,
      wethAddress,
      usdc.address,
      usdc.address
    );
    await cellar.deployed();

    await cellar.setInputToken(wethAddress, true);
    await cellar.setInputToken(usdc.address, true);
    await cellar.setInputToken(usdt.address, true);
    await cellar.setInputToken(dai.address, true);

    await swapRouter.exactOutputSingle(
      [
        wethAddress, // tokenIn
        usdc.address, // tokenOut
        3000, // fee
        owner.address, // recipient
        1657479474, // deadline
        Num(1000, 6), // amountOut
        ethers.utils.parseEther("10"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    await swapRouter.exactOutputSingle(
      [
        wethAddress, // tokenIn
        dai.address, // tokenOut
        3000, // fee
        owner.address, // recipient
        1657479474, // deadline
        Num(1000, 18), // amountOut
        ethers.utils.parseEther("10"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    await swapRouter.exactOutputSingle(
      [
        wethAddress, // tokenIn
        usdt.address, // tokenOut
        3000, // fee
        owner.address, // recipient
        1657479474, // deadline
        Num(1000, 6), // amountOut
        ethers.utils.parseEther("10"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    await swapRouter.exactOutputSingle(
      [
        wethAddress, // tokenIn
        usdc.address, // tokenOut
        3000, // fee
        alice.address, // recipient
        1657479474, // deadline
        Num(1000, 6), // amountOut
        ethers.utils.parseEther("10"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    await swapRouter.exactOutputSingle(
      [
        wethAddress, // tokenIn
        dai.address, // tokenOut
        3000, // fee
        alice.address, // recipient
        1657479474, // deadline
        Num(1000, 18), // amountOut
        ethers.utils.parseEther("10"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    await swapRouter.exactOutputSingle(
      [
        wethAddress, // tokenIn
        usdt.address, // tokenOut
        3000, // fee
        alice.address, // recipient
        1657479474, // deadline
        Num(1000, 6), // amountOut
        ethers.utils.parseEther("10"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    await usdc.approve(
      cellar.address,
      Num(10000, 6)
    );
    await usdt.approve(
      cellar.address,
      Num(10000, 6)
    );
    await dai.approve(
      cellar.address,
      Num(10000, 18)
    );

    await usdc
      .connect(alice)
      .approve(cellar.address, Num(10000, 6));
    await dai
      .connect(alice)
      .approve(cellar.address, Num(10000, 18));
    await usdt
      .connect(alice)
      .approve(cellar.address, Num(10000, 6));

    // balances accumulate every test
  });

  describe("deposit", () => {
    it("should mint correct amount of shares to user", async () => {
      // add $100 of inactive assets in cellar
      await cellar["deposit(uint256)"](Num(100, 6));
      // expect 100 shares to be minted (because total supply of shares is 0)
      expect(await cellar.balanceOf(owner.address)).to.eq(Num(100, 18));

      // add $50 of inactive assets in cellar
      await cellar
        .connect(alice)
        ["deposit(uint256)"](Num(50, 6));
      // expect 50 shares = 100 total shares * ($50 / $100) to be minted
      expect(await cellar.balanceOf(alice.address)).to.eq(Num(50, 18));
    });

    it("should transfer input token from user to cellar", async () => {
      const initialUserBalance = await usdc.balanceOf(owner.address);
      const initialCellarBalance = await usdc.balanceOf(cellar.address);

      await cellar["deposit(uint256)"](Num(100, 6));

      const updatedUserBalance = await usdc.balanceOf(owner.address);
      const updatedCellarBalance = await usdc.balanceOf(cellar.address);

      // expect $100 to have been transferred from owner to cellar
      expect(initialUserBalance.sub(updatedUserBalance)).to.eq(Num(100, 6));
      expect(updatedCellarBalance.sub(initialCellarBalance)).to.eq(Num(100, 6));
    });

    it("should swap input token for current lending token if not already", async () => {
      const initialUserBalance = await dai.balanceOf(owner.address);
      const initialCellarBalance = await usdc.balanceOf(cellar.address);

      tx = await cellar["deposit(address,uint256,uint256,address)"](
        dai.address,
        Num(100, 18),
        Num(95, 6),
        owner.address
      );

      const updatedUserBalance = await dai.balanceOf(owner.address);
      const updatedCellarBalance = await usdc.balanceOf(cellar.address);

      // expect $100 to have been transferred from owner
      expect(initialUserBalance.sub(updatedUserBalance)).to.eq(Num(100, 18));
      // expect at least $95 to have been received by cellar
      expect(updatedCellarBalance.sub(initialCellarBalance)).to.be.at.least(Num(95, 6));

      // expect shares to be minted to owner as if they deposited $95 even though
      // they deposited $100 (because that is what the cellar received after swap)
      expect(await cellar.balanceOf(owner.address)).to.be.at.least(Num(95, 18));
    });

    it("should mint shares to receiver instead of caller if specified", async () => {
      // owner mints to alice
      await cellar["deposit(uint256,address)"](
        Num(100, 6),
        alice.address
      );
      // expect alice receives 100 shares
      expect(await cellar.balanceOf(alice.address)).to.eq(Num(100, 18));
      // expect owner receives no shares
      expect(await cellar.balanceOf(owner.address)).to.eq(0);
    });
    
    it("should deposit all user's balance if tries to deposit more than they have", async () => {
      // owner has $1000 to deposit, withdrawing $5000 should only withdraw $1000
      await cellar["deposit(uint256)"](Num(5000, 6));
      expect(await usdc.balanceOf(owner.address)).to.eq(0);
      expect(await usdc.balanceOf(cellar.address)).to.eq(Num(1000, 6));
    });

    it("should emit Deposit event", async () => {
      await cellar.connect(alice)["deposit(uint256)"](Num(1000, 6));
      
      await cellar.enterStrategy();
      
      await expect(
        cellar["deposit(uint256,address)"](
          Num(2000, 6),
          alice.address
        )
      )
        .to.emit(cellar, "Deposit")
        .withArgs(
          owner.address,
          alice.address,
          usdc.address,
          Num(1000, 6),
          '999999999000000000999'
        );
    });
  });

  describe("withdraw", () => {
    beforeEach(async () => {
      // both owner and alice should start off owning 50% of the cellar's total assets each
      await cellar["deposit(uint256)"](Num(100, 6));
      await cellar
        .connect(alice)
        ["deposit(uint256)"](Num(100, 6));
    });

    it("should withdraw correctly when called with all inactive shares", async () => {
      const ownerInitialBalance = await usdc.balanceOf(owner.address);
      // owner should be able redeem all shares for initial $100 (50% of total)
      await cellar["withdraw(uint256)"](Num(1000, 6));
      const ownerUpdatedBalance = await usdc.balanceOf(owner.address);
      // expect owner receives desired amount of tokens
      expect(ownerUpdatedBalance.sub(ownerInitialBalance)).to.eq(Num(100, 6));
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceInitialBalance = await usdc.balanceOf(alice.address);
      // alice should be able redeem all shares for initial $100 (50% of total)
      await cellar
        .connect(alice)
        ["withdraw(uint256)"](Num(100, 6));
      const aliceUpdatedBalance = await usdc.balanceOf(alice.address);
      // expect alice receives desired amount of tokens
      expect(aliceUpdatedBalance.sub(aliceInitialBalance)).to.eq(Num(100, 6));
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw correctly when called with all active shares", async () => {
      // convert all inactive assets -> active assets
      await cellar.enterStrategy();

      await timetravel(864000); // 10 day

      // owner should be able redeem all shares
      await cellar["withdraw(uint256)"](Num(1000.072863, 6));

      // expect owner receives desired amount of tokens
      expect(await usdc.balanceOf(owner.address)).to.eq(Num(1000.072863, 6));
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      // alice should be able redeem all shares
      await cellar
        .connect(alice)
        ["withdraw(uint256)"](Num(1000.072863, 6));

      // expect alice receives desired amount of tokens
      expect(await usdc.balanceOf(alice.address)).to.eq(Num(1000.072863, 6));
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw correctly when called with active and inactive shares", async () => {
      // convert all inactive assets -> active assets
      await cellar.enterStrategy();

      await timetravel(864000); // 10 day

      // owner adds $100 of inactive assets
      await cellar["deposit(uint256)"](Num(100, 6));
      // alice adds $75 of inactive assets
      await cellar
        .connect(alice)
        ["deposit(uint256)"](Num(75, 6));

      // owner should be able redeem all shares for $200.072898 ($100.072864 active + $100 inactive)
      await cellar["withdraw(uint256)"](Num(1000.072863, 6));

      // expect owner receives desired amount of tokens
      expect(await usdc.balanceOf(owner.address)).to.eq(Num(1000.072863, 6));
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      // alice should be able redeem all shares for $175.072864 ($100.072864 active + $75 inactive)
      await cellar
        .connect(alice)
        ["withdraw(uint256)"](Num(1000.072863, 6));

      // expect alice receives desired amount of tokens
      expect(await usdc.balanceOf(alice.address)).to.eq(Num(1000.072863, 6));
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw all user's assets if tries to withdraw more than they have", async () => {
      const aliceInitialBalance = await usdc.balanceOf(alice.address);

      await cellar["withdraw(uint256)"](Num(100, 6));
      // owner should now have nothing left to withdraw
      expect(await cellar.balanceOf(owner.address)).to.eq(0);
      await expect(cellar["withdraw(uint256)"](1)).to.be.revertedWith(
        "ZeroShares()"
      );

      // alice only has $100 to withdraw, withdrawing $150 should only withdraw $100
      await cellar.connect(alice)["withdraw(uint256)"](Num(150, 6));
      expect(await usdc.balanceOf(alice.address)).to.eq(Num(1000, 6));
    });

    it("should not allow unapproved 3rd party to withdraw using another's shares", async () => {
      // owner tries to withdraw alice's shares without approval (expect revert)
      await expect(
        cellar["withdraw(uint256,address,address)"](
          Num(100, 6),
          owner.address,
          alice.address
        )
      ).to.be.reverted;

      cellar.connect(alice).approve(Num(100, 6));

      // owner tries again after alice approved owner to withdraw $100 (expect pass)
      await expect(
        cellar["withdraw(uint256,address,address)"](
          Num(100, 6),
          owner.address,
          alice.address
        )
      ).to.be.reverted;

      // owner tries to withdraw another $100 (expect revert)
      await expect(
        cellar["withdraw(uint256,address,address)"](
          Num(100, 6),
          owner.address,
          alice.address
        )
      ).to.be.reverted;
    });

    it("should emit Withdraw event", async () => {
      await cellar.enterStrategy();

      await expect(
        cellar["withdraw(uint256,address,address)"](
          Num(2000, 6),
          alice.address,
          owner.address
        )
      )
        .to.emit(cellar, "Withdraw")
        .withArgs(
          alice.address,
          owner.address,
          usdc.address,
          Num(100, 6),
          Num(100, 18)
        );
    });
  });

  describe("transfer", () => {
    it("should correctly update deposit accounting upon transferring shares", async () => {
      // deposit $100 -> 100 shares
      await cellar["deposit(uint256)"](Num(100, 6));
      const depositTimestamp = await timestamp();

      const aliceOldBalance = await cellar.balanceOf(alice.address);
      await cellar.transfer(alice.address, Num(25, 18));
      const aliceNewBalance = await cellar.balanceOf(alice.address);

      expect(aliceNewBalance.sub(aliceOldBalance)).to.eq(Num(25, 18));

      const ownerDeposit = await cellar.userDeposits(owner.address, 0);
      const aliceDeposit = await cellar.userDeposits(alice.address, 0);

      expect(ownerDeposit[0]).to.eq(Num(75, 18)); // expect 75 assets
      expect(ownerDeposit[1]).to.eq(Num(75, 18)); // expect 75 shares
      expect(ownerDeposit[2]).to.eq(depositTimestamp);
      expect(aliceDeposit[0]).to.eq(Num(25, 18)); // expect 25 assets
      expect(aliceDeposit[1]).to.eq(Num(25, 18)); // expect 25 shares
      expect(aliceDeposit[2]).to.eq(depositTimestamp);
    });
    
    it("should allow withdrawing of transferred shares", async () => {
      await cellar["deposit(uint256)"](Num(100, 6));
      
      await cellar.transfer(alice.address, Num(100, 18));

      await cellar.enterStrategy();
      await timetravel(864000); // 10 day
      
      await cellar.connect(alice)["deposit(uint256)"](Num(100, 6));

      const aliceOldBalance = await usdc.balanceOf(alice.address);
      await cellar.connect(alice)["withdraw(uint256)"](Num(125 + 100, 6));
      const aliceNewBalance = await usdc.balanceOf(alice.address);

      expect(await cellar.balanceOf(alice.address)).to.eq(0);
      expect(aliceNewBalance.sub(aliceOldBalance)).to.eq(Num(200.072863, 6));
    });

    it("should require approval for transferring other's shares", async () => {
      await cellar.connect(alice)["deposit(uint256)"](Num(100, 6));
      await cellar.connect(alice).approve(owner.address, Num(50, 6));

      await cellar.transferFrom(alice.address, owner.address, Num(50, 6));
      await expect(cellar.transferFrom(alice.address, owner.address, Num(200, 6))).to.be
        .reverted;
    });
  });

  describe("enterStrategy", () => {
    beforeEach(async () => {
      // owner adds $100 of inactive assets
      await cellar["deposit(uint256)"](Num(100, 6));

      // alice adds $100 of inactive assets
      await cellar
        .connect(alice)
        ["deposit(uint256)"](Num(100, 6));

      // enter all $200 of inactive assets into a strategy
      await cellar.enterStrategy();
    });

    it("should deposit cellar inactive assets into Aave", async () => {
      expect(await usdc.balanceOf(cellar.address)).to.eq(0);
      // because balances accumulate
      expect(await usdc.balanceOf(aUSDC.address)).to.eq(670895918737604);
    });

    it("should return correct amount of aTokens to cellar", async () => {
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(
        Num(200, 6) // TODO: Expected "199999999" to be equal 200000000
      );
    });

    it("should not allow deposit if cellar does not have enough liquidity", async () => {
      // cellar tries to enter strategy with $100 it does not have
      await expect(cellar.enterStrategy()).to.be.reverted;
    });

    it("should emit DepositToAave event", async () => {
      await cellar["deposit(uint256)"](Num(200, 6));

      await expect(cellar.enterStrategy())
        .to.emit(cellar, "DepositToAave")
        .withArgs(usdc.address, Num(200, 6));
    });
  });

  describe("claimAndUnstake", () => {
    beforeEach(async () => {
      // owner adds $100 of inactive assets
      await cellar["deposit(uint256)"](Num(100, 6));

      // alice adds $100 of inactive assets
      await cellar
        .connect(alice)
        ["deposit(uint256)"](Num(100, 6));

      // enter all $200 of inactive assets into a strategy
      await cellar.enterStrategy();

      await timetravel(864000); // 10 day

      await cellar["claimAndUnstake()"]();
    });

    it("should claim rewards from Aave and begin unstaking", async () => {
      // expect cellar to claim all 100 stkAAVE
      expect(await stkAAVE.balanceOf(cellar.address)).to.eq('126337316069221');
    });

    it("should have started 10 day unstaking cooldown period", async () => {
      expect(await stkAAVE.stakersCooldowns(cellar.address)).to.eq(
        await timestamp()
      );
    });
  });

  describe("reinvest", () => {
    beforeEach(async () => {
      // owner adds $100 of inactive assets
      await cellar["deposit(uint256)"](Num(100, 6));

      // alice adds $100 of inactive assets
      await cellar
        .connect(alice)
        ["deposit(uint256)"](Num(100, 6));

      // enter all $200 of inactive assets into a strategy
      await cellar.enterStrategy();
      
      await timetravel(864000); // 10 day
      
      // cellar claims rewards and begins the 10 day cooldown period
      await cellar["claimAndUnstake()"]();

      await timetravel(864000); // 10 day

      await cellar["reinvest(uint256)"](0);
    });

    it("should reinvested rewards back into principal", async () => {
      expect(await stkAAVE.balanceOf(cellar.address)).to.eq(0);
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(200329767);
    });
  });

  describe("rebalance", () => {
    beforeEach(async () => {
      await cellar["deposit(uint256)"](Num(1000, 6));
      await cellar.enterStrategy();
    });

    it("should rebalance all usdc liquidity in dai", async () => {
      expect(await dai.balanceOf(cellar.address)).to.eq(0);
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(Num(1000, 6));

      await cellar.rebalance(dai.address, Num(950, 18));

      expect(await aUSDC.balanceOf(cellar.address)).to.eq(0);
      expect(await aDAI.balanceOf(cellar.address)).to.be.at.least(Num(950, 18));
    });
    
    it("should not be possible to rebalance to the same token", async () => {
      await expect(cellar.rebalance(usdc.address, 0)).to.be.revertedWith(
          "SameLendingToken"
      );
    });
  });

  describe("fees", () => {
    it("should accrue platform fees", async () => {
      // owner deposits $1000
      await cellar["deposit(uint256)"](Num(1000, 6));

      // convert all inactive assets -> active assets
      await cellar.enterStrategy();
      await timetravel(86400); // 1 day

      await cellar.accruePlatformFees();

      // ~$0.027 worth of shares in fees = $1000 * 86400 sec * (1% / secsPerYear)
      expect(await cellar.balanceOf(cellar.address)).to.be.closeTo(
        '27000000000000000',
        '1000000000000000'
      );
    });
    
    it("should accrue performance fees upon withdraw", async () => {
      // owner deposits $1000
      await cellar["deposit(uint256)"](Num(1000, 6));

      // convert all inactive assets -> active assets
      await cellar.enterStrategy();
      await timetravel(864000); // 10 day

      // should allow users to withdraw from holding pool
      await cellar["withdraw(uint256)"](Num(1250, 6));

      expect(await usdc.balanceOf(owner.address)).to.eq(1000728631);
      // expect cellar to have received $0.03643155 fees in shares = 0.728631$ gain * 5%
      expect(await cellar.balanceOf(cellar.address)).to.eq('36431550000000000'); // TODO: Expected "38319609625809196" to be equal 36431550000000000
    });
    
    it("should be able to transfer fees to Cosmos", async () => {
      // owner deposits $1000
      await cellar["deposit(uint256)"](Num(1000, 6));

      await cellar.enterStrategy();
      await timetravel(86400); // 1 day

      // accrue some platform fees
      await cellar.accruePlatformFees();

      // accrue some performance fees
      await cellar.connect(alice)["deposit(uint256)"](Num(1000, 6));

      await cellar.enterStrategy();
      await timetravel(864000); // 10 day

      await cellar.connect(alice)["withdraw(uint256)"](Num(1250, 6));

      const fees = await cellar.balanceOf(cellar.address);
      const feeInAssets = await cellar.convertToAssets(fees);

      await cellar.transferFees(); // TODO: Error: Transaction reverted: function call to a non-contract account

      // expect all fee shares to be transferred out
      expect(await cellar.balanceOf(cellar.address)).to.eq(0);
      expect(await usdc.balanceOf(gravity.address)).to.eq(feeInAssets);
    });
  });

  describe("pause", () => {
    it("should prevent users from depositing while paused", async () => {
      await cellar.setPause(true);
      expect(cellar["deposit(uint256)"](Num(100, 6))).to.be.revertedWith(
        "ContractPaused()"
      );
    });

    it("should emits a Pause event", async () => {
      await expect(cellar.setPause(true))
        .to.emit(cellar, "Pause")
        .withArgs(owner.address, true);
    });
  });

  describe("shutdown", () => {
    it("should prevent users from depositing while shutdown", async () => {
      await cellar["deposit(uint256)"](Num(100, 6));
      await cellar.shutdown();
      expect(cellar["deposit(uint256)"](Num(100, 6))).to.be.revertedWith(
        "ContractShutdown()"
      );
    });

    it("should allow users to withdraw", async () => {
      // alice first deposits
      await cellar.connect(alice)["deposit(uint256)"](Num(100, 6));

      // cellar is shutdown
      await cellar.shutdown();

      await cellar.connect(alice)["withdraw(uint256)"](Num(100, 6));
    });

    it("should withdraw all active assets from Aave", async () => {
      await cellar["deposit(uint256)"](Num(1000, 6));

      await cellar.enterStrategy();
      await timetravel(864000); // 10 day
      
      await cellar.shutdown();

      // expect all of active liquidity to be withdrawn from Aave
      expect(await usdc.balanceOf(cellar.address)).to.eq(Num(1000.766980, 6));

      // should allow users to withdraw from holding pool
      await cellar["withdraw(uint256)"](Num(1000.766980, 6));
      
      expect(await usdc.balanceOf(cellar.address)).to.eq(38349);
    });

    it("should emit a Shutdown event", async () => {
      await expect(cellar.shutdown())
        .to.emit(cellar, "Shutdown")
        .withArgs(owner.address);
    });
  });

  describe("restrictLiquidity", () => {
    it("should prevent deposit it greater than max liquidity", async () => {
      // set 200000 ETH to owner balance
      await network.provider.send("hardhat_setBalance", [
        owner.address,
        ethers.utils.parseEther("200000").toHexString(),
      ]);

      await swapRouter.exactOutputSingle(
        [
          wethAddress, // tokenIn
          usdc.address, // tokenOut
          3000, // fee
          owner.address, // recipient
          1657479474, // deadline
          Num(5_000_000, 6), // amountOut
          ethers.utils.parseEther("150000"), // amountInMaximum
          0, // sqrtPriceLimitX96
        ],
        { value: ethers.utils.parseEther("150000") }
      );

      // transfer to cellar $5,000,000
      await usdc.transfer(cellar.address, Num(5_000_000, 6));

      await expect(cellar["deposit(uint256)"](1)).to.be.revertedWith(
        `LiquidityRestricted(${Num(5_000_000, 6)})`
      );
    });

    it("should prevent deposit it greater than max deposit", async () => {
      // set 100000 ETH to owner balance
      await network.provider.send("hardhat_setBalance", [
        owner.address,
        ethers.utils.parseEther("100000").toHexString(),
      ]);

      await swapRouter.exactOutputSingle(
        [
          wethAddress, // tokenIn
          usdc.address, // tokenOut
          3000, // fee
          owner.address, // recipient
          1657479474, // deadline
          Num(100_000, 6), // amountOut
          ethers.utils.parseEther("50000"), // amountInMaximum
          0, // sqrtPriceLimitX96
        ],
        { value: ethers.utils.parseEther("50000") }
      );

      await usdc.approve(
        cellar.address,
        Num(100_000, 6)
      );
      
      // owner deposits $5,000,000
      await expect(
        cellar["deposit(uint256)"](
          Num(50_001, 6)
        )
      ).to.be.revertedWith(
        `DepositRestricted(${Num(50_000, 6)})`
      );
      
      await cellar["deposit(uint256)"](Num(50_000, 6));
      await expect(cellar["deposit(uint256)"](1)).to.be.revertedWith(
        `DepositRestricted(${Num(50_000, 6)})`
      );
    });
    
    it("should allow deposits above max liquidity once restriction removed", async () => {
      // set 200000 ETH to owner balance
      await network.provider.send("hardhat_setBalance", [
        owner.address,
        ethers.utils.parseEther("200000").toHexString(),
      ]);

      await swapRouter.exactOutputSingle(
        [
          wethAddress, // tokenIn
          usdc.address, // tokenOut
          3000, // fee
          owner.address, // recipient
          1657479474, // deadline
          Num(5_000_000, 6), // amountOut
          ethers.utils.parseEther("150000"), // amountInMaximum
          0, // sqrtPriceLimitX96
        ],
        { value: ethers.utils.parseEther("150000") }
      );

      // transfer to cellar $5,000,000
      await usdc.transfer(cellar.address, Num(5_000_000, 6));

      await cellar.removeLiquidityRestriction();

      await cellar["deposit(uint256)"](Num(50_001, 6));
    });
  });
  
  describe("sweep", () => {
    beforeEach(async () => {
      await swapRouter.exactOutputSingle(
        [
          wethAddress, // tokenIn
          hex.address, // tokenOut
          3000, // fee
          owner.address, // recipient
          1657479474, // deadline
          Num(1000, 8), // amountOut
          ethers.utils.parseEther("10"), // amountInMaximum
          0, // sqrtPriceLimitX96
        ],
        { value: ethers.utils.parseEther("10") }
      );

      await hex.transfer(cellar.address, Num(1000, 8));
    });

    it("should not allow assets managed by cellar to be transferred out", async () => {
      await expect(cellar.sweep(usdc.address)).to.be.revertedWith(
        `ProtectedToken("${usdc.address}")`
      );
      await expect(cellar.sweep(aUSDC.address)).to.be.revertedWith(
        `ProtectedToken("${aUSDC.address}")`
      );
    });

    it("should recover tokens accidentally transferred to the contract", async () => {
      expect(await hex.balanceOf(owner.address)).to.eq(0);
      
      await cellar.sweep(hex.address);

      // expect 1000 hex to have been transferred from cellar to owner
      expect(await hex.balanceOf(owner.address)).to.eq(Num(1000, 8));
      expect(await hex.balanceOf(cellar.address)).to.eq(0);
    });

    it("should emit Sweep event", async () => {
      await expect(cellar.sweep(hex.address))
        .to.emit(cellar, "Sweep")
        .withArgs(hex.address, Num(1000, 8));
    });
  });
});
