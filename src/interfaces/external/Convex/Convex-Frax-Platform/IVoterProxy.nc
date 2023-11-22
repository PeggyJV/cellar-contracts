// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IVoterProxy{
    function operator() external view returns(address);
}