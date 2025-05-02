## **Summary of the project:**
The LandManager contract is part of a virtual land and farming protocol where users can stake NFT characters (Munchables) on plots of land owned by landlords. This contract manages the relationship between landlords who own plots of land and users who stake their Munchable NFTs on these plots to earn rewards in the form of "Schnibbles."

The protocol implements a virtual real estate and farming economy with the following key components:

- **Land Ownership**: Users can become landlords by locking tokens, which determines how many plots of land they own. The number of plots is calculated based on the locked weighted value divided by the price per plot.

- **Tax System**: Landlords can set a tax rate (within minimum and maximum bounds) that determines what percentage of Schnibbles they collect from users farming on their land.

- **Staking Mechanism**: Users can stake their Munchable NFTs on available plots owned by landlords. When staked, the NFT is transferred to the LandManager contract and begins generating Schnibbles.

- **Reward Generation**: Staked Munchables generate Schnibbles over time at a base rate, with bonuses applied based on the Munchable's realm and rarity attributes, as well as the landlord's "snuggery realm."

- **Revenue Sharing**: When rewards are harvested through the "farmPlots" function, they are split between the Munchable owner and the landlord according to the tax rate.

- **Plot Management**: Users can transfer their staked Munchables between unoccupied plots or unstake them completely to retrieve their NFTs.

The contract integrates with several other components of the ecosystem:
- LockManager: Tracks locked tokens that determine land ownership
- AccountManager: Manages player accounts and metadata
- MunchNFT: The ERC721 token representing Munchable characters
- NFTAttributesManager: Stores and provides attributes for the NFTs

### Main Entry Points and Actors:

1. **updateTaxRate(uint256 newTaxRate)**
   - Actor: Landlord
   - Purpose: Allows landlords to update the tax rate they charge to users farming on their plots.

2. **triggerPlotMetadata()**
   - Actor: Landlord
   - Purpose: Initializes plot metadata for landlords who locked tokens before the land manager was deployed.

3. **stakeMunchable(address landlord, uint256 tokenId, uint256 plotId)**
   - Actor: Munchable owner
   - Purpose: Stakes a Munchable NFT on a specific plot owned by a landlord.

4. **unstakeMunchable(uint256 tokenId)**
   - Actor: Munchable owner
   - Purpose: Removes a staked Munchable from a plot and returns it to the owner.

5. **transferToUnoccupiedPlot(uint256 tokenId, uint256 plotId)**
   - Actor: Munchable owner
   - Purpose: Moves a staked Munchable from one plot to another unoccupied plot owned by the same landlord.

6. **farmPlots()**
   - Actor: Munchable owner
   - Purpose: Harvests Schnibbles rewards from all staked Munchables owned by the caller, distributing them between the owner and landlords according to tax rates.

## **Documentation of the project (if any):**

# Additional Documentation

Q: Are there any limitations on values set by admins (or other roles) in the codebase or in protocols you integrate with, including restrictions on array lengths?
A: The objective of the game is to earn as many Munch Points as possible. In crypto terms, you could call this "point farming". Built on top of Blast, Munchables leverages the unique on-chain primitives to create a reward-filled journey. Players collect Munchables and keep them safe, fed and comfortable in their snuggery. Once in a snuggery, a Munchable can start earning rewards for that player. A variety of factors influence the rewards earned, so players will have to be smart when choosing which Munchables to put in their snuggery and the strategies they use to play the game.

Q: Is the codebase expected to comply with any specific EIPs?
A: The game works as follows:

As a player, your primary goal is to earn as many MUNCH points (which will eventually be converted into the $MUNCH token) as possible. To earn MUNCH points, you must own 1 or more Munchables (NFT) and be very diligent about feeding it, petting other Munchables, and referring more people. Each Munchable that is created is one of 125 different types, each one being not only a different creature, but having multiple different attributes that have an effect on the balance of the game (and future spin-off games).

To obtain a Munchable, one must either migrate an existing Munchable from season 1 (more on Migration later), lock up funds for a set period of time (USDB, WETH, or ETH), buy one on the open market, or mint a primordial and level them up from level -3 to 0 to hatch a new Munchable.

With this Munchable (or Munchables), you can start playing with the game by entering it into your Snuggery. This Snuggery can be considered a little home for your Munchables and can be customized at the start of your game. You can input up to 6 Munchables at any given time but can obtain more slots in your Snuggery by converting MUNCH points to slots.

