import "@typechain/hardhat";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "hardhat-contract-sizer";

import "./tasks/accounts";
// import "./tasks/deploy/aaveV2Cellar";

import { TaskArguments } from "hardhat/types";
import { subtask } from "hardhat/config";
import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from "hardhat/builtin-tasks/task-names";

// Override Hardhat compiler to ignore compiling files related to Foundry testing.
subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(
  async (_: TaskArguments, __, runSuper: any) => {
    const paths = await runSuper();

    return paths.filter(
      (p: string) =>
        !p.endsWith(".t.sol") && !p.includes("/users/") && !p.includes("/lib/")
    );
  }
);

import { resolve } from "path";

import { config as dotenvConfig } from "dotenv";
import { HardhatUserConfig } from "hardhat/config";
import { NetworkUserConfig, HardhatNetworkUserConfig } from "hardhat/types";

dotenvConfig({ path: resolve(__dirname, "./.env") });

const chainIds = {
  ganache: 1337,
  goerli: 5,
  hardhat: 1337,
  localhost: 31337,
  kovan: 42,
  mainnet: 1,
  rinkeby: 4,
  ropsten: 3,
};

// Ensure that we have all the environment variables we need.
let mnemonic: string;
if (!process.env.MNEMONIC) {
  mnemonic = "test test test test test test test test test test test junk";
} else {
  mnemonic = process.env.MNEMONIC;
}

const forkMainnet = process.env.FORK_MAINNET === "true";

let alchemyApiKey: string | undefined;
if (forkMainnet && !process.env.ALCHEMY_API_KEY) {
  throw new Error("Please set process.env.ALCHEMY_API_KEY");
} else {
  alchemyApiKey = process.env.ALCHEMY_API_KEY;
}

function createTestnetConfig(
  network: keyof typeof chainIds
): NetworkUserConfig {
  const url = `https://eth-${network}.alchemyapi.io/v2/${alchemyApiKey}`;
  return {
    accounts: {
      count: 10,
      initialIndex: 0,
      mnemonic,
      path: "m/44'/60'/0'/0",
    },
    chainId: chainIds[network],
    url,
  };
}

function createHardhatConfig(): HardhatNetworkUserConfig {
  const config = {
    accounts: {
      mnemonic,
    },
    chainId: chainIds.hardhat,
  };

  if (forkMainnet) {
    return Object.assign(config, {
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/${alchemyApiKey}`,
        blockNumber: 13837533,
      },
    });
  }

  return config;
}

function createMainnetConfig(): NetworkUserConfig {
  return {
    accounts: {
      mnemonic,
    },
    chainId: chainIds.mainnet,
    url: `https://eth-mainnet.alchemyapi.io/v2/${alchemyApiKey}`,
  };
}

const optimizerEnabled = process.env.DISABLE_OPTIMIZER ? false : true;

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  gasReporter: {
    currency: "USD",
    enabled: process.env.REPORT_GAS ? true : false,
    excludeContracts: [],
    src: "./contracts",
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    outputFile: process.env.REPORT_GAS_OUTPUT,
  },
  networks: {
    mainnet: createMainnetConfig(),
    hardhat: createHardhatConfig(),
    goerli: createTestnetConfig("goerli"),
    kovan: createTestnetConfig("kovan"),
    rinkeby: createTestnetConfig("rinkeby"),
    ropsten: createTestnetConfig("ropsten"),
    localhost: {
      accounts: {
        mnemonic,
      },
      chainId: chainIds.hardhat,
      gasMultiplier: 10,
    },
  },
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./tests",
  },
  solidity: {
    compilers: [
      {
        version: "0.8.11",
        settings: {
          metadata: {
            // Not including the metadata hash
            // https://github.com/paulrberg/solidity-template/issues/31
            bytecodeHash: "none",
          },
          // You should disable the optimizer when debugging
          // https://hardhat.org/hardhat-network/#solidity-optimizer-support
          optimizer: {
            enabled: optimizerEnabled,
            runs: 100,
            details: {
              // Enabled to fix stack errors when attempting to run test coverage
              yul: true,
              yulDetails: {
                stackAllocation: true,
              },
            },
          },
        },
      },
      {
        version: "0.4.12",
      },
    ],
  },
  typechain: {
    outDir: "src/types",
    target: "ethers-v5",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  contractSizer: {
    runOnCompile: true,
    only: ["AaveV2StablecoinCellar.sol"],
  },
};

export default config;
