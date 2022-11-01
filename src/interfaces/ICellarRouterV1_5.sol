pragma solidity ^0.8.10;

interface ICellarRouterV1_5 {
    function SWAP_ROUTER_REGISTRY_SLOT() external view returns (uint256);

    function depositAndSwap(
        address cellar,
        uint8 exchange,
        bytes memory swapData,
        uint256 assets,
        address assetIn
    ) external returns (uint256 shares);

    function depositAndSwapWithPermit(
        address cellar,
        uint8 exchange,
        bytes memory swapData,
        uint256 assets,
        address assetIn,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256 shares);

    function depositWithPermit(
        address cellar,
        uint256 assets,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256 shares);

    function registry() external view returns (address);

    function withdrawAndSwap(
        address cellar,
        uint8[] memory exchanges,
        bytes[] memory swapDatas,
        uint256 assets,
        address receiver
    ) external returns (uint256 shares);

    function withdrawAndSwapWithPermit(
        address cellar,
        uint8[] memory exchanges,
        bytes[] memory swapDatas,
        uint256 sharesToRedeem,
        uint256 deadline,
        bytes memory signature,
        address receiver
    ) external returns (uint256 shares);
}
