     1	//SPDX-License-Identifier: Unlicense
     2	pragma solidity ^0.8.0;
     3	
     4	import "@openzeppelin/contracts/access/Ownable.sol";
     5	import "./interfaces/IPairsContract.sol";
     6	import "./utils/TradingLibrary.sol";
     7	import "./interfaces/IReferrals.sol";
     8	import "./interfaces/IPosition.sol";
     9	
    10	contract TradingExtension is Ownable{
    11	    uint constant private DIVISION_CONSTANT = 1e10; // 100%
    12	
    13	    address public trading;
    14	    uint256 public validSignatureTimer;
    15	    bool public chainlinkEnabled;
    16	
    17	    mapping(address => bool) private isNode;
    18	    mapping(address => uint) public minPositionSize;
    19	    mapping(address => bool) public allowedMargin;
    20	    bool public paused;
    21	
    22	    IPairsContract private pairsContract;
    23	    IReferrals private referrals;
    24	    IPosition private position;
    25	
    26	    uint public maxGasPrice = 1000000000000; // 1000 gwei
    27	
    28	    constructor(
    29	        address _trading,
    30	        address _pairsContract,
    31	        address _ref,
    32	        address _position
    33	    )
    34	    {
    35	        trading = _trading;
    36	        pairsContract = IPairsContract(_pairsContract);
    37	        referrals = IReferrals(_ref);
    38	        position = IPosition(_position);
    39	    }
    40	
    41	    /**
    42	    * @notice returns the minimum position size per collateral asset
    43	    * @param _asset address of the asset
    44	    */
    45	    function minPos(
    46	        address _asset
    47	    ) external view returns(uint) {
    48	        return minPositionSize[_asset];
    49	    }
    50	
    51	    /**
    52	    * @notice closePosition helper
    53	    * @dev only callable by trading contract
    54	    * @param _id id of the position NFT
    55	    * @param _price current asset price
    56	    * @param _percent close percentage
    57	    * @return _trade returns the trade struct from NFT contract
    58	    * @return _positionSize size of the position
    59	    * @return _payout amount of payout to the trader after closing
    60	    */
    61	    function _closePosition(
    62	        uint _id,
    63	        uint _price,
    64	        uint _percent
    65	    ) external onlyProtocol returns (IPosition.Trade memory _trade, uint256 _positionSize, int256 _payout) {
    66	        _trade = position.trades(_id);
    67	        (_positionSize, _payout) = TradingLibrary.pnl(_trade.direction, _price, _trade.price, _trade.margin, _trade.leverage, _trade.accInterest);
    68	
    69	        unchecked {
    70	            if (_trade.direction) {
    71	                modifyLongOi(_trade.asset, _trade.tigAsset, false, (_trade.margin*_trade.leverage/1e18)*_percent/DIVISION_CONSTANT);
    72	            } else {
    73	                modifyShortOi(_trade.asset, _trade.tigAsset, false, (_trade.margin*_trade.leverage/1e18)*_percent/DIVISION_CONSTANT);     
    74	            }
    75	        }
    76	    }
    77	
    78	    /**
    79	    * @notice limitClose helper
    80	    * @dev only callable by trading contract
    81	    * @param _id id of the position NFT
    82	    * @param _tp true if long, else short
    83	    * @param _priceData price data object came from the price oracle
    84	    * @param _signature to verify the oracle
    85	    * @return _limitPrice price of sl or tp returned from positions contract
    86	    * @return _tigAsset address of the position collateral asset
    87	    */
    88	    function _limitClose(
    89	        uint _id,
    90	        bool _tp,
    91	        PriceData calldata _priceData,
    92	        bytes calldata _signature
    93	    ) external view returns(uint _limitPrice, address _tigAsset) {
    94	        _checkGas();
    95	        IPosition.Trade memory _trade = position.trades(_id);
    96	        _tigAsset = _trade.tigAsset;
    97	
    98	        getVerifiedPrice(_trade.asset, _priceData, _signature, 0);
    99	        uint256 _price = _priceData.price;
   100	
   101	        if (_trade.orderType != 0) revert("4"); //IsLimit
   102	
   103	        if (_tp) {
   104	            if (_trade.tpPrice == 0) revert("7"); //LimitNotSet
   105	            if (_trade.direction) {
   106	                if (_trade.tpPrice > _price) revert("6"); //LimitNotMet
   107	            } else {
   108	                if (_trade.tpPrice < _price) revert("6"); //LimitNotMet
   109	            }
   110	            _limitPrice = _trade.tpPrice;
   111	        } else {
   112	            if (_trade.slPrice == 0) revert("7"); //LimitNotSet
   113	            if (_trade.direction) {
   114	                if (_trade.slPrice < _price) revert("6"); //LimitNotMet
   115	            } else {
   116	                if (_trade.slPrice > _price) revert("6"); //LimitNotMet
   117	            }
   118	            _limitPrice = _trade.slPrice;
   119	        }
   120	    }
   121	
   122	    function _checkGas() public view {
   123	        if (tx.gasprice > maxGasPrice) revert("1"); //GasTooHigh
   124	    }
   125	
   126	    function modifyShortOi(
   127	        uint _asset,
   128	        address _tigAsset,
   129	        bool _onOpen,
   130	        uint _size
   131	    ) public onlyProtocol {
   132	        pairsContract.modifyShortOi(_asset, _tigAsset, _onOpen, _size);
   133	    }
   134	
   135	    function modifyLongOi(
   136	        uint _asset,
   137	        address _tigAsset,
   138	        bool _onOpen,
   139	        uint _size
   140	    ) public onlyProtocol {
   141	        pairsContract.modifyLongOi(_asset, _tigAsset, _onOpen, _size);
   142	    }
   143	
   144	    function setMaxGasPrice(uint _maxGasPrice) external onlyOwner {
   145	        maxGasPrice = _maxGasPrice;
   146	    }
   147	
   148	    function getRef(
   149	        address _trader
   150	    ) external view returns(address) {
   151	        return referrals.getReferral(referrals.getReferred(_trader));
   152	    }
   153	
   154	    /**
   155	    * @notice verifies the signed price and returns it
   156	    * @param _asset id of position asset
   157	    * @param _priceData price data object came from the price oracle
   158	    * @param _signature to verify the oracle
   159	    * @param _withSpreadIsLong 0, 1, or 2 - to specify if we need the price returned to be after spread
   160	    * @return _price price after verification and with spread if _withSpreadIsLong is 1 or 2
   161	    * @return _spread spread after verification
   162	    */
   163	    function getVerifiedPrice(
   164	        uint _asset,
   165	        PriceData calldata _priceData,
   166	        bytes calldata _signature,
   167	        uint _withSpreadIsLong
   168	    ) 
   169	        public view
   170	        returns(uint256 _price, uint256 _spread) 
   171	    {
   172	        TradingLibrary.verifyPrice(
   173	            validSignatureTimer,
   174	            _asset,
   175	            chainlinkEnabled,
   176	            pairsContract.idToAsset(_asset).chainlinkFeed,
   177	            _priceData,
   178	            _signature,
   179	            isNode
   180	        );
   181	        _price = _priceData.price;
   182	        _spread = _priceData.spread;
   183	
   184	        if(_withSpreadIsLong == 1) 
   185	            _price += _price * _spread / DIVISION_CONSTANT;
   186	        else if(_withSpreadIsLong == 2) 
   187	            _price -= _price * _spread / DIVISION_CONSTANT;
   188	    }
   189	
   190	    function _setReferral(
   191	        bytes32 _referral,
   192	        address _trader
   193	    ) external onlyProtocol {
   194	        
   195	        if (_referral != bytes32(0)) {
   196	            if (referrals.getReferral(_referral) != address(0)) {
   197	                if (referrals.getReferred(_trader) == bytes32(0)) {
   198	                    referrals.setReferred(_trader, _referral);
   199	                }
   200	            }
   201	        }
   202	    }
   203	
   204	    /**
   205	     * @dev validates the inputs of trades
   206	     * @param _asset asset id
   207	     * @param _tigAsset margin asset
   208	     * @param _margin margin
   209	     * @param _leverage leverage
   210	     */
   211	    function validateTrade(uint _asset, address _tigAsset, uint _margin, uint _leverage) external view {
   212	        unchecked {
   213	            IPairsContract.Asset memory asset = pairsContract.idToAsset(_asset);
   214	            if (!allowedMargin[_tigAsset]) revert("!margin");
   215	            if (paused) revert("paused");
   216	            if (!pairsContract.allowedAsset(_asset)) revert("!allowed");
   217	            if (_leverage < asset.minLeverage || _leverage > asset.maxLeverage) revert("!lev");
   218	            if (_margin*_leverage/1e18 < minPositionSize[_tigAsset]) revert("!size");
   219	        }
   220	    }
   221	
   222	    function setValidSignatureTimer(
   223	        uint _validSignatureTimer
   224	    )
   225	        external
   226	        onlyOwner
   227	    {
   228	        validSignatureTimer = _validSignatureTimer;
   229	    }
   230	
   231	    function setChainlinkEnabled(bool _bool) external onlyOwner {
   232	        chainlinkEnabled = _bool;
   233	    }
   234	
   235	    /**
   236	     * @dev whitelists a node
   237	     * @param _node node address
   238	     * @param _bool bool
   239	     */
   240	    function setNode(address _node, bool _bool) external onlyOwner {
   241	        isNode[_node] = _bool;
   242	    }
   243	
   244	    /**
   245	     * @dev Allows a tigAsset to be used
   246	     * @param _tigAsset tigAsset
   247	     * @param _bool bool
   248	     */
   249	    function setAllowedMargin(
   250	        address _tigAsset,
   251	        bool _bool
   252	    ) 
   253	        external
   254	        onlyOwner
   255	    {
   256	        allowedMargin[_tigAsset] = _bool;
   257	    }
   258	
   259	    /**
   260	     * @dev changes the minimum position size
   261	     * @param _tigAsset tigAsset
   262	     * @param _min minimum position size 18 decimals
   263	     */
   264	    function setMinPositionSize(
   265	        address _tigAsset,
   266	        uint _min
   267	    ) 
   268	        external
   269	        onlyOwner
   270	    {
   271	        minPositionSize[_tigAsset] = _min;
   272	    }
   273	
   274	    function setPaused(bool _paused) external onlyOwner {
   275	        paused = _paused;
   276	    }
   277	
   278	    modifier onlyProtocol { 
   279	        require(msg.sender == trading, "!protocol");
   280	        _;
   281	    }
   282	}