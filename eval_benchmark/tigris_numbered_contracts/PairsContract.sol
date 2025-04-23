     1	//SPDX-License-Identifier: Unlicense
     2	pragma solidity ^0.8.0;
     3	
     4	import "@openzeppelin/contracts/access/Ownable.sol";
     5	import "./interfaces/IPairsContract.sol";
     6	import "./interfaces/IPosition.sol";
     7	
     8	contract PairsContract is Ownable, IPairsContract {
     9	
    10	    address public protocol;
    11	
    12	    mapping(uint256 => bool) public allowedAsset;
    13	
    14	    uint256 private maxBaseFundingRate = 1e10;
    15	
    16	    mapping(uint256 => Asset) private _idToAsset;
    17	    function idToAsset(uint256 _asset) public view returns (Asset memory) {
    18	        return _idToAsset[_asset];
    19	    }
    20	
    21	    mapping(uint256 => mapping(address => OpenInterest)) private _idToOi;
    22	    function idToOi(uint256 _asset, address _tigAsset) public view returns (OpenInterest memory) {
    23	        return _idToOi[_asset][_tigAsset];
    24	    }
    25	
    26	    // OWNER
    27	
    28	    /**
    29	     * @dev Update the Chainlink price feed of an asset
    30	     * @param _asset index of the requested asset
    31	     * @param _feed contract address of the Chainlink price feed
    32	     */
    33	    function setAssetChainlinkFeed(uint256 _asset, address _feed) external onlyOwner {
    34	        bytes memory _name  = bytes(_idToAsset[_asset].name);
    35	        require(_name.length > 0, "!Asset");
    36	        _idToAsset[_asset].chainlinkFeed = _feed;
    37	    }
    38	
    39	    /**
    40	     * @dev Add an allowed asset to fetch prices for
    41	     * @param _asset index of the requested asset
    42	     * @param _name name of the asset
    43	     * @param _chainlinkFeed optional address of the respective Chainlink price feed
    44	     * @param _maxLeverage maximimum allowed leverage
    45	     * @param _maxLeverage minimum allowed leverage
    46	     * @param _feeMultiplier percent value that the opening/closing fee is multiplied by in BP
    47	     */
    48	    function addAsset(uint256 _asset, string memory _name, address _chainlinkFeed, uint256 _minLeverage, uint256 _maxLeverage, uint256 _feeMultiplier, uint256 _baseFundingRate) external onlyOwner {
    49	        bytes memory _assetName  = bytes(_idToAsset[_asset].name);
    50	        require(_assetName.length == 0, "Already exists");
    51	        require(bytes(_name).length > 0, "No name");
    52	        require(_maxLeverage >= _minLeverage && _minLeverage > 0, "Wrong leverage values");
    53	
    54	        allowedAsset[_asset] = true;
    55	        _idToAsset[_asset].name = _name;
    56	
    57	        _idToAsset[_asset].chainlinkFeed = _chainlinkFeed;
    58	
    59	        _idToAsset[_asset].minLeverage = _minLeverage;
    60	        _idToAsset[_asset].maxLeverage = _maxLeverage;
    61	        _idToAsset[_asset].feeMultiplier = _feeMultiplier;
    62	        _idToAsset[_asset].baseFundingRate = _baseFundingRate;
    63	
    64	        emit AssetAdded(_asset, _name);
    65	    }
    66	
    67	    /**
    68	     * @dev Update the leverage allowed per asset
    69	     * @param _asset index of the asset
    70	     * @param _minLeverage minimum leverage allowed
    71	     * @param _maxLeverage Maximum leverage allowed
    72	     */
    73	    function updateAssetLeverage(uint256 _asset, uint256 _minLeverage, uint256 _maxLeverage) external onlyOwner {
    74	        bytes memory _name  = bytes(_idToAsset[_asset].name);
    75	        require(_name.length > 0, "!Asset");
    76	
    77	        if (_maxLeverage > 0) {
    78	            _idToAsset[_asset].maxLeverage = _maxLeverage;
    79	        }
    80	        if (_minLeverage > 0) {
    81	            _idToAsset[_asset].minLeverage = _minLeverage;
    82	        }
    83	        
    84	        require(_idToAsset[_asset].maxLeverage >= _idToAsset[_asset].minLeverage, "Wrong leverage values");
    85	    }
    86	
    87	    /**
    88	     * @notice update the base rate for funding fees per asset
    89	     * @param _asset index of the asset
    90	     * @param _baseFundingRate the rate to set
    91	     */
    92	    function setAssetBaseFundingRate(uint256 _asset, uint256 _baseFundingRate) external onlyOwner {
    93	        bytes memory _name  = bytes(_idToAsset[_asset].name);
    94	        require(_name.length > 0, "!Asset");
    95	        require(_baseFundingRate <= maxBaseFundingRate, "baseFundingRate too high");
    96	        _idToAsset[_asset].baseFundingRate = _baseFundingRate;
    97	    }
    98	
    99	    /**
   100	     * @notice update the fee multiplier per asset
   101	     * @param _asset index of the asset
   102	     * @param _feeMultiplier the fee multiplier
   103	     */
   104	    function updateAssetFeeMultiplier(uint256 _asset, uint256 _feeMultiplier) external onlyOwner {
   105	        bytes memory _name  = bytes(_idToAsset[_asset].name);
   106	        require(_name.length > 0, "!Asset");
   107	        _idToAsset[_asset].feeMultiplier = _feeMultiplier;
   108	    }
   109	
   110	     /**
   111	     * @notice pause an asset from being traded
   112	     * @param _asset index of the asset
   113	     * @param _isPaused paused if true
   114	     */
   115	    function pauseAsset(uint256 _asset, bool _isPaused) external onlyOwner {
   116	        bytes memory _name  = bytes(_idToAsset[_asset].name);
   117	        require(_name.length > 0, "!Asset");
   118	        allowedAsset[_asset] = !_isPaused;
   119	    }
   120	
   121	    /**
   122	     * @notice sets the max rate for funding fees
   123	     * @param _maxBaseFundingRate max base funding rate
   124	     */
   125	    function setMaxBaseFundingRate(uint256 _maxBaseFundingRate) external onlyOwner {
   126	        maxBaseFundingRate = _maxBaseFundingRate;
   127	    }
   128	
   129	    function setProtocol(address _protocol) external onlyOwner {
   130	        protocol = _protocol;
   131	    }
   132	
   133	    /**
   134	     * @dev Update max open interest limits
   135	     * @param _asset index of the asset
   136	     * @param _tigAsset contract address of the tigAsset
   137	     * @param _maxOi Maximum open interest value per side
   138	     */
   139	    function setMaxOi(uint256 _asset, address _tigAsset, uint256 _maxOi) external onlyOwner {
   140	        bytes memory _name  = bytes(_idToAsset[_asset].name);
   141	        require(_name.length > 0, "!Asset");
   142	        _idToOi[_asset][_tigAsset].maxOi = _maxOi;
   143	    }
   144	
   145	    // Protocol-only
   146	
   147	    /**
   148	     * @dev edits the current open interest for long
   149	     * @param _asset index of the asset
   150	     * @param _tigAsset contract address of the tigAsset
   151	     * @param _onOpen true if adding to open interesr
   152	     * @param _amount amount to be added/removed from open interest
   153	     */
   154	    function modifyLongOi(uint256 _asset, address _tigAsset, bool _onOpen, uint256 _amount) external onlyProtocol {
   155	        if (_onOpen) {
   156	            _idToOi[_asset][_tigAsset].longOi += _amount;
   157	            require(_idToOi[_asset][_tigAsset].longOi <= _idToOi[_asset][_tigAsset].maxOi || _idToOi[_asset][_tigAsset].maxOi == 0, "MaxLongOi");
   158	        }
   159	        else {
   160	            _idToOi[_asset][_tigAsset].longOi -= _amount;
   161	            if (_idToOi[_asset][_tigAsset].longOi < 1e9) {
   162	                _idToOi[_asset][_tigAsset].longOi = 0;
   163	            }
   164	        }
   165	    }
   166	
   167	     /**
   168	     * @dev edits the current open interest for short
   169	     * @param _asset index of the asset
   170	     * @param _tigAsset contract address of the tigAsset
   171	     * @param _onOpen true if adding to open interesr
   172	     * @param _amount amount to be added/removed from open interest
   173	     */
   174	    function modifyShortOi(uint256 _asset, address _tigAsset, bool _onOpen, uint256 _amount) external onlyProtocol {
   175	        if (_onOpen) {
   176	            _idToOi[_asset][_tigAsset].shortOi += _amount;
   177	            require(_idToOi[_asset][_tigAsset].shortOi <= _idToOi[_asset][_tigAsset].maxOi || _idToOi[_asset][_tigAsset].maxOi == 0, "MaxShortOi");
   178	            }
   179	        else {
   180	            _idToOi[_asset][_tigAsset].shortOi -= _amount;
   181	            if (_idToOi[_asset][_tigAsset].shortOi < 1e9) {
   182	                _idToOi[_asset][_tigAsset].shortOi = 0;
   183	            }
   184	        }
   185	    }
   186	
   187	    // Modifiers
   188	
   189	    modifier onlyProtocol() {
   190	        require(_msgSender() == address(protocol), "!Protocol");
   191	        _;
   192	    }
   193	
   194	    // EVENTS
   195	
   196	    event AssetAdded(
   197	        uint _asset,
   198	        string _name
   199	    );
   200	
   201	}