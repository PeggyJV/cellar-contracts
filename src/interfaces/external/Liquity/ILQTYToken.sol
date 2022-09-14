// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILQTYToken is IERC20 {
    // --- Events ---

    event CommunityIssuanceAddressSet(address _communityIssuanceAddress);
    event LQTYStakingAddressSet(address _lqtyStakingAddress);
    event LockupContractFactoryAddressSet(address _lockupContractFactoryAddress);

    // --- Functions ---

    function sendToLQTYStaking(address _sender, uint256 _amount) external;

    function getDeploymentStartTime() external view returns (uint256);

    function getLpRewardsEntitlement() external view returns (uint256);
}
