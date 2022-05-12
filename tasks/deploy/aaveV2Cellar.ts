import { task } from "hardhat/config";
import { TaskArguments } from "hardhat/types";

import { AaveV2StablecoinCellar } from "../../src/types/AaveV2StablecoinCellar";
import { AaveV2StablecoinCellar__factory } from "../../src/types/factories/AaveV2StablecoinCellar__factory";

task("deploy:AaveV2StablecoinCellar").setAction(async function (args: TaskArguments, { ethers }) {
  const signers = await ethers.getSigners();
  console.log("Deployer address: ", signers[0].address);
  console.log("Deployer balance: ", (await signers[0].getBalance()).toString());

  const factory = <AaveV2StablecoinCellar__factory>await ethers.getContractFactory("AaveV2StablecoinCellar");

  const cellar = <AaveV2StablecoinCellar>await factory.deploy(
    "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", // USDC
    [
      "0x056fd409e1d7a124bd7017459dfea2f387b6d5cd", // GUSD
      "0x4fabb145d64652a948d72533023f6e7a623c7c53", // BUSD
      "0xdac17f958d2ee523a2206206994597c13d831ec7", // USDT
      "0x6b175474e89094c44da98b954eedeac495271d0f", // DAI
      "0x956f47f50a910163d8bf957cf5846d573e7f87ca", // FEI
      "0x853d955acef822db058eb8505911ed77f175b99e", // FRAX
      "0x57ab1ec28d129707052df4df418d58a2d46d5f51", // sUSD
      "0x8e870d67f660d95d5be530380d0ec0bd388289e1", // USDP
    ],
    ethers.BigNumber.from("50000000000"), // $50k
    ethers.BigNumber.from("5000000000000"), // $5m
    "0x81C46fECa27B31F3ADC2b91eE4be9717d1cd3DD7", // Curve registry exchange
    "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F", // Sushiswap Router
    "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9", // Aave V2 Lending Pool
    "0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5", // Aave Incentives Controller V2
    "0x69592e6f9d21989a043646fE8225da2600e5A0f7", // Cosmos Gravity Bridge
    "0x4da27a545c0c5B758a6BA100e3a049001de870f5", // stkAAVE
    "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9", // AAVE
    "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // WETH
  );

  await cellar.deployed();

  console.log("AaveV2StablecoinCellar deployed to: ", cellar.address);
});
