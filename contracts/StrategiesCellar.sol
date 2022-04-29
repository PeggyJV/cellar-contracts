// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {IAaveV2StablecoinCellar} from "./interfaces/IAaveV2StablecoinCellar.sol";
import {IStrategiesCellar} from "./interfaces/IStrategiesCellar.sol";
import {MathUtils} from "./utils/MathUtils.sol";

contract StrategiesCellar is IStrategiesCellar, ERC20 {
    using SafeTransferLib for ERC20;
    using MathUtils for uint256;

    struct Strategy {
        uint256[] subStrategyIds; // list of lower level strategies
        uint8[] proportions; // percentage distribution of the deposits by strategies
        uint8[] maxProportions; // maximum allowed percentages for each subStrategy
        bool isBase; // true if this is a base level strategy
        address baseAsset; // address(0) if isBase == false
    }

    mapping(uint256 => Strategy) strategies;
    mapping(uint256 => uint256) public strategiesBalances;

    uint256 public strategyCount;

    struct UserDeposit {
        uint256 strategyId;
        uint112 assets;
        uint112 shares;
        uint32 timeDeposited;
    }
    mapping(address => UserDeposit[]) public userDeposits;

    address public immutable strategyProvider;
    IAaveV2StablecoinCellar public immutable aaveCellarVault;

    /**
    * @dev only Strategy Provider can use functions affected by this modifier
    **/
    modifier onlyStrategyProvider {
        if (msg.sender != strategyProvider) revert CallerNoStrategyProvider();
        _;
    }

    constructor(
         address _strategyProvider,
         IAaveV2StablecoinCellar _aaveCellarVault
    ) ERC20("Strategies Cellar LP Token", "SCLPT", 18) {
         strategyProvider = _strategyProvider;
         aaveCellarVault = _aaveCellarVault;
    }

    // ================================== STRATEGY OPERATIONS ==================================

    // creates a new strategy
    function addStrategy(
        uint256[] memory _subStrategyIds,
        uint8[] memory _proportions,
        uint8[] memory _maxProportions
    ) onlyStrategyProvider external {
        if (_subStrategyIds.length != _proportions.length ||
            _subStrategyIds.length != _maxProportions.length) revert IncorrectArrayLength();

        uint8 sum;
        for (uint256 i = 0; i < _proportions.length; i++) {
            sum += _proportions[i];
        }
        if (sum != uint8(100)) revert IncorrectPercentageSum();

        for (uint256 i = 0; i < _maxProportions.length; i++) {
            if (_maxProportions[i] > uint8(100)) revert IncorrectPercentageValue();
        }

        strategies[strategyCount].subStrategyIds = _subStrategyIds;
        strategies[strategyCount].proportions = _proportions;
        strategies[strategyCount].maxProportions = _maxProportions;

        strategyCount += 1;

        emit AddStrategy(strategyCount - 1);
    }

    // creates a new base strategy
    function addBaseStrategy(address _baseAsset) onlyStrategyProvider external {
        strategies[strategyCount].isBase = true;
        strategies[strategyCount].baseAsset = _baseAsset;

        strategyCount += 1;

        emit AddBaseStrategy(strategyCount - 1);
    }

    // Updates proportions (zero values allowed) for the strategy. 
    // In this case, the cellar.rebalance() function will be used, which allows you to rebalance all the assets of the strategy.
    // To expand the list, he must create a new strategy, in which he can include the previous strategy in its entirety and add any others. 
    // Users must transfer assets from the old strategy to the new one on their own.
    function updateStrategy(uint256 _strategyId, uint8[] memory _proportions) onlyStrategyProvider external {
        if (strategies[_strategyId].proportions.length != _proportions.length) revert IncorrectArrayLength();

        uint8 sum;
        for (uint256 i = 0; i < _proportions.length; i++) {
            sum += _proportions[i];
        }
        if (sum != uint8(100)) revert IncorrectPercentageSum();

        strategies[_strategyId].proportions = _proportions;

        emit UpdateStrategy(_strategyId);
    }

    // changes the proportions of an asset in all strategies in which it is included
    // function balkUpdateStrategy() onlyStrategyProvider external {}

    // deletes a strategy. All assets remain in cellar but are inactive.
    // function removeStrategy(uint256 strategyId) onlyStrategyProvider external {}

    function getSubStrategyIds(uint256 strategyId) view external returns(uint256[] memory) {
        return strategies[strategyId].subStrategyIds;
    }

    function getProportions(uint256 strategyId) view external returns(uint8[] memory) {
        return strategies[strategyId].proportions;
    }

    function getMaxProportions(uint256 strategyId) view external returns(uint8[] memory) {
        return strategies[strategyId].maxProportions;
    }

    function getIsBase(uint256 strategyId) view external returns(bool) {
        return strategies[strategyId].isBase;
    }

    function getBaseAsset(uint256 strategyId) view external returns(address) {
        return strategies[strategyId].baseAsset;
    }
}