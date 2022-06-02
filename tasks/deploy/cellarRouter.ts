import { task } from "hardhat/config";
import { TaskArguments } from "hardhat/types";

import { CellarRouter, CellarRouter__factory } from "../../typechain-types";

task("deploy:CellarRouter").setAction(async function (args: TaskArguments, { ethers }) {
  const signers = await ethers.getSigners();
  console.log("Deployer address: ", signers[0].address);
  console.log("Deployer balance: ", (await signers[0].getBalance()).toString());

  const factory = <CellarRouter__factory>await ethers.getContractFactory("CellarRouter");

  const cellar = <CellarRouter>await factory.deploy(
    "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F", // Sushiswap Router
  );

  await cellar.deployed();

  console.log("CellarRouter deployed to: ", cellar.address);
});
