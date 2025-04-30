    1 | // File: LandManager.sol
    2 | // SPDX-License-Identifier: UNLICENSED
    3 | pragma solidity 0.8.25;
    4 | 
    5 | import "../interfaces/ILandManager.sol";
    6 | import "../interfaces/ILockManager.sol";
    7 | import "../interfaces/IAccountManager.sol";
    8 | import "./BaseBlastManagerUpgradeable.sol";
    9 | import "../interfaces/INFTAttributesManager.sol";
   10 | import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
   11 | 
   12 | contract LandManager is BaseBlastManagerUpgradeable, ILandManager {
   13 |     uint256 MIN_TAX_RATE;
   14 |     uint256 MAX_TAX_RATE;
   15 |     uint256 DEFAULT_TAX_RATE;
   16 |     uint256 BASE_SCHNIBBLE_RATE;
   17 |     uint256 PRICE_PER_PLOT;
   18 |     int16[] REALM_BONUSES;
   19 |     uint8[] RARITY_BONUSES;
   20 | 
   21 |     // landlord to plot metadata
   22 |     mapping(address => PlotMetadata) plotMetadata;
   23 |     // landlord to plot id to plot
   24 |     mapping(address => mapping(uint256 => Plot)) plotOccupied;
   25 |     // token id to original owner
   26 |     mapping(uint256 => address) munchableOwner;
   27 |     // main account to staked munchables list
   28 |     mapping(address => uint256[]) munchablesStaked;
   29 |     // token id -> toiler state
   30 |     mapping(uint256 => ToilerState) toilerState;
   31 | 
   32 |     ILockManager lockManager;
   33 |     IAccountManager accountManager;
   34 |     IERC721 munchNFT;
   35 |     INFTAttributesManager nftAttributesManager;
   36 | 
   37 |     constructor() {
   38 |         _disableInitializers();
   39 |     }
   40 | 
   41 |     modifier forceFarmPlots(address _account) {
   42 |         _farmPlots(_account);
   43 |         _;
   44 |     }
   45 | 
   46 |     function initialize(address _configStorage) public override initializer {
   47 |         BaseBlastManagerUpgradeable.initialize(_configStorage);
   48 |         _reconfigure();
   49 |     }
   50 | 
   51 |     function _reconfigure() internal {
   52 |         // load config from the config storage contract and configure myself
   53 |         lockManager = ILockManager(
   54 |             IConfigStorage(configStorage).getAddress(StorageKey.LockManager)
   55 |         );
   56 |         accountManager = IAccountManager(
   57 |             IConfigStorage(configStorage).getAddress(StorageKey.AccountManager)
   58 |         );
   59 |         munchNFT = IERC721(configStorage.getAddress(StorageKey.MunchNFT));
   60 |         nftAttributesManager = INFTAttributesManager(
   61 |             IConfigStorage(configStorage).getAddress(
   62 |                 StorageKey.NFTAttributesManager
   63 |             )
   64 |         );
   65 | 
   66 |         MIN_TAX_RATE = IConfigStorage(configStorage).getUint(
   67 |             StorageKey.LockManager
   68 |         );
   69 |         MAX_TAX_RATE = IConfigStorage(configStorage).getUint(
   70 |             StorageKey.AccountManager
   71 |         );
   72 |         DEFAULT_TAX_RATE = IConfigStorage(configStorage).getUint(
   73 |             StorageKey.ClaimManager
   74 |         );
   75 |         BASE_SCHNIBBLE_RATE = IConfigStorage(configStorage).getUint(
   76 |             StorageKey.MigrationManager
   77 |         );
   78 |         PRICE_PER_PLOT = IConfigStorage(configStorage).getUint(
   79 |             StorageKey.NFTOverlord
   80 |         );
   81 |         REALM_BONUSES = configStorage.getSmallIntArray(StorageKey.RealmBonuses);
   82 |         RARITY_BONUSES = configStorage.getSmallUintArray(
   83 |             StorageKey.RarityBonuses
   84 |         );
   85 | 
   86 |         __BaseBlastManagerUpgradeable_reconfigure();
   87 |     }
   88 | 
   89 |     function configUpdated() external override onlyConfigStorage {
   90 |         _reconfigure();
   91 |     }
   92 | 
   93 |     function updateTaxRate(uint256 newTaxRate) external override notPaused {
   94 |         (address landlord, ) = _getMainAccountRequireRegistered(msg.sender);
   95 |         if (newTaxRate < MIN_TAX_RATE || newTaxRate > MAX_TAX_RATE)
   96 |             revert InvalidTaxRateError();
   97 |         if (plotMetadata[landlord].lastUpdated == 0)
   98 |             revert PlotMetadataNotUpdatedError();
   99 |         uint256 oldTaxRate = plotMetadata[landlord].currentTaxRate;
  100 |         plotMetadata[landlord].currentTaxRate = newTaxRate;
  101 |         emit TaxRateChanged(landlord, oldTaxRate, newTaxRate);
  102 |     }
  103 | 
  104 |     // Only to be triggered by msg sender if they had locked before the land manager was deployed
  105 |     function triggerPlotMetadata() external override notPaused {
  106 |         (address mainAccount, ) = _getMainAccountRequireRegistered(msg.sender);
  107 |         if (plotMetadata[mainAccount].lastUpdated != 0)
  108 |             revert PlotMetadataTriggeredError();
  109 |         plotMetadata[mainAccount] = PlotMetadata({
  110 |             lastUpdated: block.timestamp,
  111 |             currentTaxRate: DEFAULT_TAX_RATE
  112 |         });
  113 | 
  114 |         emit UpdatePlotsMeta(mainAccount);
  115 |     }
  116 | 
  117 |     function updatePlotMetadata(
  118 |         address landlord
  119 |     ) external override onlyConfiguredContract(StorageKey.AccountManager) {
  120 |         if (plotMetadata[landlord].lastUpdated == 0) {
  121 |             plotMetadata[landlord] = PlotMetadata({
  122 |                 lastUpdated: block.timestamp,
  123 |                 currentTaxRate: DEFAULT_TAX_RATE
  124 |             });
  125 |         } else {
  126 |             plotMetadata[landlord].lastUpdated = block.timestamp;
  127 |         }
  128 | 
  129 |         emit UpdatePlotsMeta(landlord);
  130 |     }
  131 | 
  132 |     function stakeMunchable(
  133 |         address landlord,
  134 |         uint256 tokenId,
  135 |         uint256 plotId
  136 |     ) external override forceFarmPlots(msg.sender) notPaused {
  137 |         (address mainAccount, ) = _getMainAccountRequireRegistered(msg.sender);
  138 |         if (landlord == mainAccount) revert CantStakeToSelfError();
  139 |         if (plotOccupied[landlord][plotId].occupied)
  140 |             revert OccupiedPlotError(landlord, plotId);
  141 |         if (munchablesStaked[mainAccount].length > 10)
  142 |             revert TooManyStakedMunchiesError();
  143 |         if (munchNFT.ownerOf(tokenId) != mainAccount)
  144 |             revert InvalidOwnerError();
  145 | 
  146 |         uint256 totalPlotsAvail = _getNumPlots(landlord);
  147 |         if (plotId >= totalPlotsAvail) revert PlotTooHighError();
  148 | 
  149 |         if (
  150 |             !munchNFT.isApprovedForAll(mainAccount, address(this)) &&
  151 |             munchNFT.getApproved(tokenId) != address(this)
  152 |         ) revert NotApprovedError();
  153 |         munchNFT.transferFrom(mainAccount, address(this), tokenId);
  154 | 
  155 |         plotOccupied[landlord][plotId] = Plot({
  156 |             occupied: true,
  157 |             tokenId: tokenId
  158 |         });
  159 | 
  160 |         munchablesStaked[mainAccount].push(tokenId);
  161 |         munchableOwner[tokenId] = mainAccount;
  162 | 
  163 |         toilerState[tokenId] = ToilerState({
  164 |             lastToilDate: block.timestamp,
  165 |             plotId: plotId,
  166 |             landlord: landlord,
  167 |             latestTaxRate: plotMetadata[landlord].currentTaxRate,
  168 |             dirty: false
  169 |         });
  170 | 
  171 |         emit FarmPlotTaken(toilerState[tokenId], tokenId);
  172 |     }
  173 | 
  174 |     function unstakeMunchable(
  175 |         uint256 tokenId
  176 |     ) external override forceFarmPlots(msg.sender) notPaused {
  177 |         (address mainAccount, ) = _getMainAccountRequireRegistered(msg.sender);
  178 |         ToilerState memory _toiler = toilerState[tokenId];
  179 |         if (_toiler.landlord == address(0)) revert NotStakedError();
  180 |         if (munchableOwner[tokenId] != mainAccount) revert InvalidOwnerError();
  181 | 
  182 |         plotOccupied[_toiler.landlord][_toiler.plotId] = Plot({
  183 |             occupied: false,
  184 |             tokenId: 0
  185 |         });
  186 |         toilerState[tokenId] = ToilerState({
  187 |             lastToilDate: 0,
  188 |             plotId: 0,
  189 |             landlord: address(0),
  190 |             latestTaxRate: 0,
  191 |             dirty: false
  192 |         });
  193 |         munchableOwner[tokenId] = address(0);
  194 |         _removeTokenIdFromStakedList(mainAccount, tokenId);
  195 | 
  196 |         munchNFT.transferFrom(address(this), mainAccount, tokenId);
  197 |         emit FarmPlotLeave(_toiler.landlord, tokenId, _toiler.plotId);
  198 |     }
  199 | 
  200 |     function transferToUnoccupiedPlot(
  201 |         uint256 tokenId,
  202 |         uint256 plotId
  203 |     ) external override forceFarmPlots(msg.sender) notPaused {
  204 |         (address mainAccount, ) = _getMainAccountRequireRegistered(msg.sender);
  205 |         ToilerState memory _toiler = toilerState[tokenId];
  206 |         uint256 oldPlotId = _toiler.plotId;
  207 |         uint256 totalPlotsAvail = _getNumPlots(_toiler.landlord);
  208 |         if (_toiler.landlord == address(0)) revert NotStakedError();
  209 |         if (munchableOwner[tokenId] != mainAccount) revert InvalidOwnerError();
  210 |         if (plotOccupied[_toiler.landlord][plotId].occupied)
  211 |             revert OccupiedPlotError(_toiler.landlord, plotId);
  212 |         if (plotId >= totalPlotsAvail) revert PlotTooHighError();
  213 | 
  214 |         toilerState[tokenId].latestTaxRate = plotMetadata[_toiler.landlord]
  215 |             .currentTaxRate;
  216 |         plotOccupied[_toiler.landlord][oldPlotId] = Plot({
  217 |             occupied: false,
  218 |             tokenId: 0
  219 |         });
  220 |         plotOccupied[_toiler.landlord][plotId] = Plot({
  221 |             occupied: true,
  222 |             tokenId: tokenId
  223 |         });
  224 | 
  225 |         emit FarmPlotLeave(_toiler.landlord, tokenId, oldPlotId);
  226 |         emit FarmPlotTaken(toilerState[tokenId], tokenId);
  227 |     }
  228 | 
  229 |     function farmPlots() external override notPaused {
  230 |         _farmPlots(msg.sender);
  231 |     }
  232 | 
  233 |     function _farmPlots(address _sender) internal {
  234 |         (
  235 |             address mainAccount,
  236 |             MunchablesCommonLib.Player memory renterMetadata
  237 |         ) = _getMainAccountRequireRegistered(_sender);
  238 | 
  239 |         uint256[] memory staked = munchablesStaked[mainAccount];
  240 |         MunchablesCommonLib.NFTImmutableAttributes memory immutableAttributes;
  241 |         ToilerState memory _toiler;
  242 |         uint256 timestamp;
  243 |         address landlord;
  244 |         uint256 tokenId;
  245 |         int256 finalBonus;
  246 |         uint256 schnibblesTotal;
  247 |         uint256 schnibblesLandlord;
  248 |         for (uint8 i = 0; i < staked.length; i++) {
  249 |             timestamp = block.timestamp;
  250 |             tokenId = staked[i];
  251 |             _toiler = toilerState[tokenId];
  252 |             if (_toiler.dirty) continue;
  253 |             landlord = _toiler.landlord;
  254 |             // use last updated plot metadata time if the plot id doesn't fit
  255 |             // track a dirty bool to signify this was done once
  256 |             // the edge case where this doesnt work is if the user hasnt farmed in a while and the landlord
  257 |             // updates their plots multiple times. then the last updated time will be the last time they updated their plot details
  258 |             // instead of the first
  259 |             if (_getNumPlots(landlord) < _toiler.plotId) {
  260 |                 timestamp = plotMetadata[landlord].lastUpdated;
  261 |                 toilerState[tokenId].dirty = true;
  262 |             }
  263 |             (
  264 |                 ,
  265 |                 MunchablesCommonLib.Player memory landlordMetadata
  266 |             ) = _getMainAccountRequireRegistered(landlord);
  267 | 
  268 |             immutableAttributes = nftAttributesManager.getImmutableAttributes(
  269 |                 tokenId
  270 |             );
  271 |             finalBonus =
  272 |                 int16(
  273 |                     REALM_BONUSES[
  274 |                         (uint256(immutableAttributes.realm) * 5) +
  275 |                             uint256(landlordMetadata.snuggeryRealm)
  276 |                     ]
  277 |                 ) +
  278 |                 int16(
  279 |                     int8(RARITY_BONUSES[uint256(immutableAttributes.rarity)])
  280 |                 );
  281 |             schnibblesTotal =
  282 |                 (timestamp - _toiler.lastToilDate) *
  283 |                 BASE_SCHNIBBLE_RATE;
  284 |             schnibblesTotal = uint256(
  285 |                 (int256(schnibblesTotal) +
  286 |                     (int256(schnibblesTotal) * finalBonus)) / 100
  287 |             );
  288 |             schnibblesLandlord =
  289 |                 (schnibblesTotal * _toiler.latestTaxRate) /
  290 |                 1e18;
  291 | 
  292 |             toilerState[tokenId].lastToilDate = timestamp;
  293 |             toilerState[tokenId].latestTaxRate = plotMetadata[_toiler.landlord]
  294 |                 .currentTaxRate;
  295 | 
  296 |             renterMetadata.unfedSchnibbles += (schnibblesTotal -
  297 |                 schnibblesLandlord);
  298 | 
  299 |             landlordMetadata.unfedSchnibbles += schnibblesLandlord;
  300 |             landlordMetadata.lastPetMunchable = uint32(timestamp);
  301 |             accountManager.updatePlayer(landlord, landlordMetadata);
  302 |             emit FarmedSchnibbles(
  303 |                 _toiler.landlord,
  304 |                 tokenId,
  305 |                 _toiler.plotId,
  306 |                 schnibblesTotal - schnibblesLandlord,
  307 |                 schnibblesLandlord
  308 |             );
  309 |         }
  310 |         accountManager.updatePlayer(mainAccount, renterMetadata);
  311 |     }
  312 | 
  313 |     function _removeTokenIdFromStakedList(
  314 |         address mainAccount,
  315 |         uint256 tokenId
  316 |     ) internal {
  317 |         uint256 stakedLength = munchablesStaked[mainAccount].length;
  318 |         bool found = false;
  319 |         for (uint256 i = 0; i < stakedLength; i++) {
  320 |             if (munchablesStaked[mainAccount][i] == tokenId) {
  321 |                 munchablesStaked[mainAccount][i] = munchablesStaked[
  322 |                     mainAccount
  323 |                 ][stakedLength - 1];
  324 |                 found = true;
  325 |                 munchablesStaked[mainAccount].pop();
  326 |                 break;
  327 |             }
  328 |         }
  329 | 
  330 |         if (!found) revert InvalidTokenIdError();
  331 |     }
  332 | 
  333 |     function _getMainAccountRequireRegistered(
  334 |         address _account
  335 |     ) internal view returns (address, MunchablesCommonLib.Player memory) {
  336 |         (
  337 |             address _mainAccount,
  338 |             MunchablesCommonLib.Player memory _player
  339 |         ) = accountManager.getPlayer(_account);
  340 | 
  341 |         if (_player.registrationDate == 0) revert PlayerNotRegisteredError();
  342 |         return (_mainAccount, _player);
  343 |     }
  344 | 
  345 |     function _getNumPlots(address _account) internal view returns (uint256) {
  346 |         return lockManager.getLockedWeightedValue(_account) / PRICE_PER_PLOT;
  347 |     }
  348 | }