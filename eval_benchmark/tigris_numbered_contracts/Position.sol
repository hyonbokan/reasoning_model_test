     1	// SPDX-License-Identifier: MIT
     2	pragma solidity ^0.8.0;
     3	
     4	import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
     5	import "@openzeppelin/contracts/utils/Counters.sol";
     6	import "./utils/MetaContext.sol";
     7	import "./interfaces/IPosition.sol";
     8	
     9	contract Position is ERC721Enumerable, MetaContext, IPosition {
    10	
    11	    function ownerOf(uint _id) public view override(ERC721, IERC721, IPosition) returns (address) {
    12	        return ERC721.ownerOf(_id);
    13	    }
    14	
    15	    using Counters for Counters.Counter;
    16	    uint constant public DIVISION_CONSTANT = 1e10; // 100%
    17	
    18	    mapping(uint => mapping(address => uint)) public vaultFundingPercent;
    19	
    20	    mapping(address => bool) private _isMinter; // Trading contract should be minter
    21	    mapping(uint256 => Trade) private _trades; // NFT id to Trade
    22	
    23	    uint256[] private _openPositions;
    24	    mapping(uint256 => uint256) private _openPositionsIndexes;
    25	
    26	    mapping(uint256 => uint256[]) private _assetOpenPositions;
    27	    mapping(uint256 => mapping(uint256 => uint256)) private _assetOpenPositionsIndexes;
    28	
    29	    mapping(uint256 => uint256[]) private _limitOrders; // List of limit order nft ids per asset
    30	    mapping(uint256 => mapping(uint256 => uint256)) private _limitOrderIndexes; // Keeps track of asset -> id -> array index
    31	
    32	    // Funding
    33	    mapping(uint256 => mapping(address => int256)) public fundingDeltaPerSec;
    34	    mapping(uint256 => mapping(address => mapping(bool => int256))) private accInterestPerOi;
    35	    mapping(uint256 => mapping(address => uint256)) private lastUpdate;
    36	    mapping(uint256 => int256) private initId;
    37	    mapping(uint256 => mapping(address => uint256)) private longOi;
    38	    mapping(uint256 => mapping(address => uint256)) private shortOi;
    39	
    40	    function isMinter(address _address) public view returns (bool) { return _isMinter[_address]; }
    41	    function trades(uint _id) public view returns (Trade memory) {
    42	        Trade memory _trade = _trades[_id];
    43	        _trade.trader = ownerOf(_id);
    44	        if (_trade.orderType > 0) return _trade;
    45	        
    46	        int256 _pendingFunding;
    47	        if (_trade.direction && longOi[_trade.asset][_trade.tigAsset] > 0) {
    48	            _pendingFunding = (int256(block.timestamp-lastUpdate[_trade.asset][_trade.tigAsset])*fundingDeltaPerSec[_trade.asset][_trade.tigAsset])*1e18/int256(longOi[_trade.asset][_trade.tigAsset]);
    49	            if (longOi[_trade.asset][_trade.tigAsset] > shortOi[_trade.asset][_trade.tigAsset]) {
    50	                _pendingFunding = -_pendingFunding;
    51	            } else {
    52	                _pendingFunding = _pendingFunding*int256(1e10-vaultFundingPercent[_trade.asset][_trade.tigAsset])/1e10;
    53	            }
    54	        } else if (shortOi[_trade.asset][_trade.tigAsset] > 0) {
    55	            _pendingFunding = (int256(block.timestamp-lastUpdate[_trade.asset][_trade.tigAsset])*fundingDeltaPerSec[_trade.asset][_trade.tigAsset])*1e18/int256(shortOi[_trade.asset][_trade.tigAsset]);
    56	            if (shortOi[_trade.asset][_trade.tigAsset] > longOi[_trade.asset][_trade.tigAsset]) {
    57	                _pendingFunding = -_pendingFunding;
    58	            } else {
    59	                _pendingFunding = _pendingFunding*int256(1e10-vaultFundingPercent[_trade.asset][_trade.tigAsset])/1e10;
    60	            }
    61	        }
    62	        _trade.accInterest += (int256(_trade.margin*_trade.leverage/1e18)*(accInterestPerOi[_trade.asset][_trade.tigAsset][_trade.direction]+_pendingFunding)/1e18)-initId[_id];
    63	        
    64	        return _trade;
    65	    }
    66	    function openPositions() public view returns (uint256[] memory) { return _openPositions; }
    67	    function openPositionsIndexes(uint _id) public view returns (uint256) { return _openPositionsIndexes[_id]; }
    68	    function assetOpenPositions(uint _asset) public view returns (uint256[] memory) { return _assetOpenPositions[_asset]; }
    69	    function assetOpenPositionsIndexes(uint _asset, uint _id) public view returns (uint256) { return _assetOpenPositionsIndexes[_asset][_id]; }
    70	    function limitOrders(uint _asset) public view returns (uint256[] memory) { return _limitOrders[_asset]; }
    71	    function limitOrderIndexes(uint _asset, uint _id) public view returns (uint256) { return _limitOrderIndexes[_asset][_id]; }
    72	
    73	    Counters.Counter private _tokenIds;
    74	    string public baseURI;
    75	
    76	    constructor(string memory _setBaseURI, string memory _name, string memory _symbol) ERC721(_name, _symbol) {
    77	        baseURI = _setBaseURI;
    78	        _tokenIds.increment();
    79	    }
    80	
    81	    function _baseURI() internal override view returns (string memory) {
    82	        return baseURI;
    83	    }
    84	
    85	    function setBaseURI(string memory _newBaseURI) external onlyOwner {
    86	        baseURI = _newBaseURI;
    87	    }
    88	
    89	    /**
    90	    * @notice Update funding rate after open interest change
    91	    * @dev only callable by minter
    92	    * @param _asset pair id
    93	    * @param _tigAsset tigAsset token address
    94	    * @param _longOi long open interest
    95	    * @param _shortOi short open interest
    96	    * @param _baseFundingRate base funding rate of a pair
    97	    * @param _vaultFundingPercent percent of earned funding going to the stablevault
    98	    */
    99	    function updateFunding(uint256 _asset, address _tigAsset, uint256 _longOi, uint256 _shortOi, uint256 _baseFundingRate, uint _vaultFundingPercent) external onlyMinter {
   100	        if(longOi[_asset][_tigAsset] < shortOi[_asset][_tigAsset]) {
   101	            if (longOi[_asset][_tigAsset] > 0) {
   102	                accInterestPerOi[_asset][_tigAsset][true] += ((int256(block.timestamp-lastUpdate[_asset][_tigAsset])*fundingDeltaPerSec[_asset][_tigAsset])*1e18/int256(longOi[_asset][_tigAsset]))*int256(1e10-vaultFundingPercent[_asset][_tigAsset])/1e10;
   103	            }
   104	            accInterestPerOi[_asset][_tigAsset][false] -= (int256(block.timestamp-lastUpdate[_asset][_tigAsset])*fundingDeltaPerSec[_asset][_tigAsset])*1e18/int256(shortOi[_asset][_tigAsset]);
   105	
   106	        } else if(longOi[_asset][_tigAsset] > shortOi[_asset][_tigAsset]) {
   107	            accInterestPerOi[_asset][_tigAsset][true] -= (int256(block.timestamp-lastUpdate[_asset][_tigAsset])*fundingDeltaPerSec[_asset][_tigAsset])*1e18/int256(longOi[_asset][_tigAsset]);
   108	            if (shortOi[_asset][_tigAsset] > 0) {
   109	                accInterestPerOi[_asset][_tigAsset][false] += ((int256(block.timestamp-lastUpdate[_asset][_tigAsset])*fundingDeltaPerSec[_asset][_tigAsset])*1e18/int256(shortOi[_asset][_tigAsset]))*int256(1e10-vaultFundingPercent[_asset][_tigAsset])/1e10;
   110	            }
   111	        }
   112	        lastUpdate[_asset][_tigAsset] = block.timestamp;
   113	        int256 _oiDelta;
   114	        if (_longOi > _shortOi) {
   115	            _oiDelta = int256(_longOi)-int256(_shortOi);
   116	        } else {
   117	            _oiDelta = int256(_shortOi)-int256(_longOi);
   118	        }
   119	        
   120	        fundingDeltaPerSec[_asset][_tigAsset] = (_oiDelta*int256(_baseFundingRate)/int256(DIVISION_CONSTANT))/31536000;
   121	        longOi[_asset][_tigAsset] = _longOi;
   122	        shortOi[_asset][_tigAsset] = _shortOi;
   123	        vaultFundingPercent[_asset][_tigAsset] = _vaultFundingPercent;
   124	    }
   125	
   126	    /**
   127	    * @notice mint a new position nft
   128	    * @dev only callable by minter
   129	    * @param _mintTrade New trade params in struct
   130	    */
   131	    function mint(
   132	        MintTrade memory _mintTrade
   133	    ) external onlyMinter {
   134	        uint newTokenID = _tokenIds.current();
   135	
   136	        Trade storage newTrade = _trades[newTokenID];
   137	        newTrade.margin = _mintTrade.margin;
   138	        newTrade.leverage = _mintTrade.leverage;
   139	        newTrade.asset = _mintTrade.asset;
   140	        newTrade.direction = _mintTrade.direction;
   141	        newTrade.price = _mintTrade.price;
   142	        newTrade.tpPrice = _mintTrade.tp;
   143	        newTrade.slPrice = _mintTrade.sl;
   144	        newTrade.orderType = _mintTrade.orderType;
   145	        newTrade.id = newTokenID;
   146	        newTrade.tigAsset = _mintTrade.tigAsset;
   147	
   148	        _safeMint(_mintTrade.account, newTokenID);
   149	        if (_mintTrade.orderType > 0) {
   150	            _limitOrders[_mintTrade.asset].push(newTokenID);
   151	            _limitOrderIndexes[_mintTrade.asset][newTokenID] = _limitOrders[_mintTrade.asset].length-1;
   152	        } else {
   153	            initId[newTokenID] = accInterestPerOi[_mintTrade.asset][_mintTrade.tigAsset][_mintTrade.direction]*int256(_mintTrade.margin*_mintTrade.leverage/1e18)/1e18;
   154	            _openPositions.push(newTokenID);
   155	            _openPositionsIndexes[newTokenID] = _openPositions.length-1;
   156	
   157	            _assetOpenPositions[_mintTrade.asset].push(newTokenID);
   158	            _assetOpenPositionsIndexes[_mintTrade.asset][newTokenID] = _assetOpenPositions[_mintTrade.asset].length-1;
   159	        }
   160	        _tokenIds.increment();
   161	    }
   162	
   163	    /**
   164	     * @param _id id of the position NFT
   165	     * @param _price price used for execution
   166	     * @param _newMargin margin after fees
   167	     */
   168	    function executeLimitOrder(uint256 _id, uint256 _price, uint256 _newMargin) external onlyMinter {
   169	        Trade storage _trade = _trades[_id];
   170	        if (_trade.orderType == 0) {
   171	            return;
   172	        }
   173	        _trade.orderType = 0;
   174	        _trade.price = _price;
   175	        _trade.margin = _newMargin;
   176	        uint _asset = _trade.asset;
   177	        _limitOrderIndexes[_asset][_limitOrders[_asset][_limitOrders[_asset].length-1]] = _limitOrderIndexes[_asset][_id];
   178	        _limitOrders[_asset][_limitOrderIndexes[_asset][_id]] = _limitOrders[_asset][_limitOrders[_asset].length-1];
   179	        delete _limitOrderIndexes[_asset][_id];
   180	        _limitOrders[_asset].pop();
   181	
   182	        _openPositions.push(_id);
   183	        _openPositionsIndexes[_id] = _openPositions.length-1;
   184	        _assetOpenPositions[_asset].push(_id);
   185	        _assetOpenPositionsIndexes[_asset][_id] = _assetOpenPositions[_asset].length-1;
   186	
   187	        initId[_id] = accInterestPerOi[_trade.asset][_trade.tigAsset][_trade.direction]*int256(_trade.margin*_trade.leverage/1e18)/1e18;
   188	    }
   189	
   190	    /**
   191	    * @notice modifies margin and leverage
   192	    * @dev only callable by minter
   193	    * @param _id position id
   194	    * @param _newMargin new margin amount
   195	    * @param _newLeverage new leverage amount
   196	    */
   197	    function modifyMargin(uint256 _id, uint256 _newMargin, uint256 _newLeverage) external onlyMinter {
   198	        _trades[_id].margin = _newMargin;
   199	        _trades[_id].leverage = _newLeverage;
   200	    }
   201	
   202	    /**
   203	    * @notice modifies margin and entry price
   204	    * @dev only callable by minter
   205	    * @param _id position id
   206	    * @param _newMargin new margin amount
   207	    * @param _newPrice new entry price
   208	    */
   209	    function addToPosition(uint256 _id, uint256 _newMargin, uint256 _newPrice) external onlyMinter {
   210	        _trades[_id].margin = _newMargin;
   211	        _trades[_id].price = _newPrice;
   212	        initId[_id] = accInterestPerOi[_trades[_id].asset][_trades[_id].tigAsset][_trades[_id].direction]*int256(_newMargin*_trades[_id].leverage/1e18)/1e18;
   213	    }
   214	
   215	    /**
   216	    * @notice Called before updateFunding for reducing position or adding to position, to store accumulated funding
   217	    * @dev only callable by minter
   218	    * @param _id position id
   219	    */
   220	    function setAccInterest(uint256 _id) external onlyMinter {
   221	        _trades[_id].accInterest = trades(_id).accInterest;
   222	    }
   223	
   224	    /**
   225	    * @notice Reduces position size by %
   226	    * @dev only callable by minter
   227	    * @param _id position id
   228	    * @param _percent percent of a position being closed
   229	    */
   230	    function reducePosition(uint256 _id, uint256 _percent) external onlyMinter {
   231	        _trades[_id].accInterest -= _trades[_id].accInterest*int256(_percent)/int256(DIVISION_CONSTANT);
   232	        _trades[_id].margin -= _trades[_id].margin*_percent/DIVISION_CONSTANT;
   233	        initId[_id] = accInterestPerOi[_trades[_id].asset][_trades[_id].tigAsset][_trades[_id].direction]*int256(_trades[_id].margin*_trades[_id].leverage/1e18)/1e18;
   234	    }
   235	
   236	    /**
   237	    * @notice change a position tp price
   238	    * @dev only callable by minter
   239	    * @param _id position id
   240	    * @param _tpPrice tp price
   241	    */
   242	    function modifyTp(uint _id, uint _tpPrice) external onlyMinter {
   243	        _trades[_id].tpPrice = _tpPrice;
   244	    }
   245	
   246	    /**
   247	    * @notice change a position sl price
   248	    * @dev only callable by minter
   249	    * @param _id position id
   250	    * @param _slPrice sl price
   251	    */
   252	    function modifySl(uint _id, uint _slPrice) external onlyMinter {
   253	        _trades[_id].slPrice = _slPrice;
   254	    }
   255	
   256	    /**
   257	    * @dev Burns an NFT and it's data
   258	    * @param _id ID of the trade
   259	    */
   260	    function burn(uint _id) external onlyMinter {
   261	        _burn(_id);
   262	        uint _asset = _trades[_id].asset;
   263	        if (_trades[_id].orderType > 0) {
   264	            _limitOrderIndexes[_asset][_limitOrders[_asset][_limitOrders[_asset].length-1]] = _limitOrderIndexes[_asset][_id];
   265	            _limitOrders[_asset][_limitOrderIndexes[_asset][_id]] = _limitOrders[_asset][_limitOrders[_asset].length-1];
   266	            delete _limitOrderIndexes[_asset][_id];
   267	            _limitOrders[_asset].pop();            
   268	        } else {
   269	            _assetOpenPositionsIndexes[_asset][_assetOpenPositions[_asset][_assetOpenPositions[_asset].length-1]] = _assetOpenPositionsIndexes[_asset][_id];
   270	            _assetOpenPositions[_asset][_assetOpenPositionsIndexes[_asset][_id]] = _assetOpenPositions[_asset][_assetOpenPositions[_asset].length-1];
   271	            delete _assetOpenPositionsIndexes[_asset][_id];
   272	            _assetOpenPositions[_asset].pop();  
   273	
   274	            _openPositionsIndexes[_openPositions[_openPositions.length-1]] = _openPositionsIndexes[_id];
   275	            _openPositions[_openPositionsIndexes[_id]] = _openPositions[_openPositions.length-1];
   276	            delete _openPositionsIndexes[_id];
   277	            _openPositions.pop();              
   278	        }
   279	        delete _trades[_id];
   280	    }
   281	
   282	    function assetOpenPositionsLength(uint _asset) external view returns (uint256) {
   283	        return _assetOpenPositions[_asset].length;
   284	    }
   285	
   286	    function limitOrdersLength(uint _asset) external view returns (uint256) {
   287	        return _limitOrders[_asset].length;
   288	    }
   289	
   290	    function getCount() external view returns (uint) {
   291	        return _tokenIds.current();
   292	    }
   293	
   294	    function userTrades(address _user) external view returns (uint[] memory) {
   295	        uint[] memory _ids = new uint[](balanceOf(_user));
   296	        for (uint i=0; i<_ids.length; i++) {
   297	            _ids[i] = tokenOfOwnerByIndex(_user, i);
   298	        }
   299	        return _ids;
   300	    }
   301	
   302	    function openPositionsSelection(uint _from, uint _to) external view returns (uint[] memory) {
   303	        uint[] memory _ids = new uint[](_to-_from);
   304	        for (uint i=0; i<_ids.length; i++) {
   305	            _ids[i] = _openPositions[i+_from];
   306	        }
   307	        return _ids;
   308	    }
   309	
   310	    function setMinter(address _minter, bool _bool) external onlyOwner {
   311	        _isMinter[_minter] = _bool;
   312	    }    
   313	
   314	    modifier onlyMinter() {
   315	        require(_isMinter[_msgSender()], "!Minter");
   316	        _;
   317	    }
   318	
   319	    // META-TX
   320	    function _msgSender() internal view override(Context, MetaContext) returns (address sender) {
   321	        return MetaContext._msgSender();
   322	    }
   323	    function _msgData() internal view override(Context, MetaContext) returns (bytes calldata) {
   324	        return MetaContext._msgData();
   325	    }
   326	}