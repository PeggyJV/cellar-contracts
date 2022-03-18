const hre = require("hardhat");
const { expect } = require("chai");
const { BigNumber } = require("ethers");
const ethers = hre.ethers;

describe("AaveStablecoinCellar", () => {
  let owner;
  let alice;

  let usdc;
  let usdt;
  let dai;
  let weth;
  let aave;

  let aUSDC;
  let aDAI;

  let swapRouter;
  let cellar;
  let lendingPool;
  let incentivesController;
  let stkAAVE;
  let dataProvider;

  let tx;

  // addresses of smart contracts in the mainnet
  const routerAddress = "0xE592427A0AEce92De3Edee1F18E0157C05861564"; // Uniswap V3 SwapRouter
  const lendingPoolAddress = "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9"; // Aave LendingPool
  const dataProviderAddress = "0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d"; // AaveProtocolDataProvider
  const incentivesControllerAddress =
    "0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5"; // StakedTokenIncentivesController
  const stkAAVEAddress = "0x4da27a545c0c5B758a6BA100e3a049001de870f5"; // StakedTokenV2Rev3

  // addresses of tokens in the mainnet
  const aaveAddress = "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9";
  const usdcAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
  const usdtAddress = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
  const daiAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
  const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const aUSDCAddress = "0xBcca60bB61934080951369a648Fb03DF4F96263C";
  const aDAIAddress = "0x028171bCA77440897B824Ca71D1c56caC55b68A3";

  const timetravel = async (addTime) => {
    await network.provider.send("evm_increaseTime", [addTime]);
    await network.provider.send("evm_mine");
  };

  beforeEach(async () => {
    [owner, alice] = await ethers.getSigners();

    // set 1000 ETH to owner balance
    await network.provider.send("hardhat_setBalance", [
      owner.address,
      ethers.utils.parseEther("1000").toHexString(),
    ]);

    // set 1000 ETH to alice balance
    await network.provider.send("hardhat_setBalance", [
      alice.address,
      ethers.utils.parseEther("1000").toHexString(),
    ]);

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

    // WETH contract
    weth = new ethers.Contract(
      wethAddress,
      [
        "function deposit() external payable",
        "function transfer(address to, uint value) external returns (bool)",
        "function withdraw(uint256 value) external payable",
        "function balanceOf(address account) external view returns (uint256)",
        "function approve(address spender, uint256 amount) external returns (bool)",
      ],
      owner
    );

    // test weth.deposit
    await weth.deposit({ value: ethers.utils.parseEther("10") });

    // WETH contract
    weth = new ethers.Contract(
      wethAddress,
      [
        "function deposit() external payable",
        "function transfer(address to, uint value) external returns (bool)",
        "function withdraw(uint256 value) external payable",
        "function balanceOf(address account) external view returns (uint256)",
        "function approve(address spender, uint256 amount) external returns (bool)",
      ],
      alice
    );

    // test weth.deposit
    await weth.deposit({ value: ethers.utils.parseEther("10") });

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

    dataProvider = await ethers.getContractAt(
      "IAaveProtocolDataProvider",
      dataProviderAddress
    );

    await swapRouter.exactInputSingle(
      [
        weth.address, // tokenIn
        usdt.address, // tokenOut
        3000, // fee
        owner.address, // recipient
        1647479474, // deadline
        ethers.utils.parseEther("10"), // amountIn
        0, // amountOutMinimum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    await swapRouter.exactInputSingle(
      [
        weth.address, // tokenIn
        usdt.address, // tokenOut
        3000, // fee
        alice.address, // recipient
        1647479474, // deadline
        ethers.utils.parseEther("10"), // amountIn
        0, // amountOutMinimum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    await swapRouter.exactOutputSingle(
      [
        weth.address, // tokenIn
        usdc.address, // tokenOut
        3000, // fee
        owner.address, // recipient
        1647479474, // deadline
        ethers.BigNumber.from(10).pow(6).mul(1000), // amountOut
        ethers.utils.parseEther("10"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    await swapRouter.exactOutputSingle(
      [
        weth.address, // tokenIn
        dai.address, // tokenOut
        3000, // fee
        owner.address, // recipient
        1647479474, // deadline
        ethers.BigNumber.from(10).pow(18).mul(1000), // amountOut
        ethers.utils.parseEther("10"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    await swapRouter.exactOutputSingle(
      [
        weth.address, // tokenIn
        usdc.address, // tokenOut
        3000, // fee
        alice.address, // recipient
        1647479474, // deadline
        ethers.BigNumber.from(10).pow(6).mul(1000), // amountOut
        ethers.utils.parseEther("10"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    await swapRouter.exactOutputSingle(
      [
        weth.address, // tokenIn
        dai.address, // tokenOut
        3000, // fee
        alice.address, // recipient
        1647479474, // deadline
        ethers.BigNumber.from(10).pow(6).mul(1000), // amountOut
        ethers.utils.parseEther("10"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    // Deploy cellar contract
    const AaveStablecoinCellar = await ethers.getContractFactory(
      "AaveStablecoinCellar"
    );

    cellar = await AaveStablecoinCellar.deploy(
      routerAddress,
      lendingPoolAddress,
      dataProviderAddress,
      incentivesControllerAddress,
      stkAAVEAddress,
      aaveAddress,
      weth.address,
      usdc.address,
      usdc.address,
      "Sommelier Aave Stablecoin Cellar LP Token",
      "SASCT"
    );
    await cellar.deployed();

    await cellar.setInputToken(weth.address, true);
    await cellar.setInputToken(usdc.address, true);
    await cellar.setInputToken(usdt.address, true);
    await cellar.setInputToken(dai.address, true);

    await weth.approve(
      cellar.address,
      ethers.BigNumber.from(10).pow(18).mul(10000)
    );
    await usdc.approve(
      cellar.address,
      ethers.BigNumber.from(10).pow(6).mul(10000)
    );
    await usdt.approve(
      cellar.address,
      ethers.BigNumber.from(10).pow(6).mul(10000)
    );
    await dai.approve(
      cellar.address,
      ethers.BigNumber.from(10).pow(18).mul(10000)
    );

    await usdc
      .connect(alice)
      .approve(cellar.address, ethers.BigNumber.from(10).pow(6).mul(10000));
    await dai
      .connect(alice)
      .approve(cellar.address, ethers.BigNumber.from(10).pow(18).mul(10000));
    await weth
      .connect(alice)
      .approve(cellar.address, ethers.BigNumber.from(10).pow(18).mul(10000));
    await usdt
      .connect(alice)
      .approve(cellar.address, ethers.BigNumber.from(10).pow(6).mul(10000));

    // balances accumulate every test
  });

  describe("deposit", () => {
    it("should mint correct amount of shares to user", async () => {
      // add $100 of inactive assets in cellar
      await cellar["deposit(uint256)"](
        ethers.BigNumber.from(10).pow(6).mul(100)
      );
      // expect 100 shares to be minted (because total supply of shares is 0)
      expect(await cellar.balanceOf(owner.address)).to.eq(
        ethers.BigNumber.from(10).pow(6).mul(100)
      );

      // add $50 of inactive assets in cellar
      await cellar
        .connect(alice)
        ["deposit(uint256)"](ethers.BigNumber.from(10).pow(6).mul(50));
      // expect 50 shares = 100 total shares * ($50 / $100) to be minted
      expect(await cellar.balanceOf(alice.address)).to.eq(
        ethers.BigNumber.from(10).pow(6).mul(50)
      );
    });

    it("should transfer input token from user to cellar", async () => {
      const initialUserBalance = await usdc.balanceOf(owner.address);
      const initialCellarBalance = await usdc.balanceOf(cellar.address);

      await cellar["deposit(uint256)"](
        ethers.BigNumber.from(10).pow(6).mul(100)
      );

      const updatedUserBalance = await usdc.balanceOf(owner.address);
      const updatedCellarBalance = await usdc.balanceOf(cellar.address);

      // expect $100 to have been transferred from owner to cellar
      expect(initialUserBalance.sub(updatedUserBalance)).to.eq(
        ethers.BigNumber.from(10).pow(6).mul(100)
      );
      expect(updatedCellarBalance.sub(initialCellarBalance)).to.eq(
        ethers.BigNumber.from(10).pow(6).mul(100)
      );
    });

    it("should swap input token for current lending token if not already", async () => {
      const initialUserBalance = await dai.balanceOf(owner.address);
      const initialCellarBalance = await usdc.balanceOf(cellar.address);

      tx = await cellar["deposit(address,uint256,uint256,address)"](
        dai.address,
        ethers.BigNumber.from(10).pow(18).mul(100),
        ethers.BigNumber.from(10).pow(6).mul(95),
        owner.address
      );

      const updatedUserBalance = await dai.balanceOf(owner.address);
      const updatedCellarBalance = await usdc.balanceOf(cellar.address);

      // expect $100 to have been transferred from owner
      expect(initialUserBalance.sub(updatedUserBalance)).to.eq(
        ethers.BigNumber.from(10).pow(18).mul(100)
      );
      // expect at least $95 to have been received by cellar
      expect(updatedCellarBalance.sub(initialCellarBalance)).to.be.at.least(
        ethers.BigNumber.from(10).pow(6).mul(95)
      );

      // expect shares to be minted to owner as if they deposited $95 even though
      // they deposited $100 (because that is what the cellar received after swap)
      expect(await cellar.balanceOf(owner.address)).to.be.at.least(
        ethers.BigNumber.from(10).pow(6).mul(95)
      );
    });

    it("should mint shares to receiver instead of caller if specified", async () => {
      // owner mints to alice
      await cellar["deposit(uint256,address)"](
        ethers.BigNumber.from(10).pow(6).mul(100),
        alice.address
      );
      // expect alice receives 100 shares
      expect(await cellar.balanceOf(alice.address)).to.eq(
        ethers.BigNumber.from(10).pow(6).mul(100)
      );
      // expect owner receives no shares
      expect(await cellar.balanceOf(owner.address)).to.eq(0);
    });

    it("should deposit all user's balance if tries to deposit more than they have", async () => {
      const initialUserBalance = await usdc.balanceOf(owner.address);

      // owner deposits $1000 more than he has.
      // only what he had on his balance sheet should be deposited
      await cellar["deposit(uint256)"](
        initialUserBalance.add(ethers.BigNumber.from(10).pow(6).mul(1000))
      );
      expect(await usdc.balanceOf(owner.address)).to.eq(0);
      expect(await usdc.balanceOf(cellar.address)).to.eq(initialUserBalance);
    });

    it("should emit Deposit event", async () => {
      await expect(
        cellar["deposit(uint256,address)"](
          ethers.BigNumber.from(10).pow(6).mul(100),
          alice.address
        )
      )
        .to.emit(cellar, "Deposit")
        .withArgs(
          owner.address,
          alice.address,
          ethers.BigNumber.from(10).pow(6).mul(100),
          ethers.BigNumber.from(10).pow(6).mul(100)
        );
    });
  });

  describe("depositAndEnter", () => {
    it("should deposit directly into Aave strategy", async () => {
      await cellar.depositAndEnter(
        usdc.address,
        ethers.BigNumber.from(10).pow(6).mul(1000),
        ethers.BigNumber.from(10).pow(6).mul(1000),
        owner.address
      );
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(
        ethers.BigNumber.from(10).pow(6).mul(1000)
      );
    });
  });

  describe("withdraw", () => {
    beforeEach(async () => {
      // both owner and alice should start off owning 50% of the cellar's total assets each
      await cellar["deposit(uint256)"](
        ethers.BigNumber.from(10).pow(6).mul(100)
      );
      await cellar
        .connect(alice)
        ["deposit(uint256)"](ethers.BigNumber.from(10).pow(6).mul(100));
    });

    it("should withdraw correctly when called with all inactive shares", async () => {
      const ownerInitialBalance = await usdc.balanceOf(owner.address);
      // owner should be able redeem all shares for initial $100 (50% of total)
      await cellar["withdraw(uint256)"](
        ethers.BigNumber.from(10).pow(6).mul(1000)
      );
      const ownerUpdatedBalance = await usdc.balanceOf(owner.address);
      // expect owner receives desired amount of tokens
      expect(ownerUpdatedBalance.sub(ownerInitialBalance)).to.eq(
        ethers.BigNumber.from(10).pow(6).mul(100)
      );
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceInitialBalance = await usdc.balanceOf(alice.address);
      // alice should be able redeem all shares for initial $100 (50% of total)
      await cellar
        .connect(alice)
        ["withdraw(uint256)"](ethers.BigNumber.from(10).pow(6).mul(100));
      const aliceUpdatedBalance = await usdc.balanceOf(alice.address);
      // expect alice receives desired amount of tokens
      expect(aliceUpdatedBalance.sub(aliceInitialBalance)).to.eq(
        ethers.BigNumber.from(10).pow(6).mul(100)
      );
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw correctly when called with all active shares", async () => {
      // convert all inactive assets -> active assets
      await cellar.enterStrategy();

      // mimic growth from $200 -> $250 (1.25x increase) while in strategy
      await lendingPool.setLiquidityIndex(
        BigNumber.from("1250000000000000000000000000")
      );

      const ownerInitialBalance = await usdc.balanceOf(owner.address);
      // owner should be able redeem all shares for $125 (50% of total)
      await cellar["withdraw(uint256)"](
        ethers.BigNumber.from(10).pow(6).mul(125)
      );
      const ownerUpdatedBalance = await usdc.balanceOf(owner.address);
      // expect owner receives desired amount of tokens
      expect(ownerUpdatedBalance.sub(ownerInitialBalance)).to.eq(
        ethers.BigNumber.from(10).pow(6).mul(125)
      );
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceInitialBalance = await usdc.balanceOf(alice.address);
      // alice should be able redeem all shares for $125 (50% of total)
      await cellar
        .connect(alice)
        ["withdraw(uint256)"](ethers.BigNumber.from(10).pow(6).mul(125));
      const aliceUpdatedBalance = await usdc.balanceOf(alice.address);
      // expect alice receives desired amount of tokens
      expect(aliceUpdatedBalance.sub(aliceInitialBalance)).to.eq(
        ethers.BigNumber.from(10).pow(6).mul(125)
      );
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw correctly when called with active and inactive shares", async () => {
      // convert all inactive assets -> active assets
      await cellar.enterStrategy();

      // mimic growth from $200 -> $250 (1.25x increase) while in strategy
      await lendingPool.setLiquidityIndex(
        BigNumber.from("1250000000000000000000000000")
      );

      // owner adds $100 of inactive assets
      await cellar["deposit(uint256)"](
        ethers.BigNumber.from(10).pow(6).mul(100)
      );
      // alice adds $75 of inactive assets
      await cellar
        .connect(alice)
        ["deposit(uint256)"](ethers.BigNumber.from(10).pow(6).mul(75));

      const ownerInitialBalance = await usdc.balanceOf(owner.address);
      // owner should be able redeem all shares for $225 ($125 active + $100 inactive)
      await cellar["withdraw(uint256)"](
        ethers.BigNumber.from(10).pow(6).mul(225)
      );
      const ownerUpdatedBalance = await usdc.balanceOf(owner.address);
      // expect owner receives desired amount of tokens
      expect(ownerUpdatedBalance.sub(ownerInitialBalance)).to.eq(
        ethers.BigNumber.from(10).pow(6).mul(225)
      );
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceInitialBalance = await usdc.balanceOf(alice.address);
      // alice should be able redeem all shares for $200 ($125 active + $75 inactive)
      await cellar
        .connect(alice)
        ["withdraw(uint256)"](ethers.BigNumber.from(10).pow(6).mul(200));
      const aliceUpdatedBalance = await usdc.balanceOf(alice.address);
      // expect alice receives desired amount of tokens
      expect(aliceUpdatedBalance.sub(aliceInitialBalance)).to.eq(
        ethers.BigNumber.from(10).pow(6).mul(200)
      );
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should use and store index of first non-zero deposit", async () => {
      // owner withdraws everything from deposit object at index 0
      await cellar["withdraw(uint256)"](
        ethers.BigNumber.from(10).pow(6).mul(100)
      );
      // expect next non-zero deposit is set to index 1
      expect(await cellar.currentDepositIndex(owner.address)).to.eq(1);

      // alice only withdraws half from index 0, leaving some shares remaining
      await cellar
        .connect(alice)
        ["withdraw(uint256)"](ethers.BigNumber.from(10).pow(6).mul(50));
      // expect next non-zero deposit is set to index 0 since some shares still remain
      expect(await cellar.currentDepositIndex(alice.address)).to.eq(0);
    });

    it("should withraw all user's assets if tries to withdraw more than they have", async () => {
      await cellar["withdraw(uint256)"](
        ethers.BigNumber.from(10).pow(6).mul(100)
      );
      await expect(cellar["withdraw(uint256)"](1)).to.revertedWith(
        "NoNonemptyUserDeposits()"
      );

      await cellar
        .connect(alice)
        ["withdraw(uint256)"](ethers.BigNumber.from(10).pow(6).mul(150));
      // because balances accumulate
      expect(await usdc.balanceOf(alice.address)).to.eq(11700000000);
    });

    it("should not allow unapproved 3rd party to withdraw using another's shares", async () => {
      // owner tries to withdraw alice's shares without approval (expect revert)
      await expect(
        cellar["withdraw(uint256,address,address)"](
          ethers.BigNumber.from(10).pow(6).mul(100),
          owner.address,
          alice.address
        )
      ).to.be.reverted;

      cellar.connect(alice).approve(ethers.BigNumber.from(10).pow(6).mul(100));

      // owner tries again after alice approved owner to withdraw $100 (expect pass)
      await expect(
        cellar["withdraw(uint256,address,address)"](
          ethers.BigNumber.from(10).pow(6).mul(100),
          owner.address,
          alice.address
        )
      ).to.be.reverted;

      // owner tries to withdraw another $100 (expect revert)
      await expect(
        cellar["withdraw(uint256,address,address)"](
          ethers.BigNumber.from(10).pow(6).mul(100),
          owner.address,
          alice.address
        )
      ).to.be.reverted;
    });

    it("should emit Withdraw event", async () => {
      await expect(
        cellar["withdraw(uint256,address,address)"](
          ethers.BigNumber.from(10).pow(6).mul(100),
          alice.address,
          owner.address
        )
      )
        .to.emit(cellar, "Withdraw")
        .withArgs(
          owner.address,
          alice.address,
          owner.address,
          ethers.BigNumber.from(10).pow(6).mul(100),
          ethers.BigNumber.from(10).pow(6).mul(100)
        );
    });
  });

  describe("enterStrategy", () => {
    beforeEach(async () => {
      // owner adds $100 of inactive assets
      await cellar["deposit(uint256)"](
        ethers.BigNumber.from(10).pow(6).mul(100)
      );

      // alice adds $100 of inactive assets
      await cellar
        .connect(alice)
        ["deposit(uint256)"](ethers.BigNumber.from(10).pow(6).mul(100));

      // enter all $200 of inactive assets into a strategy
      await cellar.enterStrategy();
    });

    it("should deposit cellar inactive assets into Aave", async () => {
      expect(await usdc.balanceOf(cellar.address)).to.eq(0);
      // because balances accumulate
      expect(await usdc.balanceOf(aUSDC.address)).to.eq(670897318737604);
    });

    it("should return correct amount of aTokens to cellar", async () => {
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(
        ethers.BigNumber.from(10).pow(6).mul(200)
      );
    });

    it("should not allow deposit if cellar does not have enough liquidity", async () => {
      // cellar tries to enter strategy with $100 it does not have
      await expect(cellar.enterStrategy()).to.be.reverted;
    });

    it("should emit DepositToAave event", async () => {
      await cellar["deposit(uint256)"](
        ethers.BigNumber.from(10).pow(6).mul(200)
      );

      await expect(cellar.enterStrategy())
        .to.emit(cellar, "DepositToAave")
        .withArgs(usdc.address, ethers.BigNumber.from(10).pow(6).mul(200));
    });
  });
});
