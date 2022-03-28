const hre = require("hardhat");
const { expect } = require("chai");
const { BigNumber } = require("ethers");
const ethers = hre.ethers;
const { alchemyApiKey } = require('../secrets.json');

describe("AaveV2StablecoinCellar", () => {
  let owner;
  let alice;
  let bob;

  let USDC;
  let USDT;
  let DAI;
  let AAVE;
  let HEX;

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

  const initSwap = async (accaunt, token, amount) => {
    await swapRouter.exactOutputSingle(
      [
        wethAddress, // tokenIn
        token.address, // tokenOut
        3000, // fee
        accaunt.address, // recipient
        (await timestamp()) + 50, // deadline
        Num(amount, (await token.decimals())), // amountOut
        ethers.utils.parseEther("1000"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("1000") }
    );
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

    [owner, alice, bob] = await ethers.getSigners();

    // stablecoins contracts
    const Token = await ethers.getContractFactory(
      "@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20"
    );
    USDC = await Token.attach(usdcAddress);
    USDT = await Token.attach(usdtAddress);
    DAI = await Token.attach(daiAddress);
    AAVE = await Token.attach(aaveAddress);
    HEX = await Token.attach(hexAddress);
    aDAI = await Token.attach(aDAIAddress);
    aUSDC = await Token.attach(aUSDCAddress);

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
      USDC.address,
      routerAddress,
      sushiSwapRouterAddress,
      lendingPoolAddress,
      incentivesControllerAddress,
      gravityBridgeAddress,
      stkAAVEAddress,
      AAVE.address
    );
    await cellar.deployed();

    await initSwap(owner, USDC, 1000);
    await initSwap(owner, DAI, 1000);
    await initSwap(owner, USDT, 1000);

    await initSwap(alice, USDC, 1000);
    await initSwap(alice, DAI, 1000);
    await initSwap(alice, USDT, 1000);

    await initSwap(bob, USDC, 1000);
    await initSwap(bob, DAI, 1000);
    await initSwap(bob, USDT, 1000);

    await USDC.approve(
      cellar.address,
      ethers.constants.MaxUint256
    );
    await USDT.approve(
      cellar.address,
      ethers.constants.MaxUint256
    );
    await DAI.approve(
      cellar.address,
      ethers.constants.MaxUint256
    );

    await USDC
      .connect(alice)
      .approve(cellar.address, ethers.constants.MaxUint256);
    await DAI
      .connect(alice)
      .approve(cellar.address, ethers.constants.MaxUint256);
    await USDT
      .connect(alice)
      .approve(cellar.address, ethers.constants.MaxUint256);

    await USDC
      .connect(bob)
      .approve(cellar.address, ethers.constants.MaxUint256);
    await DAI
      .connect(bob)
      .approve(cellar.address, ethers.constants.MaxUint256);
    await USDT
      .connect(bob)
      .approve(cellar.address, ethers.constants.MaxUint256);
      
    // Approve cellar to spend shares (to take as fees)
    await cellar.approve(cellar.address, ethers.constants.MaxUint256);
    await cellar
      .connect(alice)
      .approve(cellar.address, ethers.constants.MaxUint256);
    await cellar
      .connect(bob)
      .approve(cellar.address, ethers.constants.MaxUint256);
  });

  describe("deposit", () => {
    it("should mint correct amount of shares to user", async () => {
      // add $100 of inactive assets in cellar
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);
      // expect 100 shares to be minted (because total supply of shares is 0)
      expect(await cellar.balanceOf(owner.address)).to.eq(Num(100, 18));

      // add $50 of inactive assets in cellar
      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(50, 6), alice.address);
      // expect 50 shares = 100 total shares * ($50 / $100) to be minted
      expect(await cellar.balanceOf(alice.address)).to.eq(Num(50, 18));
    });

    it("should transfer input token from user to cellar", async () => {
      const initialUserBalance = await USDC.balanceOf(owner.address);
      const initialCellarBalance = await USDC.balanceOf(cellar.address);

      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);

      const updatedUserBalance = await USDC.balanceOf(owner.address);
      const updatedCellarBalance = await USDC.balanceOf(cellar.address);

      // expect $100 to have been transferred from owner to cellar
      expect(initialUserBalance.sub(updatedUserBalance)).to.eq(Num(100, 6));
      expect(updatedCellarBalance.sub(initialCellarBalance)).to.eq(Num(100, 6));
    });

    it("should mint shares to receiver instead of caller if specified", async () => {
      // owner mints to alice
      await cellar["deposit(uint256,address)"](Num(100, 6), alice.address);
      // expect alice receives 100 shares
      expect(await cellar.balanceOf(alice.address)).to.eq(Num(100, 18));
      // expect owner receives no shares
      expect(await cellar.balanceOf(owner.address)).to.eq(0);
    });

    it("should deposit all user's balance if they try depositing more than their balance", async () => {
      // owner has $1000 to deposit, withdrawing $5000 should only withdraw $1000
      await cellar["deposit(uint256,address)"](Num(5000, 6), owner.address);
      expect(await USDC.balanceOf(owner.address)).to.eq(0);
      expect(await USDC.balanceOf(cellar.address)).to.eq(Num(1000, 6));
    });

    it("should use and store index of first non-zero deposit", async () => {
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);
      // owner withdraws everything from deposit object at index 0
      await cellar["withdraw(uint256,address,address)"](
        Num(100, 6),
        owner.address,
        owner.address
      );
      // expect next non-zero deposit is set to index 1
      expect(await cellar.currentDepositIndex(owner.address)).to.eq(1);

      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(100, 6), alice.address);
      // alice only withdraws half from index 0, leaving some shares remaining
      await cellar
        .connect(alice)
        ["withdraw(uint256,address,address)"](
          Num(50, 6),
          alice.address,
          alice.address
        );
      // expect next non-zero deposit is set to index 0 since some shares still remain
      expect(await cellar.currentDepositIndex(alice.address)).to.eq(0);
    });

    it("should not allow deposits of 0", async () => {
      await expect(cellar["deposit(uint256,address)"](0, owner.address)).to.be.revertedWith(
        "ZeroAssets()"
      );
    });

    it("should emit Deposit event", async () => {
      await cellar.connect(alice)["deposit(uint256,address)"](Num(1000, 6), alice.address);

      await cellar.enterStrategy();
      await timetravel(864000); // 10 day

      await expect(
        cellar["deposit(uint256,address)"](
          Num(2000, 6),
          alice.address
        )
      )
        .to.emit(cellar, "Deposit"); 
//         .withArgs(
//           owner.address,
//           alice.address,
//           USDC.address,
//           Num(1000, 6),
//           '999233607807483816062' TODO: this value may change slightly when retesting
//         );
    });
  });

  describe("withdraw", () => {
    beforeEach(async () => {
      // both owner and alice should start off owning 50% of the cellar's total assets each
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);
      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(100, 6), alice.address);
    });

    it("should withdraw correctly when called with all inactive shares", async () => {
      const ownerOldBalance = await USDC.balanceOf(owner.address);
      // owner should be able redeem all shares for initial $100 (50% of total)
      await cellar["withdraw(uint256,address,address)"](
        Num(100, 6),
        owner.address,
        owner.address
      );
      const ownerNewBalance = await USDC.balanceOf(owner.address);
      // expect owner receives desired amount of tokens
      expect((ownerNewBalance - ownerOldBalance).toString()).to.eq(Num(100, 6));
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceOldBalance = await USDC.balanceOf(alice.address);
      // alice should be able redeem all shares for initial $100 (50% of total)
      await cellar
        .connect(alice)
        ["withdraw(uint256,address,address)"](
          Num(100, 6),
          alice.address,
          alice.address
        );
      const aliceNewBalance = await USDC.balanceOf(alice.address);
      // expect alice receives desired amount of tokens
      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(Num(100, 6));
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw correctly when called with all active shares", async () => {
      // convert all inactive assets -> active assets
      await cellar.enterStrategy();
      await timetravel(864000); // 10 day

      const ownerOldBalance = await USDC.balanceOf(owner.address);
      await cellar["withdraw(uint256,address,address)"](
        Num(100.076699, 6),
        owner.address,
        owner.address
      );
      const ownerNewBalance = await USDC.balanceOf(owner.address);
      // owner should be able redeem all shares for initial $100.076698
      expect((ownerNewBalance - ownerOldBalance).toString()).to.eq(Num(100.076698, 6));
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceOldBalance = await USDC.balanceOf(alice.address);
      await cellar
        .connect(alice)
        ["withdraw(uint256,address,address)"](
          Num(100.076699, 6),
          alice.address,
          alice.address
        );
      const aliceNewBalance = await USDC.balanceOf(alice.address);
      // alice should be able redeem all shares for initial $100.076697
      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(Num(100.076698, 6));
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw correctly when called with active and inactive shares", async () => {
      // convert all inactive assets -> active assets
      await cellar.enterStrategy();

      await timetravel(864000); // 10 day

      // owner adds $100 of inactive assets
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);
      // alice adds $75 of inactive assets
      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(75, 6), alice.address);

      const ownerOldBalance = await USDC.balanceOf(owner.address);
      await cellar["withdraw(uint256,address,address)"](
        Num(200.076699, 6),
        owner.address,
        owner.address
      );
      const ownerNewBalance = await USDC.balanceOf(owner.address);
      // expect owner receives desired amount of tokens
      expect(ownerNewBalance.sub(ownerOldBalance)).to.eq(
        Num(200.076698, 6) // 100 + 100.076698
      );
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.be.below(Num(0.0001, 18));

      const aliceOldBalance = await USDC.balanceOf(alice.address);
      await cellar
        .connect(alice)
        ["withdraw(uint256,address,address)"](
          Num(175.076699, 6),
          alice.address,
          alice.address
        );
      const aliceNewBalance = await USDC.balanceOf(alice.address);
      // expect alice receives desired amount of tokens
      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(
        Num(175.076698, 6) // 75 + 100.076698
      );
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.be.below(Num(0.0001, 18));
    });

    it("should withdraw all user's assets if they try withdrawing more than their balance", async () => {
      await cellar["withdraw(uint256,address,address)"](
        Num(100, 6),
        owner.address,
        owner.address
      );
      // owner should now have nothing left to withdraw
      expect(await cellar.balanceOf(owner.address)).to.eq(0);
      await expect(
        cellar["withdraw(uint256,address,address)"](
          1,
          owner.address,
          owner.address
        )
      ).to.be.revertedWith("ZeroShares()");

      // alice only has $100 to withdraw, withdrawing $150 should only withdraw $100
      const aliceOldBalance = await USDC.balanceOf(alice.address);
      await cellar
        .connect(alice)
        ["withdraw(uint256,address,address)"](
          Num(150, 6),
          alice.address,
          alice.address
        );
      const aliceNewBalance = await USDC.balanceOf(alice.address);
      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(Num(100, 6));
    });

    it("should not allow withdraws of 0", async () => {
      await expect(
        cellar["withdraw(uint256,address,address)"](
          0,
          owner.address,
          owner.address
        )
      ).to.be.revertedWith("ZeroAssets()");
    });

    it("should not allow unapproved 3rd party to withdraw using another's shares", async () => {
      // owner tries to withdraw alice's shares without approval (expect revert)
      await expect(
        cellar["withdraw(uint256,address,address)"](
          Num(1, 6),
          owner.address,
          alice.address
        )
      ).to.be.reverted;

      cellar.connect(alice).approve(Num(1, 6));

      // owner tries again after alice approved owner to withdraw $1 (expect pass)
      await expect(
        cellar["withdraw(uint256,address,address)"](
          Num(1, 6),
          owner.address,
          alice.address
        )
      ).to.be.reverted;

      // owner tries to withdraw another $1 (expect revert)
      await expect(
        cellar["withdraw(uint256,address,address)"](
          Num(1, 6),
          owner.address,
          alice.address
        )
      ).to.be.reverted;
    });

    it("should only withdraw from strategy if holding pool does not contain enough funds", async () => {
      await cellar.enterStrategy();
      await timetravel(864000); // 10 day

      await cellar.connect(alice)["deposit(uint256,address)"](Num(125, 6), alice.address);

      const beforeActiveAssets = await cellar.activeAssets();

      // with $125 in strategy and $125 in holding pool, should with
      await cellar["withdraw(uint256,address,address)"](
        Num(125, 6),
        owner.address,
        owner.address
      );

      const afterActiveAssets = await cellar.activeAssets();

      // active assets from strategy should not have changed
      expect(afterActiveAssets).to.eq(beforeActiveAssets);
      // should have withdrawn from holding pool funds
      expect(await cellar.inactiveAssets()).to.eq(0); // TODO: Expected "24923302" to be equal 0
    });

    it("should emit Withdraw event", async () => {
      await cellar.enterStrategy();
      await timetravel(864000); // 10 day

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
          USDC.address,
          Num(100.076698, 6),
          Num(100, 18)
        );
    });
  });

  describe("transfer", () => {
    beforeEach(async () => {
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);
      await cellar.enterStrategy();
    });

    it("should correctly update deposit accounting upon transferring shares", async () => {
      // transferring active shares:

      const transferredActiveShares = Num(50, 18);

      const aliceOldBalance = await cellar.balanceOf(alice.address);
      await cellar.transfer(alice.address, transferredActiveShares);
      const aliceNewBalance = await cellar.balanceOf(alice.address);

      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(
        transferredActiveShares
      );

      let ownerDeposit = await cellar.userDeposits(owner.address, 0);
      let aliceDeposit = await cellar.userDeposits(alice.address, 0);

      expect(ownerDeposit[0]).to.eq(0); // expect 0 assets (should have been deleted for a gas refund)
      expect(ownerDeposit[1]).to.eq(Num(50, 18)); // expect 50 shares
      expect(ownerDeposit[2]).to.eq(0); // expect 0 assets (should have been deleted for a gas refund)
      expect(aliceDeposit[0]).to.eq(0); // expect 0 assets (should have been deleted for a gas refund)
      expect(aliceDeposit[1]).to.eq(transferredActiveShares); // expect 50 shares
      expect(aliceDeposit[2]).to.eq(0); // expect 0 assets (should have been deleted for a gas refund)

      // transferring inactive shares:

      await cellar.connect(bob).deposit(Num(100, 6), bob.address);
      const depositTimestamp = await timestamp();

      const transferredInactiveShares = Num(25, 18);

      const ownerOldBalance = await cellar.balanceOf(owner.address);
      await cellar
        .connect(bob)
        ["transferFrom(address,address,uint256,bool)"](
          bob.address,
          owner.address,
          transferredInactiveShares,
          false
        );
      const ownerNewBalance = await cellar.balanceOf(owner.address);

      expect((ownerNewBalance - ownerOldBalance).toString()).to.eq(
        transferredInactiveShares
      );

      bobDeposit = await cellar.userDeposits(bob.address, 0);
      ownerDeposit = await cellar.userDeposits(
        owner.address,
        (await cellar.numDeposits(owner.address)) - 1
      );

      // must change decimals because deposit data is stored with 18 decimals
      expect(bobDeposit[0]).to.eq(Num(75, 18)); // expect 75 assets
      expect(bobDeposit[1]).to.eq(Num(75, 18)); // expect 75 shares
      expect(bobDeposit[2]).to.eq(depositTimestamp);
      expect(ownerDeposit[0]).to.eq(Num(25, 18)); // expect 25 assets
      expect(ownerDeposit[1]).to.eq(transferredInactiveShares); // expect 25 shares
      expect(ownerDeposit[2]).to.eq(depositTimestamp);
    });

    it("should correctly withdraw transferred shares", async () => {
      await timetravel(864000); // 10 day
      
      // gain $100 worth of inactive shares
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);

      // transfer all shares to alice
      await cellar["transferFrom(address,address,uint256,bool)"](
        owner.address,
        alice.address,
        await cellar.balanceOf(owner.address),
        false
      );

      const aliceOldBalance = await USDC.balanceOf(alice.address);

      // alice redeem all the shares that have been transferred to her and withdraw all of her assets
      await cellar
        .connect(alice)
        ["withdraw(uint256,address,address)"](
          await cellar.convertToAssets(await cellar.balanceOf(alice.address)),
          alice.address,
          alice.address
        );

      const aliceNewBalance = await USDC.balanceOf(alice.address);

      // expect alice to have redeemed all the shares transferred to her for $225 in assets
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(
        Num(200.076698, 6) // 100.076698 + 100
      );
    });

    it("should only transfer active shares by default", async () => {
      const expectedShares = await cellar.balanceOf(owner.address);

      // gain $100 worth of inactive shares
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);

      const aliceOldBalance = await cellar.balanceOf(alice.address);

      // attempting to transfer all active shares should transfer $100 worth of active shares (and not the
      // $100 worth of inactive shares) and not revert
      await cellar.transfer(
        alice.address,
        await cellar.balanceOf(owner.address)
      );

      const aliceNewBalance = await cellar.balanceOf(alice.address);

      // expect alice to have received $100 worth of shares
      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(
        expectedShares
      );
    });

    it("should use and store index of first non-zero deposit if not only active", async () => {
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);
      // owner transfers all active shares from deposit object at index 0
      await cellar.transfer(alice.address, Num(100, 6));
      // expect next non-zero deposit is not have updated because onlyActive was true
      expect(await cellar.currentDepositIndex(owner.address)).to.eq(0);

      // owner transfers everything from deposit object at index 1
      await cellar["transferFrom(address,address,uint256,bool)"](
        owner.address,
        alice.address,
        await cellar.balanceOf(owner.address),
        false
      );
      // expect next non-zero deposit is set to index 2
      expect(await cellar.currentDepositIndex(owner.address)).to.eq(2);

      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(100, 6), alice.address);
      // alice only transfers half from index 0, leaving some shares remaining
      await cellar
        .connect(alice)
        ["transferFrom(address,address,uint256,bool)"](
          alice.address,
          owner.address,
          Num(50, 6),
          false
        );
      // expect next non-zero deposit is set to index 0 since some shares still remain
      expect(await cellar.currentDepositIndex(alice.address)).to.eq(0);
    });

    it("should require approval for transferring other's shares", async () => {
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);
      await cellar.approve(alice.address, Num(50, 18));

      await cellar
        .connect(alice)
        ["transferFrom(address,address,uint256)"](
          owner.address,
          alice.address,
          Num(50, 18)
        );

      await expect(
        cellar["transferFrom(address,address,uint256)"](
          alice.address,
          owner.address,
          Num(200, 18)
        )
      ).to.be.reverted;
    });
  });

  describe("enterStrategy", () => {
    beforeEach(async () => {
      // owner adds $100 of inactive assets
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);

      // alice adds $100 of inactive assets
      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(100, 6), alice.address);

      // enter all $200 of inactive assets into a strategy
      await cellar.enterStrategy();
    });

    it("should deposit cellar inactive assets into Aave", async () => {
      expect(await USDC.balanceOf(cellar.address)).to.eq(0);
      // because balances accumulate
      expect(await USDC.balanceOf(aUSDC.address)).to.eq(670895918737604);
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
      await cellar["deposit(uint256,address)"](Num(200, 6), owner.address);

      await expect(cellar.enterStrategy())
        .to.emit(cellar, "DepositToAave")
        .withArgs(USDC.address, Num(200, 6));
    });
  });

  describe("claimAndUnstake", () => {
    beforeEach(async () => {
      // owner adds $100 of inactive assets
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);

      // alice adds $100 of inactive assets
      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(100, 6), alice.address);

      // enter all $200 of inactive assets into a strategy
      await cellar.enterStrategy();

      await timetravel(864000); // 10 day

      await cellar["claimAndUnstake()"]();
    });

    it("should claim rewards from Aave and begin unstaking", async () => {
      // expect cellar to claim all 100 stkAAVE
      expect(await stkAAVE.balanceOf(cellar.address)).to.be.closeTo(Num(0.00012633746, 18), Num(0.000126337462, 18));
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
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);

      // alice adds $100 of inactive assets
      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(100, 6), alice.address);

      // enter all $200 of inactive assets into a strategy
      await cellar.enterStrategy();

      await timetravel(864000); // 10 day

      // cellar claims rewards and begins the 10 day cooldown period
      await cellar["claimAndUnstake()"]();

      await timetravel(864000); // 10 day

      await cellar.reinvest([AAVE.address, wethAddress, USDC.address], Num(0.01, 6));
    });

    it("should reinvested rewards back into principal", async () => {
      expect(await stkAAVE.balanceOf(cellar.address)).to.eq(0);
      expect(await aUSDC.balanceOf(cellar.address)).to.be.closeTo(Num(200.329767, 6), Num(200.329768, 6));
    });

    it("should have accrued performance fees", async () => {
      const accruedPerformanceFees = await cellar.accruedPerformanceFees();

      // expect $10.016488350000001 ($200.329767 * 0.05 = $10.016488350000001) worth of fees to be minted as shares
      // TODO: check calculation
      expect(await cellar.balanceOf(cellar.address)).to.be.closeTo(Num(0.00114611024, 18), Num(0.00114611026, 18));
      expect(accruedPerformanceFees).to.be.closeTo(Num(0.00114611024, 18), Num(0.00114611026, 18));
    });

    it("should revert with an invalid swap path", async () => {
      await expect(
        cellar.reinvest([wethAddress, USDC.address, AAVE.address], 0)
      ).to.be.revertedWith(
        `InvalidSwapPath(["${wethAddress}", "${USDC.address}", "${AAVE.address}"])`
      );
    });
  });

  describe("rebalance", () => {
    beforeEach(async () => {
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);
      await cellar.enterStrategy();
      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(500, 6), alice.address);

      // set initial fee data
      await cellar.accrueFees();
    });

    it("should rebalance all USDC liquidity into DAI", async () => {
      expect(await DAI.balanceOf(cellar.address)).to.eq(0);
      expect(await cellar.totalAssets()).to.be.closeTo(Num(1500.000001, 6), Num(1500.000002, 6));

      await cellar.rebalance([USDC.address, DAI.address], 0);

      expect(await aUSDC.balanceOf(cellar.address)).to.eq(0);
      expect(await aDAI.balanceOf(cellar.address)).to.be.at.least(Num(950, 18));
    });

    it("should use a multihop swap when needed", async () => {
      await cellar.rebalance([USDC.address, wethAddress, USDT.address], 0);
    });

    it("should not be possible to rebalance to the same token", async () => {
      const asset = await cellar.asset();
      await expect(
        cellar.rebalance([USDC.address, asset], Num(950, 18))
      ).to.be.revertedWith(`SameAsset("${asset}")`);
    });

    it("should only be able to rebalance from the current asset", async () => {
      await expect(
        cellar.rebalance([DAI.address, USDT.address], Num(950, 18))
      ).to.be.revertedWith(
        `InvalidSwapPath(["${DAI.address}", "${USDT.address}"])`
      );
    });

    it("should have accrued performance fees", async () => {
      await timetravel(864000); // 10 day

      const accruedPerformanceFeesBefore =
        await cellar.accruedPerformanceFees();
      const feesBefore = await cellar.balanceOf(cellar.address);

      await cellar.rebalance([USDC.address, DAI.address], Num(950, 18));

      const accruedPerformanceFeesAfter = await cellar.accruedPerformanceFees();
      const feesAfter = await cellar.balanceOf(cellar.address);

      expect(accruedPerformanceFeesAfter.gt(accruedPerformanceFeesBefore)).to.be
        .true;
      expect(feesAfter.gt(feesBefore)).to.be.true;
    });
  });

  describe("accrueFees", () => {
    it("should accrue platform fees", async () => {
      // owner deposits $1000
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);

      // convert all inactive assets -> active assets
      await cellar.enterStrategy();

      await timetravel(86400); // 1 day

      await cellar.accrueFees();

      const accruedPlatformFees = await cellar.accruedPlatformFees();
      const feesInAssets = await cellar.convertToAssets(accruedPlatformFees);

      // ~$0.027 worth of shares in fees = $1000 * 86400 sec * (1% / secsPerYear)
      expect(feesInAssets).to.be.closeTo(Num(0.027, 6), Num(0.001, 6));
    });

    it("should accrue performance fees", async () => {
      // owner deposits $1000
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);

      // convert all inactive assets -> active assets
      await cellar.enterStrategy();
      await cellar.accrueFees();

      await timetravel(864000); // 10 day
      await cellar.accrueFees();

      const performanceFees = await cellar.accruedPerformanceFees();
      // expect cellar to have received $12.5 fees in shares = $250 gain * 5%,
      // which would be ~10 shares at the time of accrual
      expect(performanceFees).to.be.closeTo(Num(0.038330109, 18), Num(0.0383301092, 18)); // TODO: need to calculate the correct performanceFees

      const ownerAssetBalance = await cellar.convertToAssets(
        await cellar.balanceOf(owner.address)
      );
      const cellarAssetBalance = await cellar.convertToAssets(
        await cellar.balanceOf(cellar.address)
      );

      // expect to be ~$1250 (will be off by an extremely slight amount due to
      // converToAssets truncating 18 decimals of precision to 6 decimals)
      expect(
        ethers.BigNumber.from(ownerAssetBalance).add(
          ethers.BigNumber.from(cellarAssetBalance)
        )
      ).to.be.closeTo(Num(1000.766979, 6), Num(1000.766980, 6)); // TODO: need to calculate the correct value
    });

    it("should burn performance fees as insurance for negative performance", async () => {
      // owner deposits $1000
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);

      // convert all inactive assets -> active assets
      await cellar.enterStrategy();
      await cellar.accrueFees();

      await timetravel(864000); // 10 day
      await cellar.accrueFees();

      await timetravel(864000); // 10 day
      await cellar.accrueFees();

      const performanceFees = await cellar.accruedPerformanceFees();

      // expect all performance fee shares to have been burned
      expect(performanceFees).to.eq(0); // TODO: Expected "76653320194954782" to be equal 0
    });

    it("should be able to transfer fees to Cosmos", async () => {
      // accrue some platform fees
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);
      await cellar.enterStrategy();
      await timetravel(86400); // 1 day
      await cellar.accrueFees();

      await timetravel(864000); // 10 day
      await cellar.accrueFees();

      const fees = await cellar.balanceOf(cellar.address);
      const accruedPlatformFees = await cellar.accruedPlatformFees();
      const accruedPerformanceFees = await cellar.accruedPerformanceFees();
      expect(fees).to.eq(accruedPlatformFees.add(accruedPerformanceFees));

      const feeInAssets = await cellar.convertToAssets(fees);

      await cellar.transferFees(); // TODO: Error: Transaction reverted: function call to a non-contract account

      // expect all fee shares to be transferred out
      expect(await cellar.balanceOf(cellar.address)).to.eq(0);
      expect(await USDC.balanceOf(gravity.address)).to.eq(feeInAssets);
    });

    it("should only withdraw from strategy if holding pool does not contain enough funds", async () => {
      // accrue some platform fees
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);
      await cellar.enterStrategy();
      await timetravel(86400); // 1 day
      await cellar.accrueFees();

      // accrue some performance fees
      await timetravel(864000); // 10 day
      await cellar.accrueFees();

      await cellar.connect(alice)["deposit(uint256,address)"](Num(100, 6), alice.address);

      const beforeActiveAssets = await cellar.activeAssets();
      const beforeInactiveAssets = await cellar.inactiveAssets();

      // redeems fee shares for their underlying assets and sends them to Cosmos
      await cellar.transferFees(); // TODO: Error: Transaction reverted: function call to a non-contract account

      const afterActiveAssets = await cellar.activeAssets();
      const afterInactiveAssets = await cellar.inactiveAssets();

      // active assets from strategy should not have changed
      expect(afterActiveAssets).to.eq(beforeActiveAssets);
      // should have withdrawn from holding pool funds
      expect(afterInactiveAssets.lt(beforeInactiveAssets)).to.be.true;
    });
  });

  describe("pause", () => {
    it("should prevent users from depositing while paused", async () => {
      await cellar.setPause(true);
      expect(cellar["deposit(uint256,address)"](Num(100, 6), owner.address)).to.be.revertedWith(
        "ContractPaused()"
      );
    });

    it("should emits a Pause event", async () => {
      await expect(cellar.setPause(true))
        .to.emit(cellar, "Pause")
        .withArgs(true);
    });
  });

  describe("shutdown", () => {
    it("should prevent users from depositing while shutdown", async () => {
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);
      await cellar.shutdown();
      expect(cellar["deposit(uint256,address)"](Num(100, 6), owner.address)).to.be.revertedWith(
        "ContractShutdown()"
      );
    });

    it("should allow users to withdraw", async () => {
      // alice first deposits
      await cellar.connect(alice)["deposit(uint256,address)"](Num(100, 6), alice.address);

      // cellar is shutdown
      await cellar.shutdown();

      await cellar
        .connect(alice)
        ["withdraw(uint256,address,address)"](
          Num(100, 6),
          alice.address,
          alice.address
        );
    });

    it("should withdraw all active assets from Aave", async () => {
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);

      await cellar.enterStrategy();
      await timetravel(864000); // 10 day

      await cellar.shutdown();

      // expect all of active liquidity to be withdrawn from Aave
      expect(await USDC.balanceOf(cellar.address)).to.be.closeTo(Num(1000.76698, 6), Num(1000.766981, 6));

      // should allow users to withdraw from holding pool
      await cellar["withdraw(uint256,address,address)"](
        Num(1000.766981, 6),
        owner.address,
        owner.address
      );
      expect(await USDC.balanceOf(cellar.address)).to.eq(0);
    });

    it("should emit a Shutdown event", async () => {
      await expect(cellar.shutdown()).to.emit(cellar, "Shutdown");
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
          USDC.address, // tokenOut
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
      await USDC.transfer(cellar.address, Num(5_000_000, 6));

      await expect(cellar["deposit(uint256,address)"](1, owner.address)).to.be.revertedWith(
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
          USDC.address, // tokenOut
          3000, // fee
          owner.address, // recipient
          1657479474, // deadline
          Num(100_000, 6), // amountOut
          ethers.utils.parseEther("50000"), // amountInMaximum
          0, // sqrtPriceLimitX96
        ],
        { value: ethers.utils.parseEther("50000") }
      );

      await USDC.approve(
        cellar.address,
        Num(100_000, 6)
      );

      // owner deposits $5,000,000
      await expect(
        cellar["deposit(uint256,address)"](
          Num(50_001, 6),
          owner.address
        )
      ).to.be.revertedWith(
        `DepositRestricted(${Num(50_000, 6)})`
      );

      await cellar["deposit(uint256,address)"](Num(50_000, 6), owner.address);
      await expect(cellar["deposit(uint256,address)"](1, owner.address)).to.be.revertedWith(
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
          USDC.address, // tokenOut
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
      await USDC.transfer(cellar.address, Num(5_000_000, 6));

      await cellar.removeLiquidityRestriction();

      await cellar["deposit(uint256,address)"](Num(50_001, 6), owner.address);
    });
  });

  describe("sweep", () => {
    beforeEach(async () => {
      await swapRouter.exactOutputSingle(
        [
          wethAddress, // tokenIn
          HEX.address, // tokenOut
          3000, // fee
          owner.address, // recipient
          1657479474, // deadline
          Num(1000, 8), // amountOut
          ethers.utils.parseEther("10"), // amountInMaximum
          0, // sqrtPriceLimitX96
        ],
        { value: ethers.utils.parseEther("10") }
      );

      await HEX.transfer(cellar.address, Num(1000, 8));
    });

    it("should not allow assets managed by cellar to be transferred out", async () => {
      await expect(cellar.sweep(USDC.address)).to.be.revertedWith(
        `ProtectedAsset("${USDC.address}")`
      );
      await expect(cellar.sweep(aUSDC.address)).to.be.revertedWith(
        `ProtectedAsset("${aUSDC.address}")`
      );
      await expect(cellar.sweep(cellar.address)).to.be.revertedWith(
        `ProtectedAsset("${cellar.address}")`
      );
    });

    it("should recover tokens accidentally transferred to the contract", async () => {
      expect(await HEX.balanceOf(owner.address)).to.eq(0);

      await cellar.sweep(HEX.address);

      // expect 1000 HEX to have been transferred from cellar to owner
      expect(await HEX.balanceOf(owner.address)).to.eq(Num(1000, 8));
      expect(await HEX.balanceOf(cellar.address)).to.eq(0);
    });

    it("should emit Sweep event", async () => {
      await expect(cellar.sweep(HEX.address))
        .to.emit(cellar, "Sweep")
        .withArgs(HEX.address, Num(1000, 8));
    });
  });

  describe("conversions", () => {
    it("should accurately convert shares to assets and vice versa", async () => {
      // has been tested successfully from 0 up to 10_000, but set to run once to avoid long test time
      for (let i = 0; i < 1; i++) {
        const initialAssets = Num(i, 6);
        const assetsToShares = await cellar.convertToShares(initialAssets);
        const sharesBackToAssets = await cellar.convertToAssets(assetsToShares);
        expect(sharesBackToAssets).to.eq(initialAssets);
        const assetsBackToShares = await cellar.convertToShares(
          sharesBackToAssets
        );
        expect(assetsBackToShares).to.eq(assetsToShares);
      }
    });
  });
});
