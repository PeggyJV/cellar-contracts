import fs from "fs";
import { resolve } from "path";
import { NetworkUserConfig, HardhatNetworkUserConfig } from "hardhat/types";
import { HardhatUserConfig } from "hardhat/config";
import { config as dotenvConfig } from "dotenv";
import "@typechain/hardhat";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-preprocessor";
import "hardhat-contract-sizer";

// Commented out to fix initial compile error with Hardhat, uncomment after compiling with `npx hardhat compile`.
// import "./tasks/accounts";
// import "./tasks/deploy";

function getRemappings() {
  return fs
    .readFileSync("remappings.txt", "utf8")
    .split("\n")
    .filter(Boolean)
    .map(line => line.trim().split("="));
}

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

function createTestnetConfig(network: keyof typeof chainIds): NetworkUserConfig {
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
  solidity: {
    compilers: [
      {
        version: "0.8.16",
        settings: {
          optimizer: {
            enabled: optimizerEnabled,
            runs: 200,
            details: {
              // Enabled to fix stack errors when attempting to run test coverage.
              yul: true,
              yulDetails: {
                stackAllocation: true,
              },
            },
          },
        },
      },
    ],
  },
  paths: {
    sources: "./src", // Use ./src rather than ./contracts as Hardhat expects
    cache: "./cache_hardhat", // Use a different cache for Hardhat than Foundry
  },
  defaultNetwork: "hardhat",
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
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  gasReporter: {
    currency: "USD",
    enabled: process.env.REPORT_GAS ? true : false,
    excludeContracts: [],
    src: "./src",
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    outputFile: process.env.REPORT_GAS_OUTPUT,
  },
  // This fully resolves paths for imports in the ./lib directory for Hardhat
  preprocess: {
    eachLine: hre => ({
      transform: (line: string) => {
        if (line.match(/^\s*import /i)) {
          getRemappings().forEach(([find, replace]) => {
            if (line.match('"' + find)) {
              line = line.replace('"' + find, '"' + replace);
            }
          });
        }
        return line;
      },
    }),
  },
};

export default config;
