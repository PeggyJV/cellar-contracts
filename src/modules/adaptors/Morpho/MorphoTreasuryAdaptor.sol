// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

interface IMorphoWrapper {
    function depositFor(address account, uint256 value) external returns (bool);
}

/// @title MorphoTreasuryAdaptor
/// @notice Single-purpose Sommelier cellar adaptor, run only through `callOnAdaptor` (delegatecall).
///         Wraps the cellar's entire Legacy MORPHO balance 1:1 into current MORPHO and sends it, plus any
///         current MORPHO the cellar already holds, to a fixed recipient. Every address is a constant:
///         there is no parameter a caller can use to redirect funds or approve another spender.
///         It backs no position: the position hooks all revert, so it can never be added as one.
contract MorphoTreasuryAdaptor {
    IERC20 public constant LEGACY_MORPHO = IERC20(0x9994E35Db50125E0DF82e4c2dde62496CE330999);
    IERC20 public constant MORPHO = IERC20(0x58D97B57BB95320F9a05dC918Aef65434969c2B2);
    IMorphoWrapper public constant WRAPPER = IMorphoWrapper(0x9D03bb2092270648d7480049d0E58d2FcF0E5123);
    address public constant RECIPIENT = 0x7566D348038d881475b5FE0638c00B391f9B33E6;

    error MorphoTreasuryAdaptor__NotAPosition();
    error MorphoTreasuryAdaptor__CallFailed();

    /// @dev Registry.trustAdaptor requires a unique identifier.
    function identifier() public pure returns (bytes32) {
        return keccak256(abi.encode("Morpho Treasury Adaptor V 1.0"));
    }

    /// @notice Wrap all Legacy MORPHO held by the calling cellar and deliver current MORPHO to RECIPIENT.
    function wrapLegacyToRecipient() external {
        uint256 amount = LEGACY_MORPHO.balanceOf(address(this));
        if (amount == 0) return;
        if (!LEGACY_MORPHO.approve(address(WRAPPER), amount)) revert MorphoTreasuryAdaptor__CallFailed();
        if (!WRAPPER.depositFor(RECIPIENT, amount)) revert MorphoTreasuryAdaptor__CallFailed();
        // Leave no allowance behind.
        if (!LEGACY_MORPHO.approve(address(WRAPPER), 0)) revert MorphoTreasuryAdaptor__CallFailed();
    }

    /// @notice Send all current MORPHO held by the calling cellar to RECIPIENT.
    function sweepMorphoToRecipient() external {
        uint256 amount = MORPHO.balanceOf(address(this));
        if (amount == 0) return;
        if (!MORPHO.transfer(RECIPIENT, amount)) revert MorphoTreasuryAdaptor__CallFailed();
    }

    // ---- Position hooks: this adaptor backs no position. ----
    function deposit(uint256, bytes memory, bytes memory) external pure { revert MorphoTreasuryAdaptor__NotAPosition(); }
    function withdraw(uint256, address, bytes memory, bytes memory) external pure { revert MorphoTreasuryAdaptor__NotAPosition(); }
    function withdrawableFrom(bytes memory, bytes memory) external pure returns (uint256) { revert MorphoTreasuryAdaptor__NotAPosition(); }
    function balanceOf(bytes memory) external pure returns (uint256) { revert MorphoTreasuryAdaptor__NotAPosition(); }
    function assetOf(bytes memory) external pure returns (address) { revert MorphoTreasuryAdaptor__NotAPosition(); }
    function assetsUsed(bytes memory) external pure returns (address[] memory) { revert MorphoTreasuryAdaptor__NotAPosition(); }
    function isDebt() external pure returns (bool) { revert MorphoTreasuryAdaptor__NotAPosition(); }
}