Once you have some Munchables in your Snuggery, you can start feeding them Schnibbles. Munchables are always hungry so they want as many Schnibbles as possible! You get an allocated number of Schnibbles based on these factors:

How much money you have locked
Whether you have a migration bonus (detailed later)
The impact of those Schnibbles is weighted differently however when you actually feed them to your Munchable and convert them to Chonks (think of it like XP for a Munchable). Everytime you reach a certain new threshold of Chonks for a Munchable, it reaches a new level horizon. Each level-up will trigger an increase in stats and eventually an evolution into a newer Munchable! While these don't have much of an effect on the game currently, future spin-off games will use these stats as a primary focus (and you can bet that you will be able to earn many more MUNCH points when it comes to)!

The Migration mechanic is split into three parts (these are not finalized):

You had a Munchable minted from season 1's lock conract. In order to get it back with full atttributes, you need to lock in at least half of the amount you locked in the previous season. For each additional amount locked, you will receive an extra migration bonus that gives you additional daily Schnibbles.
You had a Munchable bought from the open-market and want to convert it over to season 2. For this, just lock in 1 ETH equivalent per Munchable.
You no longer want to participate in the game and so you burn your old Munchable into a set amount of Munch points.
A general overview of our smart contract system is as follows:

The core components are split into 5 categories:
Managers: A general term to describe all of the smart contracts that interface with external-facing actions.
Config Storage: A central store of all updateable information across the rest of the system. Every other contract in the system inherits a BaseConfigStorage contract that handles the initialization and connection to the ConfigStorage contract.
RNG Proxy: This proxy contract handles updating on-chain randomness factors (primarily used for randomly-generating NFT attributes).
Tokens: MunchNFT is our primary NFT ERC-721 contract and Munch is a contract built for future use as the internal ERC-20 token.
Distributors: We decoupled the RewardsManager (more specifics on it below) from its Distributor contracts so that we can easily create new contracts that handle the dispersion or collection of revenue in the future.
This document will not go into details about specific methods, functions, errors, etc. as those can be viewed from running the command pnpm serve:doc



