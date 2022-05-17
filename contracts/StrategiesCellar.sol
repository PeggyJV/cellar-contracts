// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {IStrategiesCellar} from "./interfaces/IStrategiesCellar.sol";
import {ICellarVault} from "./interfaces/ICellarVault.sol";
import {MathUtils} from "./utils/MathUtils.sol";

/**
 * @title Sommelier Strategies Cellar
 * @notice Dynamic ERC4626 that adapts strategies to always get the best yield.
 */
contract StrategiesCellar is IStrategiesCellar, ERC20 {
    using SafeTransferLib for ERC20;
    using MathUtils for uint256;

    mapping(uint256 => Strategy) strategies;
    mapping(uint256 => uint256) public strategiesTotalSupplies;
    mapping(uint256 => uint256) public strategiesAssetBalances; // strategiesAssetBalances[_strategyId]
    mapping(address => mapping(uint256 => uint256)) public userStrategyShares; // userStrategyShares[user][_strategyId] -> shares

    address[] inputTokens;
    address[] outputTokens;

    uint256 public strategyCount;

    ERC20 public asset = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
    uint8 public assetDecimals = 6;

    address public immutable strategyProvider;
    ICellarVault public immutable cellarVault;

    /**
    * @dev only Strategy Provider can use functions affected by this modifier
    **/
    modifier onlyStrategyProvider {
        if (msg.sender != strategyProvider) revert CallerNoStrategyProvider();
        _;
    }

    /**
    * @dev only CellarVault contract can use functions affected by this modifier
    **/
    modifier onlyCellarVault {
        if (msg.sender != address(cellarVault)) revert CallerNoCellarVault();
        _;
    }

    constructor(
         address _strategyProvider,
         ICellarVault _cellarVault
    ) ERC20("Strategies Cellar LP Token", "SCLPT", 18) {
        strategyProvider = _strategyProvider;
        cellarVault = _cellarVault;

        // allowed input tokens. 
        // TODO: make a function to add tokens to the allowed list
        inputTokens.push(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
        inputTokens.push(0xdAC17F958D2ee523a2206206994597C13D831ec7); // USDT
        inputTokens.push(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI
        
        // allowed output tokens. 
        // TODO: make a function to add tokens to the allowed list
        outputTokens.push(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
        outputTokens.push(0xdAC17F958D2ee523a2206206994597C13D831ec7); // USDT
        outputTokens.push(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI
    }

    // deposits allowed input_token from user address into multi-cellar contract in accordance with the chosen strategy.
    // During the deposit, input_token is not immediately exchanged for sub-strategy tokens. 
    // It is more economical to exchange during enterBaseStrategy(uint baseStrategyId) (immediately for all strategies 
    // that include the baseStrategyId token).
    function deposit(uint256 _strategyId, address inputToken, uint256 inputAmount, address receiver) external {
        // Check inputToken
        bool inputTokenAllowed;
        for (uint256 i = 0; i < inputTokens.length; i++) {
            if (inputTokens[i] == inputToken) {
                inputTokenAllowed = true;
            }
        }
        if (!inputTokenAllowed) revert InputTokenNotAllowed();
        
        // Transfers inputToken into the cellarVault.
        ERC20(inputToken).safeTransferFrom(msg.sender, address(cellarVault), inputAmount);

        // Swap inputToken to assets in the cellarVault
        uint256 assets;
        if (inputToken != address(asset)) {
            assets = cellarVault.swapToAsset(
                inputToken,
                inputAmount,
                0 // TODO: can add amountOutMin to the deposit parameters
            );
        } else {
            assets = inputAmount;
        }

        // Calculate shares
        uint256 shares = convertToShares(_strategyId, assets);

        // Check for rounding error on `deposit` since we round down in convertToShares
        if (shares == 0) revert ZeroShares();

        // Mint user tokens that represents their share of the cellar's assets.
        _mint(receiver, shares);

        // update strategiesTotalSupplies (and subStrategiesShares) in given strategy
        _updateStrategiesSharesBalancesOnDeposit(_strategyId, shares, assets);

        // Update shares user balance in given strategy
        userStrategyShares[receiver][_strategyId] += shares;

        emit Deposit(
            msg.sender,
            receiver,
            inputToken,
            inputAmount,
            shares
        );
    }

    function _updateStrategiesSharesBalancesOnDeposit(uint256 _strategyId, uint256 shares, uint256 assets) internal {
        strategiesTotalSupplies[_strategyId] += shares;

        if (strategies[_strategyId].isBase) {
            strategiesAssetBalances[_strategyId] += assets;
        } else {
            uint256 subStrategyAssets;
            uint256 subStrategyShares;

            for (uint256 i = 0; i < strategies[_strategyId].subStrategiesIds.length; i++) {
                subStrategyAssets = assets.mulDivDown(strategies[_strategyId].proportions[i], uint256(100));

                subStrategyShares = convertToShares(
                    strategies[_strategyId].subStrategiesIds[i],
                    subStrategyAssets
                );

                strategies[_strategyId].subStrategiesShares[i] += subStrategyShares;

                _updateStrategiesSharesBalancesOnDeposit(
                    strategies[_strategyId].subStrategiesIds[i],
                    subStrategyShares,
                    subStrategyAssets
                );
            }
        }
    }

    // moves user shares between strategies
    function move(uint256 fromStrategy, uint256 toStrategy, uint256 shares) public {

    }

    // withdraws the specified amount allowed outputToken to receiver from owner in accordance with the chosen strategy
    function withdraw(uint256 _strategyId, address outputToken, uint256 outputAmount, address receiver, address owner) public {
        if (balanceOf[owner] == 0) revert ZeroShares();
        if (outputAmount == 0) revert ZeroAssets();

        // Check outputToken
        bool outputTokenAllowed;
        for (uint256 i = 0; i < outputTokens.length; i++) {
            if (outputTokens[i] == outputToken) {
                outputTokenAllowed = true;
            }
        }
        if (!outputTokenAllowed) revert OutputTokenNotAllowed();

        uint256 assets = cellarVault.toAsset(outputToken, outputAmount, true);

        uint256 maxWithdrawable = convertToAssets(_strategyId, userStrategyShares[owner][_strategyId]);
        uint256 shares;
        if (assets > maxWithdrawable) {
            assets = maxWithdrawable;
            shares = userStrategyShares[owner][_strategyId];
            outputAmount = cellarVault.toToken(outputToken, assets, false);
        } else {
            shares = convertToShares(_strategyId, assets);
        }

        _updateStrategiesSharesBalancesOnWithdraw(_strategyId, shares, assets);

        // If the caller is not the owner of the shares, check to see if the owner has approved them
        // to spend their shares.
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Redeem shares for assets.
        _burn(owner, shares);

        userStrategyShares[owner][_strategyId] -= shares;

        cellarVault.withdraw(outputToken, assets, outputAmount, receiver);

        emit Withdraw(receiver, owner, outputToken, outputAmount, shares);
    }

    function _updateStrategiesSharesBalancesOnWithdraw(
        uint256 _strategyId,
        uint256 shares,
        uint256 assets
    ) internal {
        strategiesTotalSupplies[_strategyId] -= shares;

        if (strategies[_strategyId].isBase) {
            uint256 assetsToBeWithdrawn = MathUtils.min(strategiesAssetBalances[_strategyId], assets);
            strategiesAssetBalances[_strategyId] -= assetsToBeWithdrawn;
            
            uint256 missingAssets = assets - assetsToBeWithdrawn;
            if (missingAssets > 0) {
                uint256 missingInactiveAssets = cellarVault.toToken(strategies[_strategyId].baseInactiveAsset, missingAssets, true);
                missingInactiveAssets = cellarVault.convertActiveToInactiveAsset(
                    _strategyId,
                    missingInactiveAssets
                );

                // output must be at least missingAssets
                // can be fixed by replacing sushiswap with uniswap v3
                if (strategies[_strategyId].baseInactiveAsset != address(asset)) {
                    cellarVault.swapToAsset(
                        strategies[_strategyId].baseInactiveAsset,
                        missingInactiveAssets,
                        missingAssets
                    );
                }
            }
        } else {
            uint256 subStrategyAssets;
            uint256 subStrategyShares;
            uint256 _totalAssets = totalAssets(_strategyId);

            for (uint256 i = 0; i < strategies[_strategyId].subStrategiesIds.length; i++) {
                subStrategyAssets = _subStrategyTotalAssetsUSDC(
                    strategies[_strategyId].subStrategiesIds[i],
                    strategies[_strategyId].subStrategiesShares[i]
                ).mulDivDown(assets, _totalAssets);

                subStrategyShares = convertToShares(
                    strategies[_strategyId].subStrategiesIds[i],
                    subStrategyAssets
                );

                strategies[_strategyId].subStrategiesShares[i] -= subStrategyShares;

                _updateStrategiesSharesBalancesOnWithdraw(
                    strategies[_strategyId].subStrategiesIds[i],
                    subStrategyShares,
                    subStrategyAssets
                );
            }
        }
    }

    // redeems shares from owner to withdraw allowed outputToken into receiver in accordance with the chosen strategy
    function redeem(address outputToken, uint256 shares, uint256 _strategyId, address receiver, address owner) public {

    }

    // ================================== ACCOUNTING OPERATIONS ==================================

    function activeBaseAssets(uint256 _baseStrategyId) public view returns (uint256) {
        return ERC20(strategies[_baseStrategyId].baseActiveAsset).
            balanceOf(address(cellarVault));
    }

    function activeBaseAssetsUSDC(uint256 _baseStrategyId) public view returns (uint256) {
        if (activeBaseAssets(_baseStrategyId) == 0) return 0;
        return cellarVault.toAsset(strategies[_baseStrategyId].baseInactiveAsset, activeBaseAssets(_baseStrategyId), false);
    }

    function inactiveBaseAssets(uint256 _baseStrategyId) public view returns (uint256) {
        if (inactiveBaseAssetsUSDC(_baseStrategyId) == 0) return 0;
        return cellarVault.toToken(strategies[_baseStrategyId].baseInactiveAsset, inactiveBaseAssetsUSDC(_baseStrategyId), false);
    }

    function inactiveBaseAssetsUSDC(uint256 _baseStrategyId) public view returns (uint256) {
        return strategiesAssetBalances[_baseStrategyId];
    }

    function totalBaseAssets(uint256 _baseStrategyId) public view returns (uint256) {
        return activeBaseAssets(_baseStrategyId) + inactiveBaseAssets(_baseStrategyId);
    }

    function totalBaseAssetsUSDC(uint256 _baseStrategyId) public view returns (uint256) {
        return activeBaseAssetsUSDC(_baseStrategyId) + inactiveBaseAssetsUSDC(_baseStrategyId);
    }

    function _baseSharesToUSDC(uint256 _baseStrategyId, uint256 shares) internal view returns (uint256) {
        return shares >= strategiesTotalSupplies[_baseStrategyId] ? totalBaseAssetsUSDC(_baseStrategyId) :
                shares.mulDivDown(totalBaseAssetsUSDC(_baseStrategyId), strategiesTotalSupplies[_baseStrategyId]);
    }

    function _subStrategyTotalAssetsUSDC(uint256 _strategyId, uint256 shares) internal view returns (uint256) {
        if (strategies[_strategyId].isBase) {
            return _baseSharesToUSDC(_strategyId, shares);
        } else {
            uint256 subStrategyShares;
            uint256 subStrategiesSumBalanceUSDC;

            for (uint256 i = 0; i < strategies[_strategyId].subStrategiesIds.length; i++) {
                subStrategyShares = shares.mulDivDown(
                    strategies[_strategyId].subStrategiesShares[i],
                    strategiesTotalSupplies[_strategyId]
                );

                subStrategiesSumBalanceUSDC += _subStrategyTotalAssetsUSDC(
                    strategies[_strategyId].subStrategiesIds[i],
                    subStrategyShares
                );
            }

            return subStrategiesSumBalanceUSDC;
        }
    }

    function totalAssets(uint256 _strategyId) public view returns (uint256) {
        if (strategies[_strategyId].isBase) {
            return totalBaseAssetsUSDC(_strategyId);
        } else {
            uint256 subStrategiesSumBalanceUSDC;

            for (uint256 i = 0; i < strategies[_strategyId].subStrategiesIds.length; i++) {
                subStrategiesSumBalanceUSDC += _subStrategyTotalAssetsUSDC(
                    strategies[_strategyId].subStrategiesIds[i],
                    strategies[_strategyId].subStrategiesShares[i]
                );
            }

            return subStrategiesSumBalanceUSDC;
        }
    }

    function convertToShares(uint256 _strategyId, uint256 assetsUSDC) internal view returns (uint256) {
        return strategiesTotalSupplies[_strategyId] == 0 ? assetsUSDC.changeDecimals(assetDecimals, decimals) : 
                assetsUSDC.mulDivDown(strategiesTotalSupplies[_strategyId], totalAssets(_strategyId));
    }

    function convertToAssets(uint256 _strategyId, uint256 shares) internal view returns (uint256) {
        return strategiesTotalSupplies[_strategyId] == 0 ? shares.changeDecimals(decimals, assetDecimals) :
            shares.mulDivDown(totalAssets(_strategyId), strategiesTotalSupplies[_strategyId]);
//             _subStrategyTotalAssetsUSDC(_strategyId, shares);
    }

    function previewDeposit(uint256 _strategyId, address inputToken, uint256 amount) public view returns (uint256) {
        return convertToShares(_strategyId, cellarVault.toAsset(inputToken, amount, false));
    }

    function previewWithdraw(uint256 _strategyId, address outputToken, uint256 amount) public view returns (uint256) {
        return convertToShares(_strategyId, cellarVault.toAsset(outputToken, amount, true));
    }

    function afterEnterBaseStrategy(uint256 _baseStrategyId) onlyCellarVault public {
        strategiesAssetBalances[_baseStrategyId] = 0;
    }
    // ================================== STRATEGY OPERATIONS ==================================

    // creates a new strategy
    function addStrategy(
        uint256[] memory _subStrategiesIds,
        uint8[] memory _proportions,
        uint8[] memory _maxProportions
    ) onlyStrategyProvider external {
        if (_subStrategiesIds.length != _proportions.length ||
            _subStrategiesIds.length != _maxProportions.length) revert IncorrectArrayLength();

        uint8 sum;
        for (uint256 i = 0; i < _proportions.length; i++) {
            if (_maxProportions[i] > uint8(100)) revert IncorrectPercentageValue();
            strategies[strategyCount].subStrategiesShares.push(0);
            sum += _proportions[i];
        }
        if (sum != uint8(100)) revert IncorrectPercentageSum();

        strategies[strategyCount].subStrategiesIds = _subStrategiesIds;
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

    function getSubStrategiesIds(uint256 strategyId) view external returns(uint256[] memory) {
        return strategies[strategyId].subStrategiesIds;
    }

    function getProportions(uint256 strategyId) view external returns(uint8[] memory) {
        return strategies[strategyId].proportions;
    }

    function getMaxProportions(uint256 strategyId) view external returns(uint8[] memory) {
        return strategies[strategyId].maxProportions;
    }

    function getSubStrategiesShares(uint256 strategyId) view external returns(uint256[] memory) {
        return strategies[strategyId].subStrategiesShares;
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

    // ================================= SHARE TRANSFER OPERATIONS =================================

    /**
     * @dev Modified versions of Solmate's ERC20 transfer and transferFrom functions to work with the
     *      cellar's active vs inactive shares mechanic.
     */

    /// @dev For compatibility with ERC20 standard.
    function transferFrom(address from, address to, uint256 shares) public override returns (bool) {
        // If the sender is not the owner of the shares, check to see if the owner has approved them
        // to spend their shares.
        if (msg.sender != from) {
            uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - shares;
        }

        uint256 leftToTransfer = shares;
        uint256 transferredStrategyShares;
        for (uint256 i = 0; i < strategyCount; i++) {
            if (userStrategyShares[from][i] > 0) {
                transferredStrategyShares = MathUtils.min(leftToTransfer, userStrategyShares[from][i]);
                userStrategyShares[from][i] -= transferredStrategyShares;
                userStrategyShares[to][i] += transferredStrategyShares;
                leftToTransfer -= transferredStrategyShares;
            }
            
            if (leftToTransfer == 0)
                break;
        }

        // Will revert here if sender is trying to transfer more shares then they have, so no need
        // for an explicit check.
        balanceOf[from] -= shares;

        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += shares;
        }

        emit Transfer(from, to, shares);

        return true;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        // Defaults to only transferring active shares.
        return transferFrom(msg.sender, to, amount);
    }
}
