// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { MathUtils } from "../utils/MathUtils.sol";
import { IWETH } from "./IWETH.sol";

/// @notice Minimal ERC4626 tokenized Vault implementation.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/mixins/ERC4626.sol)
abstract contract ERC4626 is ERC20 {
    using SafeTransferLib for ERC20;
    using MathUtils for uint256;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    ERC20 public immutable asset;
    IWETH public WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        bool _assetIsETHInsteadOfWETH
    ) ERC20(_name, _symbol, _decimals) {
        asset = _asset;
        assetIsETHInsteadOfWETH = _assetIsETHInsteadOfWETH;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits assets and mints the shares to receiver.
     * @param assets amount of assets to deposit
     * @param receiver address receiving the shares
     * @return shares amount of shares minted
     */
    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        beforeDeposit(assets, shares, receiver);

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        if (address(asset) == address(WETH) && assetIsETHInsteadOfWETH)
            WETH.withdraw(assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares, receiver);
    }

    /**
     * @notice Mints shares to receiver by depositing assets.
     * @param shares amount of shares to mint
     * @param receiver address receiving the shares
     * @return assets amount of assets deposited
     */
    function mint(uint256 shares, address receiver) public virtual returns (uint256 assets) {
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        beforeDeposit(assets, shares, receiver);

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares, receiver);
    }

    /**
     * @notice Withdraws assets to receiver by redeeming shares from owner.
     * @param assets amount of assets being withdrawn
     * @param receiver address of account receiving the assets
     * @param owner address of the owner of the shares being redeemed
     * @return shares amount of shares redeemed
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets, shares, receiver, owner);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        if (address(asset) == address(WETH) && assetIsETHInsteadOfWETH)
            WETH.deposit{value: assets}();

        asset.safeTransfer(receiver, assets);

        afterWithdraw(assets, shares, receiver, owner);
    }

    /**
     * @notice Redeems shares from owner to withdraw assets to receiver.
     * @param shares amount of shares redeemed
     * @param receiver address of account receiving the assets
     * @param owner address of the owner of the shares being redeemed
     * @return assets amount of assets sent to receiver
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        beforeWithdraw(assets, shares, receiver, owner);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);

        afterWithdraw(assets, shares, receiver, owner);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view virtual returns (uint256);

    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
    }

    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return convertToAssets(shares);
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return convertToAssets(balanceOf[owner]);
    }

    function maxRedeem(address owner) public view virtual returns (uint256) {
        return balanceOf[owner];
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeDeposit(
        uint256 assets,
        uint256 shares,
        address receiver
    ) internal virtual {}

    function afterDeposit(
        uint256 assets,
        uint256 shares,
        address receiver
    ) internal virtual {}

    function beforeWithdraw(
        uint256 assets,
        uint256 shares,
        address receiver,
        address owner
    ) internal virtual {}

    function afterWithdraw(
        uint256 assets,
        uint256 shares,
        address receiver,
        address owner
    ) internal virtual {}

    /*///////////////////////////////////////////////////////////////
                   DEPOSIT/WITHDRAWAL FOR ETH
    //////////////////////////////////////////////////////////////*/

    bool public assetIsETHInsteadOfWETH;

    /**
    * @notice Deposits WETH, using native ETH, and mints the shares to receiver.
    * @param receiver address of the user who will receive minted shares
    * @return shares amount of shares minted
    **/
    function depositETH(address receiver) public payable virtual returns (uint256 shares) {
        require(address(asset) == address(WETH), "ASSET_NOT_WETH");

        uint256 assets = msg.value;

        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        beforeDeposit(assets, shares, receiver);

        if (!assetIsETHInsteadOfWETH)
            WETH.deposit{value: assets}();

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares, receiver);
    }

    /**
    * @notice Withdraws native ETH to receiver by redeeming shares from owner. 
    * @param assets amount of WETH being withdrawn and receive native ETH
    * @param receiver address of account who will receive native ETH
    * @param owner address of the user whose shares will be burnt
    * @return shares amount of shares redeemed
    **/
    function withdrawETH(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual returns (uint256 shares) {
        require(address(asset) == address(WETH), "ASSET_NOT_WETH");

        // if assets is equal to uint(-1), the user wants to redeem everything
        if (assets == type(uint256).max)
            assets = maxWithdraw(owner);

        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets, shares, receiver, owner);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        if (!assetIsETHInsteadOfWETH)
            WETH.withdraw(assets);

        _safeTransferETH(receiver, assets);

        afterWithdraw(assets, shares, receiver, owner);
    }

    /**
     * @notice Redeems shares from owner to withdraw native ETH to receiver.
     * @param shares amount of shares redeemed
     * @param receiver address of account receiving the native ETH
     * @param owner address of the owner of the shares being redeemed
     * @return assets amount of native ETH sent to receiver
     */
    function redeemETH(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual returns (uint256 assets) {
        require(address(asset) == address(WETH), "ASSET_NOT_WETH");

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        beforeWithdraw(assets, shares, receiver, owner);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        if (!assetIsETHInsteadOfWETH)
            WETH.withdraw(assets);

        _safeTransferETH(receiver, assets);

        afterWithdraw(assets, shares, receiver, owner);
    }

    /**
    * @dev transfers ETH to an address. Revert if it fails.
    * @param receiver receiver of the transfer
    * @param amount the amount of ETH to send
    */
    function _safeTransferETH(address receiver, uint256 amount) internal {
        (bool success, ) = receiver.call{value: amount}(new bytes(0));
        require(success, 'ETH_TRANSFER_FAILED');
    }
    
    receive() external payable {}
}