## **Invariants to consider (if any):**
```json
{"invariants": [{"description": "Current tax rate after update is within allowed bounds", "function": "updateTaxRate", "condition": "```solidity\nplotMetadata[landlord].currentTaxRate >= MIN_TAX_RATE &&\nplotMetadata[landlord].currentTaxRate <= MAX_TAX_RATE\n```", "path": "src/managers/LandManager.sol"}, {"description": "After triggerPlotMetadata, metadata initialized", "function": "triggerPlotMetadata", "condition": "```solidity\nplotMetadata[mainAccount].lastUpdated == block.timestamp &&\nplotMetadata[mainAccount].currentTaxRate == DEFAULT_TAX_RATE\n```", "path": "src/managers/LandManager.sol"}, {"description": "After updatePlotMetadata, metadata lastUpdated is set", "function": "updatePlotMetadata", "condition": "```solidity\nplotMetadata[landlord].lastUpdated == block.timestamp\n```", "path": "src/managers/LandManager.sol"}, {"description": "Stake does not increase staked munchables beyond limit", "function": "stakeMunchable", "condition": "```solidity\nmunchablesStaked[mainAccount].length <= 10\n```", "path": "src/managers/LandManager.sol"}, {"description": "After staking, plot is marked occupied", "function": "stakeMunchable", "condition": "```solidity\nplotOccupied[landlord][plotId].occupied == true &&\nplotOccupied[landlord][plotId].tokenId == tokenId\n```", "path": "src/managers/LandManager.sol"}, {"description": "After staking, munchableOwner maps token to staker", "function": "stakeMunchable", "condition": "```solidity\nmunchableOwner[tokenId] == mainAccount\n```", "path": "src/managers/LandManager.sol"}, {"description": "toilerState initialized correctly on stake", "function": "stakeMunchable", "condition": "```solidity\ntoilerState[tokenId] == ToilerState({\n  lastToilDate: block.timestamp,\n  plotId: plotId,\n  landlord: landlord,\n  latestTaxRate: plotMetadata[landlord].currentTaxRate,\n  dirty: false\n})\n```", "path": "src/managers/LandManager.sol"}, {"description": "PRICE_PER_PLOT is non-zero", "function": "_reconfigure", "condition": "```solidity\nPRICE_PER_PLOT > 0\n```", "path": "src/managers/LandManager.sol"}, {"description": "DEFAULT_TAX_RATE within bounds", "function": "_reconfigure", "condition": "```solidity\nDEFAULT_TAX_RATE >= MIN_TAX_RATE &&\nDEFAULT_TAX_RATE <= MAX_TAX_RATE\n```", "path": "src/managers/LandManager.sol"}, {"description": "After unstaking, plot is marked unoccupied", "function": "unstakeMunchable", "condition": "```solidity\nplotOccupied[landlord][plotId].occupied == false &&\nplotOccupied[landlord][plotId].tokenId == 0\n```", "path": "src/managers/LandManager.sol"}, {"description": "After unstaking, munchableOwner cleared", "function": "unstakeMunchable", "condition": "```solidity\nmunchableOwner[tokenId] == address(0)\n```", "path": "src/managers/LandManager.sol"}, {"description": "After unstaking, toilerState reset", "function": "unstakeMunchable", "condition": "```solidity\ntoilerState[tokenId] == ToilerState({\n  lastToilDate: 0,\n  plotId: 0,\n  landlord: address(0),\n  latestTaxRate: 0,\n  dirty: false\n})\n```", "path": "src/managers/LandManager.sol"}, {"description": "After unstaking, munchablesStaked does not contain tokenId", "function": "unstakeMunchable", "condition": "```solidity\n!munchablesStaked[mainAccount].includes(tokenId)\n```", "path": "src/managers/LandManager.sol"}, {"description": "Transfer to new plot updates occupancy correctly", "function": "transferToUnoccupiedPlot", "condition": "```solidity\nplotOccupied[landlord][oldPlotId].occupied == false &&\nplotOccupied[landlord][plotId].occupied == true\n```", "path": "src/managers/LandManager.sol"}, {"description": "Transfer to new plot updates latestTaxRate", "function": "transferToUnoccupiedPlot", "condition": "```solidity\ntoilerState[tokenId].latestTaxRate == plotMetadata[landlord].currentTaxRate\n```", "path": "src/managers/LandManager.sol"}, {"description": "After transfer, toilerState.plotId updated", "function": "transferToUnoccupiedPlot", "condition": "```solidity\ntoilerState[tokenId].plotId == plotId\n```", "path": "src/managers/LandManager.sol"}, {"description": "_removeTokenIdFromStakedList removes the token", "function": "_removeTokenIdFromStakedList", "condition": "```solidity\n!munchablesStaked[mainAccount].includes(tokenId) &&\nmunchablesStaked[mainAccount].length == oldLength - 1\n```", "path": "src/managers/LandManager.sol"}, {"description": "_getNumPlots computes based on lockManager", "function": "_getNumPlots", "condition": "```solidity\n_getNumPlots(account) == lockManager.getLockedWeightedValue(account) / PRICE_PER_PLOT\n```", "path": "src/managers/LandManager.sol"}, {"description": "In farming, total schnibbles split equals total", "function": "_farmPlots", "condition": "```solidity\n(schnibblesTotal - schnibblesLandlord) + schnibblesLandlord == schnibblesTotal\n```", "path": "src/managers/LandManager.sol"}, {"description": "In farming, landlord allocation never exceeds total schnibbles", "function": "_farmPlots", "condition": "```solidity\nschnibblesLandlord <= schnibblesTotal\n```", "path": "src/managers/LandManager.sol"}, {"description": "toilerState.lastToilDate updated to at most block.timestamp", "function": "_farmPlots", "condition": "```solidity\ntoilerState[tokenId].lastToilDate <= block.timestamp\n```", "path": "src/managers/LandManager.sol"}, {"description": "Dirty flag set when plot count decreases", "function": "_farmPlots", "condition": "```solidity\nif (_getNumPlots(landlord) < _toiler.plotId) {\n  toilerState[tokenId].dirty == true\n}\n```", "path": "src/managers/LandManager.sol"}, {"description": "Only registered players can operate", "function": "_getMainAccountRequireRegistered", "condition": "```solidity\naccountManager.getPlayer(_account).registrationDate != 0\n```", "path": "src/managers/LandManager.sol"}, {"description": "Tax rate update requires metadata initialized", "function": "updateTaxRate", "condition": "```solidity\nplotMetadata[landlord].lastUpdated != 0\n```", "path": "src/managers/LandManager.sol"}, {"description": "Stake requires approved or operator rights", "function": "stakeMunchable", "condition": "```solidity\nmunchNFT.isApprovedForAll(mainAccount, address(this)) ||\nmunchNFT.getApproved(tokenId) == address(this)\n```", "path": "src/managers/LandManager.sol"}, {"description": "Unstake only if owned by staker", "function": "unstakeMunchable", "condition": "```solidity\nmunchableOwner[tokenId] == mainAccount\n```", "path": "src/managers/LandManager.sol"}, {"description": "Plot ID within available plots on stake", "function": "stakeMunchable", "condition": "```solidity\nplotId < _getNumPlots(landlord)\n```", "path": "src/managers/LandManager.sol"}, {"description": "Cannot stake to self", "function": "stakeMunchable", "condition": "```solidity\nlandlord != mainAccount\n```", "path": "src/managers/LandManager.sol"}, {"description": "Cannot transfer to occupied plot", "function": "transferToUnoccupiedPlot", "condition": "```solidity\nplotOccupied[landlord][plotId].occupied == false\n```", "path": "src/managers/LandManager.sol"}]}
```

