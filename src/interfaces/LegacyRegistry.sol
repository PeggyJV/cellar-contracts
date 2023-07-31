// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface LegacyRegistry {
    function trustPosition(address adaptor, bytes memory adaptorData) external returns (uint32);

    function trustAdaptor(address adaptor) external;
}
