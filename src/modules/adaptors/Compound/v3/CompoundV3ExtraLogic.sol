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
 * NOTE: we inherit CometInterface in order to use the CometMath
 */
abstract contract CompoundV3ExtraLogic is CometInterface {
    using Math for uint256;

    /**
     * @notice Attempted to interact with a Compound Lending Market (compMarket) the Cellar is not using.
     */
    error CompoundV3ExtraLogic__MarketPositionsMustBeTracked(address compMarket);

    /**
     * @notice Attempted tx that results in unhealthy cellar
     */
    error CompoundV3ExtraLogic__PositionIsNotABorrowPosition(address compMarket);

    /**
     * @notice var referencing specific compMarket
     */
    uint8 public numAssets;

    /**
     * @notice Minimum Health Factor enforced after every borrow or added collateral
     * @notice Overwrites strategist set minimums if they are lower.
     */
    uint256 public immutable minimumHealthFactor;

    constructor(uint256 _healthFactor) {
        _verifyConstructorMinimumHealthFactor(_healthFactor);
        minimumHealthFactor = _healthFactor;
    }

    /**
     * @notice Minimum Health Factor enforced after every borrow.
     * @notice Overwrites strategist set minimums if they are lower.
     */
    uint256 public immutable minimumHealthFactor;

    constructor(bool _accountForInterest, address _frax, uint256 _healthFactor) {
        minimumHealthFactor = _healthFactor;
    }

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
            revert CompoundV3ExtraLogic__MarketAndAssetPositionsMustBeTracked(address(_compMarket), address(_asset));
    }

    function _checkLiquidity(CometInterface _compMarket) internal view virtual returns (int liquidity) {
        UserBasic userBasic = _compMarket.userBasic(address(this)); // struct should be accessible via extensions/inheritance within CometMainInterface
        int104 principal = userBasic.principal;

        if (principal >= 0) {
            revert CompoundV3ExtraLogic__PositionIsNotABorrowPosition(address(_compMarket));
        } // EIN: this just means that it was a non-borrow position, because `principal` is a signed integer, so if it's greater than 0, it is not a borrow position.

        uint16 assetsIn = userBasic[account].assetsIn; // EIN - collateral indices
        int liquidity = signedMulPrice(presentValue(principal), getPrice(baseTokenPriceFeed), uint64(baseScale));

        numAssets = _compMarket.numAssets();

        for (uint8 i = 0; i < numAssets; ) {
            if (isInAsset(assetsIn, i)) {
                AssetInfo memory asset = getAssetInfo(i);
                uint newAmount = mulPrice(
                    userCollateral[account][asset.asset].balance,
                    getPrice(asset.priceFeed),
                    asset.scale
                );
                liquidity += signed256(
                    mulFactor(newAmount, (asset.liquidateCollateralFactor) * (1 / minimumHealthFactor))
                ); // TODO: EIN - just need to get the math to compile and work in tests.
            }
            unchecked {
                i++;
            }
        }

        return liquidity;
    }

    /// helper functions from `Comet.sol` implementation logic

    /**
     * @notice Get the current price from a feed
     * @param priceFeed The address of a price feed
     * @return The price, scaled by `PRICE_SCALE`
     */
    function getPrice(address priceFeed) public view override returns (uint256) {
        (, int price, , , ) = IPriceFeed(priceFeed).latestRoundData();
        if (price <= 0) revert BadPrice();
        return uint256(price);
    }

    /**
     * @notice Get the i-th asset info, according to the order they were passed in originally
     * @param i The index of the asset info to get
     * @return The asset info object
     */
    function getAssetInfo(uint8 i) public view override returns (AssetInfo memory) {
        if (i >= numAssets) revert BadAsset();

        uint256 word_a;
        uint256 word_b;

        if (i == 0) {
            word_a = asset00_a;
            word_b = asset00_b;
        } else if (i == 1) {
            word_a = asset01_a;
            word_b = asset01_b;
        } else if (i == 2) {
            word_a = asset02_a;
            word_b = asset02_b;
        } else if (i == 3) {
            word_a = asset03_a;
            word_b = asset03_b;
        } else if (i == 4) {
            word_a = asset04_a;
            word_b = asset04_b;
        } else if (i == 5) {
            word_a = asset05_a;
            word_b = asset05_b;
        } else if (i == 6) {
            word_a = asset06_a;
            word_b = asset06_b;
        } else if (i == 7) {
            word_a = asset07_a;
            word_b = asset07_b;
        } else if (i == 8) {
            word_a = asset08_a;
            word_b = asset08_b;
        } else if (i == 9) {
            word_a = asset09_a;
            word_b = asset09_b;
        } else if (i == 10) {
            word_a = asset10_a;
            word_b = asset10_b;
        } else if (i == 11) {
            word_a = asset11_a;
            word_b = asset11_b;
        } else if (i == 12) {
            word_a = asset12_a;
            word_b = asset12_b;
        } else if (i == 13) {
            word_a = asset13_a;
            word_b = asset13_b;
        } else if (i == 14) {
            word_a = asset14_a;
            word_b = asset14_b;
        } else {
            revert Absurd();
        }

        address asset = address(uint160(word_a & type(uint160).max));
        uint64 rescale = FACTOR_SCALE / 1e4;
        uint64 borrowCollateralFactor = uint64(((word_a >> 160) & type(uint16).max) * rescale);
        uint64 liquidateCollateralFactor = uint64(((word_a >> 176) & type(uint16).max) * rescale);
        uint64 liquidationFactor = uint64(((word_a >> 192) & type(uint16).max) * rescale);

        address priceFeed = address(uint160(word_b & type(uint160).max));
        uint8 decimals_ = uint8(((word_b >> 160) & type(uint8).max));
        uint64 scale = uint64(10 ** decimals_);
        uint128 supplyCap = uint128(((word_b >> 168) & type(uint64).max) * scale);

        return
            AssetInfo({
                offset: i,
                asset: asset,
                priceFeed: priceFeed,
                scale: scale,
                borrowCollateralFactor: borrowCollateralFactor,
                liquidateCollateralFactor: liquidateCollateralFactor,
                liquidationFactor: liquidationFactor,
                supplyCap: supplyCap
            });
    }

    /**
     * @dev Whether user has a non-zero balance of an asset, given assetsIn flags
     */
    function isInAsset(uint16 assetsIn, uint8 assetOffset) internal pure returns (bool) {
        return (assetsIn & (uint16(1) << assetOffset) != 0);
    }

    /**
     * @dev Multiply a number by a factor
     */
    function mulFactor(uint n, uint factor) internal pure returns (uint) {
        return (n * factor) / FACTOR_SCALE;
    }

    /**
     * @dev Divide a number by an amount of base
     */
    function divBaseWei(uint n, uint baseWei) internal view returns (uint) {
        return (n * baseScale) / baseWei;
    }

    /**
     * @dev Multiply a `fromScale` quantity by a price, returning a common price quantity
     */
    function mulPrice(uint n, uint price, uint64 fromScale) internal pure returns (uint) {
        return (n * price) / fromScale;
    }

    /**
     * @dev Multiply a signed `fromScale` quantity by a price, returning a common price quantity
     */
    function signedMulPrice(int n, uint price, uint64 fromScale) internal pure returns (int) {
        return (n * signed256(price)) / int256(uint256(fromScale));
    }

    /**
     * @dev Divide a common price quantity by a price, returning a `toScale` quantity
     */
    function divPrice(uint n, uint price, uint64 toScale) internal pure returns (uint) {
        return (n * toScale) / price;
    }
}