## **Additional context from web to assist with the audit (if any):**
## Solidity Compiler v0.8.25 – Security Considerations

- **Transient Storage Warning**  
  - Since v0.8.24, using the `tstore` opcode in inline assembly emits a compiler warning.  
  - In v0.8.25 the warning is emitted only _once_ per compilation (at the first `tstore` use) to reduce noise while still highlighting potential risks of transient (ephemeral) storage writes.

- **MCOPY Opcode**  
  - The code generator now emits the new `mcopy()` opcode instead of looping `mload()`/`mstore()` for contiguous memory copies.  
  - Benefits are modest gas savings for encoding/decoding byte arrays, but no change in cost for copying between memory and calldata/storage/returndata.  
  - Auditors should verify that any custom assembly still handles copying correctly, especially for non‐contiguous or complex data structures.

- **EVM Version Update**  
  - Default EVM target is now `"cancun"` (post-Dencun hard fork).  
  - Ensure contracts compiled with v0.8.25 are tested against the same EVM version to avoid subtle execution mismatches.

---

## ERC-721 (NFT) Security Best Practices

- **Use of OpenZeppelin’s `safeTransferFrom`**  
  - Prevents tokens from being locked in non-compliant contracts by calling `onERC721Received` and checking for the magic return value `0x150b7a02`.  
  - **Beware**: the external call introduces a reentrancy risk; use a reentrancy guard or the checks-effects-interactions pattern.

- **Approval Management**  
  - Only one approval per token (`approve`) or a blanket operator approval (`setApprovalForAll`).  
  - Protect against front-running: revoke or reset approvals (`approve(address(0))`) before granting new ones.

- **Custom Errors (EIP-6093)**  
  - OpenZeppelin v5+ uses custom errors for better gas efficiency and explicit failure modes (e.g., `ERC721IncorrectOwner`, `ERC721NonexistentToken`).

- **Basic Example**  
  ```solidity
  // SPDX-License-Identifier: MIT
  pragma solidity ^0.8.0;

  import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
  import "@openzeppelin/contracts/access/Ownable.sol";
  import "@openzeppelin/contracts/security/Pausable.sol";

  contract MyNFT is ERC721, Ownable, Pausable {
      uint256 public nextTokenId;

      function initialize(string memory name_, string memory symbol_) external {
          // If using an upgradeable pattern, replace constructor logic with initializer
      }

      function mint(address to) external onlyOwner whenNotPaused {
          _safeMint(to, nextTokenId);
          nextTokenId++;
      }

      function pause() external onlyOwner {
          _pause();
      }

      function unpause() external onlyOwner {
          _unpause();
      }
  }
  ```

---

## Upgradeable Contracts – Initializers

- **No Constructors**  
  - Proxy-based upgradeable contracts cannot use constructors; all setup must happen in an `initialize` function.

- **`initializer` Modifier**  
  - Provided by OpenZeppelin’s `Initializable` base contract to prevent multiple invocations and re-entrancy during initialization.

