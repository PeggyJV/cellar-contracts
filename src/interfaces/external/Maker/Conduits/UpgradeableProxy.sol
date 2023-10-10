// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { IUpgradeableProxy } from "./interfaces/IUpgradeableProxy.sol";

contract UpgradeableProxy is IUpgradeableProxy {

    address public override implementation;

    mapping (address => uint256) public override wards;

    modifier auth {
        require(wards[msg.sender] == 1, "UpgradeableProxy/not-authorized");
        _;
    }

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function deny(address usr) external override auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function rely(address usr) external override auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function setImplementation(address implementation_) external override auth {
        implementation = implementation_;
        emit SetImplementation(implementation_);
    }

    fallback() external {
        address implementation_ = implementation;

        require(implementation_.code.length != 0, "UpgradeableProxy/no-code-at-implementation");

        assembly {
            calldatacopy(0, 0, calldatasize())

            let result := delegatecall(gas(), implementation_, 0, calldatasize(), 0, 0)

            returndatacopy(0, 0, returndatasize())

            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

}
