# UI Flows and Sommelier Cellars


## Deposits

### Basic Deposits
All cellars possess a `deposit` and `mint` function. These functions are equivalent. This duplicate functionality is there to enable cellars to conform to the er4626 vault standard. The Cellar implementation overrides the default er4626.

We generally prefer deposit. Like other erc4626 vault, the deposit function takes a base asset stored in the asset variable and mints shares. The deposit functionality only supports this single asset.

The deposit function takes two arguments. The amount of the base asset and the address to recieve the share. The deposit function will mint the shares and send them to the reciever. The deposit function will also transfer the base asset from the sender to the cellar.

There is a also 'previewMint' function that allow a UI to simulate the deposit for the user. Note for any vault the uses the erc4626 price oracle fuctionality for share pricing will generally see the dollar redemeption value of the shares be lower than value of funds deposited. This functionality is reccomended because it results in dramatically lower gas costs for deposits and withdrawals.

### MultiAsset Deposits

The multiAssetDeposit function is an advanced and otional functionality that can be enabled when the cellar is constructed. This function allows the cellar to accept deposits of multiple assets. The multiAssetDeposit function takes three arguments. The type of asset being deposited, the amount of the base asset and the address to recieve the shares. The deposit function will covert the asset to base asset ad mint the shares and transfer them to the reciever.

The multiAssetDeposit functionality takes a fee on the deposit. This fee serves a couple of purposes but most importantly it prevents exploiting small price arbtrigages to get underpriced cellar shares.

The Strategist on a cellar can set all the supported asset with `setAlternativeAssetData`. The variable `alternativeAssetData` holds a map of ERC20 addresses to supported Alternative assets.

## Withdrawls