- **Explicit Parent Initializers**  
  - In case of multiple inheritance, you must call each parent’s initializer explicitly:
    ```solidity
    pragma solidity ^0.8.0;
    import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

    contract BaseContract is Initializable {
        uint256 public y;
        function __BaseContract_init() internal onlyInitializing {
            y = 42;
        }
    }

    contract MyContract is Initializable, BaseContract {
        uint256 public x;

        function initialize(uint256 _x) public initializer {
            __BaseContract_init();  // must call parent
            x = _x;
        }
    }
    ```

- **Locking the Implementation**  
  - Protect the logic contract from direct initialization by calling `_disableInitializers()` in its constructor:
    ```solidity
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    ```

---

## UUPS Initializer Best Practices

When combining multiple OpenZeppelin modules (e.g., `ERC721PausableUpgradeable` and `ERC721BurnableUpgradeable`), **always** call each module’s initializer—even if they share common ancestors—to guard against future additions:

```solidity
function initialize() public initializer {
    __ERC721_init("My Token", "TOKEN");
    __ERC721Pausable_init();
    __ERC721Burnable_init();  // explicit call prevents missing future setup
    __Ownable_init();
}
```

---

## Delegatecall Storage Collision Vulnerability

A proxy using `delegatecall` must align its storage layout exactly with the implementation. Misalignment can let attackers overwrite critical slots:

```solidity
contract VulnerableProxy {
    address public libraryContract;  // slot 0
    address public owner;            // slot 1

    bytes4 constant setOwnerSig = bytes4(keccak256("setOwner(uint256)"));

    constructor(address _lib) {
        libraryContract = _lib;
        owner = msg.sender;
    }

    function updateOwner(uint256 _newOwner) public {
        libraryContract.delegatecall(
            abi.encodePacked(setOwnerSig, _newOwner)
        );
    }
}

contract LibraryContract {
    address public owner;  // writes to slot 1 of proxy

    function setOwner(uint256 _owner) public {
        owner = address(uint160(_owner));
    }
}
```

**Mitigations**  
- Use unstructured storage patterns (EIP-1967).  
- Reserve storage gaps for future variables.  
- Adopt audited proxy standards (Transparent or UUPS).  
- Restrict access to upgrade and `delegatecall` targets.

---

## Insecure Randomness (SC09:2025)

**Vulnerable Example**  
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract InsecureRandomness {
    function guess(uint256 _guess) public payable {
        uint256 answer = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.difficulty,
                    msg.sender
                )
            )
        );
        if (_guess == answer) {
            payable(msg.sender).transfer(1 ether);
        }
    }
}
```
*Miner‐controllable block fields and predictability allow front-running or timestamp manipulation.*

**Fixed with Chainlink VRF**  
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

contract SecureRandomness is VRFConsumerBase {
    bytes32 internal keyHash;
    uint256 internal fee;
    uint256 public randomResult;

    constructor(
        address vrfCoordinator,
        address linkToken,
        bytes32 _keyHash,
        uint256 _fee
    ) VRFConsumerBase(vrfCoordinator, linkToken) {
        keyHash = _keyHash;
        fee = _fee;
    }

    function requestRandomNumber() public returns (bytes32) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK");
        return requestRandomness(keyHash, fee);
    }

    function fulfillRandomness(bytes32, uint256 randomness) internal override {
        randomResult = randomness;
    }
}
```

---

## Common Vulnerability Classes (RareSkills)

- Reentrancy via external calls (use guards, Checks-Effects-Interactions)  
- Access Control mistakes (missing `require`, faulty modifiers)  
- Improper Input Validation (e.g., unchecked array indexes, missing state‐flag updates)  
- Flashloan & Oracle manipulation (price or governance)  
- Unsafe randomness (don’t rely on block fields)  
- Implicit type conversions and overflow/underflow (use SafeMath/SafeCast)  
- Storage pointer and deletion pitfalls (deleting structs with dynamic members)  
- Delegatecall and upgrade pattern bugs (storage collisions, uninitialized logic contracts)  
- Front-running & sandwich attacks (manage approvals and slippage)  
- Signature replay or malleability (include nonces, use ECDSA libraries)  
- Low-level calls with unchecked returns (`.call` must check success)  

Auditors should use this checklist alongside static analysis tools (Slither, Echidna), thorough unit/fuzz testing, and formal verification where appropriate.

---

