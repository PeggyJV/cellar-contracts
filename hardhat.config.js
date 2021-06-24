/**
 * @type import('hardhat/config').HardhatUserConfig
 */
 module.exports = {
  solidity: {
    version: "0.7.6",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000
      }
    }
  }
}