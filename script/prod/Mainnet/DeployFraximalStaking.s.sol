// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { CellarStaking } from "src/modules/staking/CellarStaking.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/Mainnet/DeployFraximalStaking.s.sol:DeployFraximalStakingScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployFraximalStakingScript is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    ERC20 private fraximal = ERC20(0xDBe19d1c3F21b1bB250ca7BDaE0687A97B5f77e6);
    ERC20 private somm = ERC20(0xa670d7237398238DE01267472C6f13e5B8010FD1);
    CellarStaking private staker;

    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;

    function run() external {
        vm.startBroadcast();

        staker = new CellarStaking(multisig, fraximal, somm, 30 days, 0.1e18, 0.3e18, 0.5e18, 5 days, 10 days, 14 days);

        vm.stopBroadcast();
    }
}
