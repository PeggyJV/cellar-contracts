import { task } from "hardhat/config";
import { TaskArguments } from "hardhat/types";

import { CellarRouter, CellarRouter__factory } from "../../typechain-types";

task("deploy:CellarRouter").setAction(async function (args: TaskArguments, { ethers }) {
  const signers = await ethers.getSigners();
  console.log("Deployer address: ", signers[0].address);
  console.log("Deployer balance: ", (await signers[0].getBalance()).toString());

  const factory = <CellarRouter__factory>await ethers.getContractFactory("CellarRouter");

  const cellar = <CellarRouter>await factory.deploy(
    "0xE592427A0AEce92De3Edee1F18E0157C05861564", // Uniswap V3 Swap Router
  );

  await cellar.deployed();

  console.log("CellarRouter deployed to: ", cellar.address);
});