## **Contracts to audit:**
```solidity
// File: LandManager.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "../interfaces/ILandManager.sol";
import "../interfaces/ILockManager.sol";
import "../interfaces/IAccountManager.sol";
import "./BaseBlastManagerUpgradeable.sol";
import "../interfaces/INFTAttributesManager.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

contract LandManager is BaseBlastManagerUpgradeable, ILandManager {
    uint256 MIN_TAX_RATE;
    uint256 MAX_TAX_RATE;
    uint256 DEFAULT_TAX_RATE;
    uint256 BASE_SCHNIBBLE_RATE;
    uint256 PRICE_PER_PLOT;
    int16[] REALM_BONUSES;
    uint8[] RARITY_BONUSES;

    // landlord to plot metadata
    mapping(address => PlotMetadata) plotMetadata;
    // landlord to plot id to plot
    mapping(address => mapping(uint256 => Plot)) plotOccupied;
    // token id to original owner
    mapping(uint256 => address) munchableOwner;
    // main account to staked munchables list
    mapping(address => uint256[]) munchablesStaked;
    // token id -> toiler state
    mapping(uint256 => ToilerState) toilerState;

    ILockManager lockManager;
    IAccountManager accountManager;
    IERC721 munchNFT;
    INFTAttributesManager nftAttributesManager;

    constructor() {
        _disableInitializers();
    }

    modifier forceFarmPlots(address _account) {
        _farmPlots(_account);
        _;
    }

    function initialize(address _configStorage) public override initializer {
        BaseBlastManagerUpgradeable.initialize(_configStorage);
        _reconfigure();
    }

    function _reconfigure() internal {
        // load config from the config storage contract and configure myself
        lockManager = ILockManager(
            IConfigStorage(configStorage).getAddress(StorageKey.LockManager)
        );
        accountManager = IAccountManager(
            IConfigStorage(configStorage).getAddress(StorageKey.AccountManager)
        );
        munchNFT = IERC721(configStorage.getAddress(StorageKey.MunchNFT));
        nftAttributesManager = INFTAttributesManager(
            IConfigStorage(configStorage).getAddress(
                StorageKey.NFTAttributesManager
            )
        );

        MIN_TAX_RATE = IConfigStorage(configStorage).getUint(
            StorageKey.LockManager
        );
        MAX_TAX_RATE = IConfigStorage(configStorage).getUint(
            StorageKey.AccountManager
        );
        DEFAULT_TAX_RATE = IConfigStorage(configStorage).getUint(
            StorageKey.ClaimManager
        );
        BASE_SCHNIBBLE_RATE = IConfigStorage(configStorage).getUint(
            StorageKey.MigrationManager
        );
        PRICE_PER_PLOT = IConfigStorage(configStorage).getUint(
            StorageKey.NFTOverlord
        );
        REALM_BONUSES = configStorage.getSmallIntArray(StorageKey.RealmBonuses);
        RARITY_BONUSES = configStorage.getSmallUintArray(
            StorageKey.RarityBonuses
        );

        __BaseBlastManagerUpgradeable_reconfigure();
    }

    function configUpdated() external override onlyConfigStorage {
        _reconfigure();
    }

    function updateTaxRate(uint256 newTaxRate) external override notPaused {
        (address landlord, ) = _getMainAccountRequireRegistered(msg.sender);
        if (newTaxRate < MIN_TAX_RATE || newTaxRate > MAX_TAX_RATE)
            revert InvalidTaxRateError();
        if (plotMetadata[landlord].lastUpdated == 0)
            revert PlotMetadataNotUpdatedError();
        uint256 oldTaxRate = plotMetadata[landlord].currentTaxRate;
        plotMetadata[landlord].currentTaxRate = newTaxRate;
        emit TaxRateChanged(landlord, oldTaxRate, newTaxRate);
    }

    // Only to be triggered by msg sender if they had locked before the land manager was deployed
    function triggerPlotMetadata() external override notPaused {
        (address mainAccount, ) = _getMainAccountRequireRegistered(msg.sender);
        if (plotMetadata[mainAccount].lastUpdated != 0)
            revert PlotMetadataTriggeredError();
        plotMetadata[mainAccount] = PlotMetadata({
            lastUpdated: block.timestamp,
            currentTaxRate: DEFAULT_TAX_RATE
        });

        emit UpdatePlotsMeta(mainAccount);
    }

    function updatePlotMetadata(
        address landlord
    ) external override onlyConfiguredContract(StorageKey.AccountManager) {
        if (plotMetadata[landlord].lastUpdated == 0) {
            plotMetadata[landlord] = PlotMetadata({
                lastUpdated: block.timestamp,
                currentTaxRate: DEFAULT_TAX_RATE
            });
        } else {
            plotMetadata[landlord].lastUpdated = block.timestamp;
        }

        emit UpdatePlotsMeta(landlord);
    }

    function stakeMunchable(
        address landlord,
        uint256 tokenId,
        uint256 plotId
    ) external override forceFarmPlots(msg.sender) notPaused {
        (address mainAccount, ) = _getMainAccountRequireRegistered(msg.sender);
        if (landlord == mainAccount) revert CantStakeToSelfError();
        if (plotOccupied[landlord][plotId].occupied)
            revert OccupiedPlotError(landlord, plotId);
        if (munchablesStaked[mainAccount].length > 10)
            revert TooManyStakedMunchiesError();
        if (munchNFT.ownerOf(tokenId) != mainAccount)
            revert InvalidOwnerError();

        uint256 totalPlotsAvail = _getNumPlots(landlord);
        if (plotId >= totalPlotsAvail) revert PlotTooHighError();

        if (
            !munchNFT.isApprovedForAll(mainAccount, address(this)) &&
            munchNFT.getApproved(tokenId) != address(this)
        ) revert NotApprovedError();
        munchNFT.transferFrom(mainAccount, address(this), tokenId);

        plotOccupied[landlord][plotId] = Plot({
            occupied: true,
            tokenId: tokenId
        });

        munchablesStaked[mainAccount].push(tokenId);
        munchableOwner[tokenId] = mainAccount;

        toilerState[tokenId] = ToilerState({
            lastToilDate: block.timestamp,
            plotId: plotId,
            landlord: landlord,
            latestTaxRate: plotMetadata[landlord].currentTaxRate,
            dirty: false
        });

        emit FarmPlotTaken(toilerState[tokenId], tokenId);
    }

    function unstakeMunchable(
        uint256 tokenId
    ) external override forceFarmPlots(msg.sender) notPaused {
        (address mainAccount, ) = _getMainAccountRequireRegistered(msg.sender);
        ToilerState memory _toiler = toilerState[tokenId];
        if (_toiler.landlord == address(0)) revert NotStakedError();
        if (munchableOwner[tokenId] != mainAccount) revert InvalidOwnerError();

        plotOccupied[_toiler.landlord][_toiler.plotId] = Plot({
            occupied: false,
            tokenId: 0
        });
        toilerState[tokenId] = ToilerState({
            lastToilDate: 0,
            plotId: 0,
            landlord: address(0),
            latestTaxRate: 0,
            dirty: false
        });
        munchableOwner[tokenId] = address(0);
        _removeTokenIdFromStakedList(mainAccount, tokenId);

        munchNFT.transferFrom(address(this), mainAccount, tokenId);
        emit FarmPlotLeave(_toiler.landlord, tokenId, _toiler.plotId);
    }

    function transferToUnoccupiedPlot(
        uint256 tokenId,
        uint256 plotId
    ) external override forceFarmPlots(msg.sender) notPaused {
        (address mainAccount, ) = _getMainAccountRequireRegistered(msg.sender);
        ToilerState memory _toiler = toilerState[tokenId];
        uint256 oldPlotId = _toiler.plotId;
        uint256 totalPlotsAvail = _getNumPlots(_toiler.landlord);
        if (_toiler.landlord == address(0)) revert NotStakedError();
        if (munchableOwner[tokenId] != mainAccount) revert InvalidOwnerError();
        if (plotOccupied[_toiler.landlord][plotId].occupied)
            revert OccupiedPlotError(_toiler.landlord, plotId);
        if (plotId >= totalPlotsAvail) revert PlotTooHighError();

        toilerState[tokenId].latestTaxRate = plotMetadata[_toiler.landlord]
            .currentTaxRate;
        plotOccupied[_toiler.landlord][oldPlotId] = Plot({
            occupied: false,
            tokenId: 0
        });
        plotOccupied[_toiler.landlord][plotId] = Plot({
            occupied: true,
            tokenId: tokenId
        });

        emit FarmPlotLeave(_toiler.landlord, tokenId, oldPlotId);
        emit FarmPlotTaken(toilerState[tokenId], tokenId);
    }

    function farmPlots() external override notPaused {
        _farmPlots(msg.sender);
    }

    function _farmPlots(address _sender) internal {
        (
            address mainAccount,
            MunchablesCommonLib.Player memory renterMetadata
        ) = _getMainAccountRequireRegistered(_sender);

        uint256[] memory staked = munchablesStaked[mainAccount];
        MunchablesCommonLib.NFTImmutableAttributes memory immutableAttributes;
        ToilerState memory _toiler;
        uint256 timestamp;
        address landlord;
        uint256 tokenId;
        int256 finalBonus;
        uint256 schnibblesTotal;
        uint256 schnibblesLandlord;
        for (uint8 i = 0; i < staked.length; i++) {
            timestamp = block.timestamp;
            tokenId = staked[i];
            _toiler = toilerState[tokenId];
            if (_toiler.dirty) continue;
            landlord = _toiler.landlord;
            // use last updated plot metadata time if the plot id doesn't fit
            // track a dirty bool to signify this was done once
            // the edge case where this doesnt work is if the user hasnt farmed in a while and the landlord
            // updates their plots multiple times. then the last updated time will be the last time they updated their plot details
            // instead of the first
            if (_getNumPlots(landlord) < _toiler.plotId) {
                timestamp = plotMetadata[landlord].lastUpdated;
                toilerState[tokenId].dirty = true;
            }
            (
                ,
                MunchablesCommonLib.Player memory landlordMetadata
            ) = _getMainAccountRequireRegistered(landlord);

            immutableAttributes = nftAttributesManager.getImmutableAttributes(
                tokenId
            );
            finalBonus =
                int16(
                    REALM_BONUSES[
                        (uint256(immutableAttributes.realm) * 5) +
                            uint256(landlordMetadata.snuggeryRealm)
                    ]
                ) +
                int16(
                    int8(RARITY_BONUSES[uint256(immutableAttributes.rarity)])
                );
            schnibblesTotal =
                (timestamp - _toiler.lastToilDate) *
                BASE_SCHNIBBLE_RATE;
            schnibblesTotal = uint256(
                (int256(schnibblesTotal) +
                    (int256(schnibblesTotal) * finalBonus)) / 100
            );
            schnibblesLandlord =
                (schnibblesTotal * _toiler.latestTaxRate) /
                1e18;

            toilerState[tokenId].lastToilDate = timestamp;
            toilerState[tokenId].latestTaxRate = plotMetadata[_toiler.landlord]
                .currentTaxRate;

            renterMetadata.unfedSchnibbles += (schnibblesTotal -
                schnibblesLandlord);

            landlordMetadata.unfedSchnibbles += schnibblesLandlord;
            landlordMetadata.lastPetMunchable = uint32(timestamp);
            accountManager.updatePlayer(landlord, landlordMetadata);
            emit FarmedSchnibbles(
                _toiler.landlord,
                tokenId,
                _toiler.plotId,
                schnibblesTotal - schnibblesLandlord,
                schnibblesLandlord
            );
        }
        accountManager.updatePlayer(mainAccount, renterMetadata);
    }

    function _removeTokenIdFromStakedList(
        address mainAccount,
        uint256 tokenId
    ) internal {
        uint256 stakedLength = munchablesStaked[mainAccount].length;
        bool found = false;
        for (uint256 i = 0; i < stakedLength; i++) {
            if (munchablesStaked[mainAccount][i] == tokenId) {
                munchablesStaked[mainAccount][i] = munchablesStaked[
                    mainAccount
                ][stakedLength - 1];
                found = true;
                munchablesStaked[mainAccount].pop();
                break;
            }
        }

        if (!found) revert InvalidTokenIdError();
    }

    function _getMainAccountRequireRegistered(
        address _account
    ) internal view returns (address, MunchablesCommonLib.Player memory) {
        (
            address _mainAccount,
            MunchablesCommonLib.Player memory _player
        ) = accountManager.getPlayer(_account);

        if (_player.registrationDate == 0) revert PlayerNotRegisteredError();
        return (_mainAccount, _player);
    }

    function _getNumPlots(address _account) internal view returns (uint256) {
        return lockManager.getLockedWeightedValue(_account) / PRICE_PER_PLOT;
    }
}
```