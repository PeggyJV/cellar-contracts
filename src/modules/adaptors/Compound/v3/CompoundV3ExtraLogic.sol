// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16; // TODO: update to 0.8.21
import { ERC20 } from "src/modules/adaptors/BaseAdaptor.sol";

import { Math } from "src/utils/Math.sol";
import { CometInterface } from "src/interfaces/external/Compound/CometInterface.sol";

/**
 * @title CompoundV3 Extra Logic contract
 * @notice An abstract contract with general logic usable by any of the core CompoundV3 adaptors offering core functionality (lending, borrowing, supplying).
 * @dev This contract is specifically for CompoundV3 contracts.
 * @dev Includes the implementation for health factor logic used by both
 *         the CompoundV3SupplyAdaptor && CompoundV3DebtAdaptor.
 * @author crispymangoes, 0xEinCodes
 * NOTE: helper functions made virtual in case future versions require different implementation logic. The logic here is written in compliance with CompoundV3
 */
abstract contract CompoundV3ExtraLogic {
    using Math for uint256;

    /**
     * @notice Attempted to interact with a Compound Lending Market (compMarket) the Cellar is not using.
     */
    error CompoundV3ExtraLogic__MarketPositionsMustBeTracked(address compMarket);

    /**
     * @notice Get current collateral balance for caller in specified CompMarket and Collateral Asset.
     * @dev Queries the `CometStorage.sol` nested mapping for struct UserCollateral.
     * @param _fraxlendPair The specified Fraxlend Pair
     * @param _user The specified user
     * @return collateralBalance of user in fraxlend pair
     */
    function _userCollateralBalance(
        CometInterface _compMarket,
        address _asset
    ) internal view virtual returns (uint256 collateralBalance) {
        UserCollateral userCollateral = _compMarket.userCollateral(address(_compMarket), _asset);
        return userCollateral.balance;
    }

    /**
     * @notice Allows strategists to claim `rewards` from carrying out certain functionalities within compoundV3 lending markets.
     * @param _compMarket the specified compMarket
     * @param _shouldAccrue if true, the protocol will account for the rewards owed to the account as of the current block before transferring.
     * NOTE: it is up to the Strategist how to handle protocol rewards. Ex.) They can re-invest the rewards into the strategy, or they could simply have ERC20 positions keeping track of said rewards.
     */
    function claimRewards(CometInterface _compMarket, bool _shouldAccrue) internal virtual {
        _validateCompMarket(_compMarket);
        ERC20 baseAsset = ERC20(_compMarket.baseToken());
        _compMarket.claim(address(_compMarket), address(this), _shouldAccrue);
    }

    /**
     * @notice Validates that a given CompMarket and Asset are set up as a position in the Cellar.
     * @dev This function uses `address(this)` as the address of the Cellar.
     */
    function _validateCompMarket(CometInterface _compMarket) internal view virtual {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(_compMarket)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert CompoundV3ExtraLogic__MarketPositionsMustBeTracked(address(_compMarket));
    }

    /**
     * @notice Validates that a given CompMarket and Asset are set up as a position in the Cellar.
     * @dev This function uses `address(this)` as the address of the Cellar.
     */
    function _validateCompMarketAndAsset(CometInterface _compMarket, ERC20 _asset) internal view virtual {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(_compMarket, _asset)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert CompoundV3ExtraLogic__MarketAndAssetPositionsMustBeTracked(
                address(_compMarket),
                address(_asset)
            );
    }
}
