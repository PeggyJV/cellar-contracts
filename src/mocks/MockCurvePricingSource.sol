// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { CurvePool } from "src/interfaces/external/Curve/CurvePool.sol";

/**
 * @title MockCurvePricingSource
 * @author crispymangoes, 0xeincodes
 * @notice Test mock contract with same function signatures as actual CurvePool sources. 
    - 2Pool uses getVirtualPrice()
    - CurveEMA uses pool.priceOracle()
 * NOTE: This is not based off of a real curve pool in prod, this is a mock contract that needs to be updated for new pricing for respective tests to simulate working with a pool under different conditions.
 */
contract MockCurvePricingSource {
    uint256 public mockVirtualPrice;
    uint256 public mockPriceOraclePrice;
    uint256 public mockUpdatedAt;

    /// Curve2Pool Extension Related Getters
    uint256 public coinsLength = 2; // for 2pools
    address[2] public coins; // constituent addresses
    uint256[2] public rates; // rates per constituent asset wrt to one another or wrt to coins0 iirc

    /**
     * @notice set up mock curve pool for pricing purposes
     */
    constructor(
        address[2] memory _coins,
        uint256[2] memory _rates,
        uint256 _mockVirtualPrice,
        uint256 _mockPriceOraclePrice
    ) {
        coins = _coins;
        rates = _rates;
        mockVirtualPrice = _mockVirtualPrice;
        mockPriceOraclePrice = _mockPriceOraclePrice;
        
    }

    /**
     * @notice Mock get_virtual_price getter returning mock_virtual_price set within test
     * @return mock price of curve lpt
     */
    function get_virtual_price() public view returns (uint256) {
        uint256 answer;
        if (mockVirtualPrice != 0) {
            answer = mockVirtualPrice;
        }
        return answer;
    }

    /**
     * @notice This should not revert for pools we are using that are correlated. We are not working with uncorrelated assets ATM.
     * @return lp asset price
     */
    function lp_price() public view returns (uint256) {
        uint256 answer;
        if (mockVirtualPrice != 0) {
            answer = mockVirtualPrice;
        }
        return answer;
    }

    /// Curve EMA Extension Related Getters

    uint256 public mockCurveEMAPrice;
    uint256[2] public stored_rates; // coin rates using Curve EMA oracle as per rateIndex

    /// Curve EMA Extension Related Setters

    /**
     * @notice Get the price of an asset using a Curve EMA Oracle.
     */
    function price_oracle() public view returns (uint256) {
        uint256 answer;
        if (mockPriceOraclePrice != 0) {
            answer = mockPriceOraclePrice;
        }
        return answer;
    }

    /**
     * @notice set mock curve ema stored_rates array
     */
    function setStoredRates(uint256 at) external {
        mockUpdatedAt = at;
    }

    /// Curve 2pool Extension Related Setters

    /**
     * @notice set mockVirtualPrice
     */
    function setMockVirtualPrice(uint256 ans) external {
        mockVirtualPrice = ans;
    }

    /**
     * @notice set mockPriceOraclePrice
     */
    function setMockPriceOraclePrice(uint256 ans) external {
        mockPriceOraclePrice = ans;
    }

    /**
     * @notice set mock 2pool rates array
     */
    function setCoinsRates(uint256 at) external {
        mockUpdatedAt = at;
    }

    /// General setter

    /**
     * @notice set mock updated at timestamp
     */
    function setMockUpdatedAt(uint256 at) external {
        mockUpdatedAt = at;
    }
}
