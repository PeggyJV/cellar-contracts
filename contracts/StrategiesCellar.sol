// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {IStrategiesCellar} from "./interfaces/IStrategiesCellar.sol";
import {MathUtils} from "./utils/MathUtils.sol";

contract StrategiesCellar is IStrategiesCellar, ERC20 {
    using SafeTransferLib for ERC20;
    using MathUtils for uint256;

    struct Strategy {
        uint256[] subStrategyIds; // list of lower level strategies
        uint8[] proportions; // percentage distribution of the deposits by strategies
        uint8[] maxProportions; // maximum allowed percentages for each subStrategy
        uint256[] subStrategyShares; // sub strategy shares
        bool isBase; // true if this is a base level strategy
        address baseInactiveAsset; // address(0) if isBase == false
        address baseActiveAsset; // aToken corresponding to the baseInactiveAsset
    }

    mapping(uint256 => Strategy) strategies;
    mapping(uint256 => uint256) public strategiesTotalSupplies;
    mapping(uint256 => mapping(address => uint256)) public strategiesInputTokenBalances;
    mapping(address => uint256) public otherStrategiesInputTokenBalances;

    address[] inputTokens;
    uint256 public strategyCount;
    uint8 public constant USD_DECIMALS = 8;

    struct UserDeposit {
        uint256 strategyId;
        uint112 assetsUSD;
        uint112 shares;
        uint32 timeDeposited;
    }
    mapping(address => UserDeposit[]) public userDeposits;

    address public immutable strategyProvider;
    address public immutable cellarVault;

    /**
    * @dev only Strategy Provider can use functions affected by this modifier
    **/
    modifier onlyStrategyProvider {
        if (msg.sender != strategyProvider) revert CallerNoStrategyProvider();
        _;
    }

    constructor(
         address _strategyProvider,
         address _cellarVault
    ) ERC20("Strategies Cellar LP Token", "SCLPT", 18) {
        strategyProvider = _strategyProvider;
        cellarVault = _cellarVault;

        // allowed input tokens. 
        // TODO: make a function to add tokens to the allowed list
        inputTokens.push(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
        inputTokens.push(0xdAC17F958D2ee523a2206206994597C13D831ec7); // USDT
    }

    // deposits allowed input_token from user address into multi-cellar contract in accordance with the chosen strategy.
    // During the deposit, input_token is not immediately exchanged for sub-strategy tokens. 
    // It is more economical to exchange during enterBaseStrategy(uint baseStrategyId) (immediately for all strategies 
    // that include the baseStrategyId token).
    function deposit(uint256 _strategyId, address inputToken, uint256 assets, address receiver) external {
        uint256 assetsUSD = toUSD(inputToken, assets);

        // Must calculate before assets are transferred in.
        uint256 shares = convertToShares(_strategyId, toUSD(inputToken, assetsUSD));

        // Check for rounding error on `deposit` since we round down in convertToShares. No need to
        // check for rounding error if `mint`, previewMint rounds up.
        if (shares == 0) revert ZeroShares();
        
        // Transfers assets into the cellar.
        ERC20(inputToken).safeTransferFrom(msg.sender, cellarVault, assets);

        // Mint user tokens that represents their share of the cellar's assets.
        _mint(receiver, shares);

        _updateStrategiesSharesBalances(_strategyId, inputToken, shares, assets);

        // Store the user's deposit data. This will be used later on when the user wants to withdraw
        // their assets or transfer their shares.
        UserDeposit[] storage deposits = userDeposits[receiver];
        deposits.push(UserDeposit({
            strategyId: _strategyId,
            assetsUSD: uint112(assetsUSD),
            shares: uint112(shares),
            timeDeposited: uint32(block.timestamp)
        }));

        emit Deposit(
            msg.sender,
            receiver,
            inputToken,
            assets,
            shares
        );
    }

    function _updateStrategiesSharesBalances(uint256 _strategyId, address inputToken, uint256 shares, uint256 assets) internal {
        strategiesTotalSupplies[_strategyId] += shares;

        if (strategies[_strategyId].isBase) {
            if (strategies[_strategyId].baseInactiveAsset != inputToken) {
                strategiesInputTokenBalances[_strategyId][inputToken] += assets;
                otherStrategiesInputTokenBalances[inputToken] += assets;
            }
        } else {
            uint256 subStrategyAssets;
            for (uint256 i = 0; i < strategies[_strategyId].subStrategyIds.length; i++) {
                subStrategyAssets = assets.mulDivDown(strategies[_strategyId].proportions[i], uint256(100));

                strategies[_strategyId].subStrategyShares[i] = previewDeposit(
                    strategies[_strategyId].subStrategyIds[i],
                    inputToken, 
                    subStrategyAssets
                );

                _updateStrategiesSharesBalances(
                    strategies[_strategyId].subStrategyIds[i],
                    inputToken,
                    strategies[_strategyId].subStrategyShares[i],
                    subStrategyAssets
                );
            }
        }
    }

    // moves user shares between strategies
    function move(uint256 fromStrategy, uint256 toStrategy, uint256 shares) public {

    }

    // withdraws the specified amount allowed output_token to receiver from owner in accordance with the chosen strategy
    function withdraw(address output_token, uint256 amount, uint256 strategy_id, address receiver, address owner)  public {

    }

    // redeems shares from owner to withdraw allowed output_token into receiver in accordance with the chosen strategy
    function redeem(address output_token, uint256 shares, uint256 strategy_id, address receiver, address owner) public {

    }

    // ================================== ACCOUNTING OPERATIONS ==================================

    // token USD price
    // TODO: need to use chainlink price feeds
    // USD decimals: 8
    function tokenPrice(address token) internal pure returns (uint256) {
        if (token == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) {  // USDC
            return uint256(100000000);
        } else if (token == 0xdAC17F958D2ee523a2206206994597C13D831ec7) { // USDT
            return uint256(100000000);
        } else if (token == 0x6B175474E89094C44Da98b954EedeAC495271d0F) { // DAI
            return uint256(100000000);
        } else {
            revert TokenIsNotSupported();
        }
    }

    function toUSD(address token, uint256 amount) internal view returns (uint256) {
        return tokenPrice(token)*amount / 10**(ERC20(token).decimals());
    }

    function activeBaseAssets(uint256 _baseStrategyId) public view returns (uint256) {
        return ERC20(strategies[_baseStrategyId].baseActiveAsset).
            balanceOf(cellarVault);
    }

    function _activeBaseAssetsUSD(uint256 _baseStrategyId) internal view returns (uint256) {
        return toUSD(strategies[_baseStrategyId].baseActiveAsset, activeBaseAssets(_baseStrategyId));
    }

    function inactiveBaseAssets(uint256 _baseStrategyId) public view returns (uint256) {
        return ERC20(strategies[_baseStrategyId].baseInactiveAsset).
            balanceOf(cellarVault);
    }

    function _inactiveBaseAssetsUSD(uint256 _baseStrategyId) internal view returns (uint256) {
        return toUSD(strategies[_baseStrategyId].baseActiveAsset, inactiveBaseAssets(_baseStrategyId));
    }

    function _strategyTotalInputTokenBalanceUSD(uint256 _baseStrategyId) internal view returns (uint256) {
        uint256 balanceUSD;

        for (uint256 i = 0; i < inputTokens.length; i++) {
            balanceUSD += toUSD(
                inputTokens[i],
                strategiesInputTokenBalances[_baseStrategyId][inputTokens[i]]
            );
        }

        return balanceUSD;
    }

    function _otherStrategyTotalInputTokenBalanceUSD(uint256 _baseStrategyId) internal view returns (uint256) {
        return toUSD(
            strategies[_baseStrategyId].baseInactiveAsset,
            otherStrategiesInputTokenBalances[strategies[_baseStrategyId].baseInactiveAsset]
        );
    }

    function totalBaseAssets(uint256 _baseStrategyId) public view returns (uint256) {
        return activeBaseAssets(_baseStrategyId) + inactiveBaseAssets(_baseStrategyId);
    }

    function _totalBaseAssetsUSD(uint256 _baseStrategyId) internal view returns (uint256) {
        return toUSD(
            strategies[_baseStrategyId].baseInactiveAsset,
            totalBaseAssets(_baseStrategyId)
        ) + _strategyTotalInputTokenBalanceUSD(_baseStrategyId) -
            _otherStrategyTotalInputTokenBalanceUSD(_baseStrategyId);
    }

    function _baseSharesToUSD(uint256 _baseStrategyId, uint256 shares) internal view returns (uint256) {
        return shares >= strategiesTotalSupplies[_baseStrategyId] ? _totalBaseAssetsUSD(_baseStrategyId) :
                shares.mulDivDown(_totalBaseAssetsUSD(_baseStrategyId), strategiesTotalSupplies[_baseStrategyId]);
    }

    function _subStrategyTotalAssetsUSD(uint256 _strategyId, uint256 shares) internal view returns (uint256) {
        if (strategies[_strategyId].isBase) {
            return _baseSharesToUSD(_strategyId, shares);
        } else {
            uint256 subStrategyShares;
            uint256 subStrategiesSumBalanceUSD;

            for (uint256 i = 0; i < strategies[_strategyId].subStrategyIds.length; i++) {
                subStrategyShares = shares.mulDivDown(
                    strategies[_strategyId].subStrategyShares[i],
                    strategiesTotalSupplies[_strategyId]
                );

                subStrategiesSumBalanceUSD += _subStrategyTotalAssetsUSD(
                    strategies[_strategyId].subStrategyIds[i],
                    subStrategyShares
                );
            }

            return subStrategiesSumBalanceUSD;
        }
    }

    function _totalAssetsUSD(uint256 _strategyId) internal view returns (uint256) {
        if (strategies[_strategyId].isBase) {
            return _totalBaseAssetsUSD(_strategyId);
        } else {
            uint256 subStrategiesSumBalanceUSD;

            for (uint256 i = 0; i < strategies[_strategyId].subStrategyIds.length; i++) {
                subStrategiesSumBalanceUSD += _subStrategyTotalAssetsUSD(
                    strategies[_strategyId].subStrategyIds[i],
                    strategies[_strategyId].subStrategyShares[i]
                );
            }

            return subStrategiesSumBalanceUSD;
        }
    }

    function convertToShares(uint256 _strategyId, uint256 assetsUSD) public view returns (uint256) {
        return strategiesTotalSupplies[_strategyId] == 0 ? assetsUSD.changeDecimals(USD_DECIMALS, decimals) : 
                assetsUSD.mulDivDown(strategiesTotalSupplies[_strategyId], _totalAssetsUSD(_strategyId));
    }

    /**
    * @notice Simulate the effects of depositing assets at the current block, given current on-chain
    *         conditions.
     * @param assets amount of assets to deposit
     * @return shares that will be minted
     */
    function previewDeposit(uint256 _strategyId, address inputToken, uint256 assets) public view returns (uint256) {
        return convertToShares(_strategyId, toUSD(inputToken, assets));
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
            if (_maxProportions[i] > uint8(100)) revert IncorrectPercentageValue();
            strategies[strategyCount].subStrategyShares.push(0);
            sum += _proportions[i];
        }
        if (sum != uint8(100)) revert IncorrectPercentageSum();

        strategies[strategyCount].subStrategyIds = _subStrategyIds;
        strategies[strategyCount].proportions = _proportions;
        strategies[strategyCount].maxProportions = _maxProportions;

        strategyCount += 1;

        emit AddStrategy(strategyCount - 1);
    }

    // creates a new base strategy
    function addBaseStrategy(address _baseInactiveAsset, address _baseActiveAsset) onlyStrategyProvider external {
        strategies[strategyCount].isBase = true;
        strategies[strategyCount].baseInactiveAsset = _baseInactiveAsset;
        strategies[strategyCount].baseActiveAsset = _baseActiveAsset;

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

    function getSubStrategyShares(uint256 strategyId) view external returns(uint256[] memory) {
        return strategies[strategyId].subStrategyShares;
    }

    function getIsBase(uint256 strategyId) view external returns(bool) {
        return strategies[strategyId].isBase;
    }

    function getBaseInactiveAsset(uint256 strategyId) view external returns(address) {
        return strategies[strategyId].baseInactiveAsset;
    }

    function getBaseActiveAsset(uint256 strategyId) view external returns(address) {
        return strategies[strategyId].baseActiveAsset;
    }
}