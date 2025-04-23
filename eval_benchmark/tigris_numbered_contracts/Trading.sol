     1	//SPDX-License-Identifier: Unlicense
     2	pragma solidity ^0.8.0;
     3	
     4	import "./utils/MetaContext.sol";
     5	import "./interfaces/ITrading.sol";
     6	import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
     7	import "./interfaces/IPairsContract.sol";
     8	import "./interfaces/IReferrals.sol";
     9	import "./interfaces/IPosition.sol";
    10	import "./interfaces/IGovNFT.sol";
    11	import "./interfaces/IStableVault.sol";
    12	import "./utils/TradingLibrary.sol";
    13	
    14	interface ITradingExtension {
    15	    function getVerifiedPrice(
    16	        uint _asset,
    17	        PriceData calldata _priceData,
    18	        bytes calldata _signature,
    19	        uint _withSpreadIsLong
    20	    ) external returns(uint256 _price, uint256 _spread);
    21	    function getRef(
    22	        address _trader
    23	    ) external pure returns(address);
    24	    function _setReferral(
    25	        bytes32 _referral,
    26	        address _trader
    27	    ) external;
    28	    function validateTrade(uint _asset, address _tigAsset, uint _margin, uint _leverage) external view;
    29	    function isPaused() external view returns(bool);
    30	    function minPos(address) external view returns(uint);
    31	    function modifyLongOi(
    32	        uint _asset,
    33	        address _tigAsset,
    34	        bool _onOpen,
    35	        uint _size
    36	    ) external;
    37	    function modifyShortOi(
    38	        uint _asset,
    39	        address _tigAsset,
    40	        bool _onOpen,
    41	        uint _size
    42	    ) external;
    43	    function paused() external returns(bool);
    44	    function _limitClose(
    45	        uint _id,
    46	        bool _tp,
    47	        PriceData calldata _priceData,
    48	        bytes calldata _signature
    49	    ) external returns(uint _limitPrice, address _tigAsset);
    50	    function _checkGas() external view;
    51	    function _closePosition(
    52	        uint _id,
    53	        uint _price,
    54	        uint _percent
    55	    ) external returns (IPosition.Trade memory _trade, uint256 _positionSize, int256 _payout);
    56	}
    57	
    58	interface IStable is IERC20 {
    59	    function burnFrom(address account, uint amount) external;
    60	    function mintFor(address account, uint amount) external;
    61	}
    62	
    63	interface ExtendedIERC20 is IERC20 {
    64	    function decimals() external view returns (uint);
    65	}
    66	
    67	interface ERC20Permit is IERC20 {
    68	    function permit(
    69	        address owner,
    70	        address spender,
    71	        uint256 value,
    72	        uint256 deadline,
    73	        uint8 v,
    74	        bytes32 r,
    75	        bytes32 s
    76	    ) external;
    77	}
    78	
    79	contract Trading is MetaContext, ITrading {
    80	
    81	    error LimitNotSet(); //7
    82	    error NotLiquidatable();
    83	    error TradingPaused();
    84	    error BadDeposit();
    85	    error BadWithdraw();
    86	    error ValueNotEqualToMargin();
    87	    error BadLeverage();
    88	    error NotMargin();
    89	    error NotAllowedPair();
    90	    error BelowMinPositionSize();
    91	    error BadClosePercent();
    92	    error NoPrice();
    93	    error LiqThreshold();
    94	
    95	    uint constant private DIVISION_CONSTANT = 1e10; // 100%
    96	    uint private constant liqPercent = 9e9; // 90%
    97	
    98	    struct Fees {
    99	        uint daoFees;
   100	        uint burnFees;
   101	        uint referralFees;
   102	        uint botFees;
   103	    }
   104	    Fees public openFees = Fees(
   105	        0,
   106	        0,
   107	        0,
   108	        0
   109	    );
   110	    Fees public closeFees = Fees(
   111	        0,
   112	        0,
   113	        0,
   114	        0
   115	    );
   116	    uint public limitOrderPriceRange = 1e8; // 1%
   117	
   118	    uint public maxWinPercent;
   119	    uint public vaultFundingPercent;
   120	
   121	    IPairsContract private pairsContract;
   122	    IPosition private position;
   123	    IGovNFT private gov;
   124	    ITradingExtension private tradingExtension;
   125	
   126	    struct Delay {
   127	        uint delay; // Block number where delay ends
   128	        bool actionType; // True for open, False for close
   129	    }
   130	    mapping(uint => Delay) public blockDelayPassed; // id => Delay
   131	    uint public blockDelay;
   132	    mapping(uint => uint) public limitDelay; // id => block.timestamp
   133	
   134	    mapping(address => bool) public allowedVault;
   135	
   136	    struct Proxy {
   137	        address proxy;
   138	        uint256 time;
   139	    }
   140	
   141	    mapping(address => Proxy) public proxyApprovals;
   142	
   143	    constructor(
   144	        address _position,
   145	        address _gov,
   146	        address _pairsContract
   147	    )
   148	    {
   149	        position = IPosition(_position);
   150	        gov = IGovNFT(_gov);
   151	        pairsContract = IPairsContract(_pairsContract);
   152	    }
   153	
   154	    // ===== END-USER FUNCTIONS =====
   155	
   156	    /**
   157	     * @param _tradeInfo Trade info
   158	     * @param _priceData verifiable off-chain price data
   159	     * @param _signature node signature
   160	     * @param _permitData data and signature needed for token approval
   161	     * @param _trader address the trade is initiated for
   162	     */
   163	    function initiateMarketOrder(
   164	        TradeInfo calldata _tradeInfo,
   165	        PriceData calldata _priceData,
   166	        bytes calldata _signature,
   167	        ERC20PermitData calldata _permitData,
   168	        address _trader
   169	    )
   170	        external
   171	    {
   172	        _validateProxy(_trader);
   173	        _checkDelay(position.getCount(), true);
   174	        _checkVault(_tradeInfo.stableVault, _tradeInfo.marginAsset);
   175	        address _tigAsset = IStableVault(_tradeInfo.stableVault).stable();
   176	        tradingExtension.validateTrade(_tradeInfo.asset, _tigAsset, _tradeInfo.margin, _tradeInfo.leverage);
   177	        tradingExtension._setReferral(_tradeInfo.referral, _trader);
   178	        uint256 _marginAfterFees = _tradeInfo.margin - _handleOpenFees(_tradeInfo.asset, _tradeInfo.margin*_tradeInfo.leverage/1e18, _trader, _tigAsset, false);
   179	        uint256 _positionSize = _marginAfterFees * _tradeInfo.leverage / 1e18;
   180	        _handleDeposit(_tigAsset, _tradeInfo.marginAsset, _tradeInfo.margin, _tradeInfo.stableVault, _permitData, _trader);
   181	        uint256 _isLong = _tradeInfo.direction ? 1 : 2;
   182	        (uint256 _price,) = tradingExtension.getVerifiedPrice(_tradeInfo.asset, _priceData, _signature, _isLong);
   183	        IPosition.MintTrade memory _mintTrade = IPosition.MintTrade(
   184	            _trader,
   185	            _marginAfterFees,
   186	            _tradeInfo.leverage,
   187	            _tradeInfo.asset,
   188	            _tradeInfo.direction,
   189	            _price,
   190	            _tradeInfo.tpPrice,
   191	            _tradeInfo.slPrice,
   192	            0,
   193	            _tigAsset
   194	        );
   195	        _checkSl(_tradeInfo.slPrice, _tradeInfo.direction, _price);
   196	        unchecked {
   197	            if (_tradeInfo.direction) {
   198	                tradingExtension.modifyLongOi(_tradeInfo.asset, _tigAsset, true, _positionSize);
   199	            } else {
   200	                tradingExtension.modifyShortOi(_tradeInfo.asset, _tigAsset, true, _positionSize);
   201	            }
   202	        }
   203	        _updateFunding(_tradeInfo.asset, _tigAsset);
   204	        position.mint(
   205	            _mintTrade
   206	        );
   207	        unchecked {
   208	            emit PositionOpened(_tradeInfo, 0, _price, position.getCount()-1, _trader, _marginAfterFees);
   209	        }   
   210	    }
   211	
   212	    /**
   213	     * @dev initiate closing position
   214	     * @param _id id of the position NFT
   215	     * @param _percent percent of the position being closed in BP
   216	     * @param _priceData verifiable off-chain price data
   217	     * @param _signature node signature
   218	     * @param _stableVault StableVault address
   219	     * @param _outputToken Token received upon closing trade
   220	     * @param _trader address the trade is initiated for
   221	     */
   222	    function initiateCloseOrder(
   223	        uint _id,
   224	        uint _percent,
   225	        PriceData calldata _priceData,
   226	        bytes calldata _signature,
   227	        address _stableVault,
   228	        address _outputToken,
   229	        address _trader
   230	    )
   231	        external
   232	    {
   233	        _validateProxy(_trader);
   234	        _checkDelay(_id, false);
   235	        _checkOwner(_id, _trader);
   236	        _checkVault(_stableVault, _outputToken);
   237	        IPosition.Trade memory _trade = position.trades(_id);
   238	        if (_trade.orderType != 0) revert("4"); //IsLimit        
   239	        (uint256 _price,) = tradingExtension.getVerifiedPrice(_trade.asset, _priceData, _signature, 0);
   240	
   241	        if (_percent > DIVISION_CONSTANT || _percent == 0) revert BadClosePercent();
   242	        _closePosition(_id, _percent, _price, _stableVault, _outputToken, false); 
   243	    }
   244	
   245	    /**
   246	     * @param _id position id
   247	     * @param _addMargin margin amount used to add to the position
   248	     * @param _priceData verifiable off-chain price data
   249	     * @param _signature node signature
   250	     * @param _stableVault StableVault address
   251	     * @param _marginAsset Token being used to add to the position
   252	     * @param _permitData data and signature needed for token approval
   253	     * @param _trader address the trade is initiated for
   254	     */
   255	    function addToPosition(
   256	        uint _id,
   257	        uint _addMargin,
   258	        PriceData calldata _priceData,
   259	        bytes calldata _signature,
   260	        address _stableVault,
   261	        address _marginAsset,
   262	        ERC20PermitData calldata _permitData,
   263	        address _trader
   264	    )
   265	        external
   266	    {
   267	        _validateProxy(_trader);
   268	        _checkOwner(_id, _trader);
   269	        _checkDelay(_id, true);
   270	        IPosition.Trade memory _trade = position.trades(_id);
   271	        tradingExtension.validateTrade(_trade.asset, _trade.tigAsset, _trade.margin + _addMargin, _trade.leverage);
   272	        _checkVault(_stableVault, _marginAsset);
   273	        if (_trade.orderType != 0) revert("4"); //IsLimit
   274	        uint _fee = _handleOpenFees(_trade.asset, _addMargin*_trade.leverage/1e18, _trader, _trade.tigAsset, false);
   275	        _handleDeposit(
   276	            _trade.tigAsset,
   277	            _marginAsset,
   278	            _addMargin - _fee,
   279	            _stableVault,
   280	            _permitData,
   281	            _trader
   282	        );
   283	        position.setAccInterest(_id);
   284	        unchecked {
   285	            (uint256 _price,) = tradingExtension.getVerifiedPrice(_trade.asset, _priceData, _signature, _trade.direction ? 1 : 2);
   286	            uint _positionSize = (_addMargin - _fee) * _trade.leverage / 1e18;
   287	            if (_trade.direction) {
   288	                tradingExtension.modifyLongOi(_trade.asset, _trade.tigAsset, true, _positionSize);
   289	            } else {
   290	                tradingExtension.modifyShortOi(_trade.asset, _trade.tigAsset, true, _positionSize);     
   291	            }
   292	            _updateFunding(_trade.asset, _trade.tigAsset);
   293	            _addMargin -= _fee;
   294	            uint _newMargin = _trade.margin + _addMargin;
   295	            uint _newPrice = _trade.price*_trade.margin/_newMargin + _price*_addMargin/_newMargin;
   296	
   297	            position.addToPosition(
   298	                _trade.id,
   299	                _newMargin,
   300	                _newPrice
   301	            );
   302	            
   303	            emit AddToPosition(_trade.id, _newMargin, _newPrice, _trade.trader);
   304	        }
   305	    }
   306	
   307	    /**
   308	     * @param _tradeInfo Trade info
   309	     * @param _orderType type of limit order used to open the position
   310	     * @param _price limit price
   311	     * @param _permitData data and signature needed for token approval
   312	     * @param _trader address the trade is initiated for
   313	     */
   314	    function initiateLimitOrder(
   315	        TradeInfo calldata _tradeInfo,
   316	        uint256 _orderType, // 1 limit, 2 stop
   317	        uint256 _price,
   318	        ERC20PermitData calldata _permitData,
   319	        address _trader
   320	    )
   321	        external
   322	    {
   323	        _validateProxy(_trader);
   324	        address _tigAsset = IStableVault(_tradeInfo.stableVault).stable();
   325	        tradingExtension.validateTrade(_tradeInfo.asset, _tigAsset, _tradeInfo.margin, _tradeInfo.leverage);
   326	        _checkVault(_tradeInfo.stableVault, _tradeInfo.marginAsset);
   327	        if (_orderType == 0) revert("5");
   328	        if (_price == 0) revert NoPrice();
   329	        tradingExtension._setReferral(_tradeInfo.referral, _trader);
   330	        _handleDeposit(_tigAsset, _tradeInfo.marginAsset, _tradeInfo.margin, _tradeInfo.stableVault, _permitData, _trader);
   331	        _checkSl(_tradeInfo.slPrice, _tradeInfo.direction, _price);
   332	        uint256 _id = position.getCount();
   333	        position.mint(
   334	            IPosition.MintTrade(
   335	                _trader,
   336	                _tradeInfo.margin,
   337	                _tradeInfo.leverage,
   338	                _tradeInfo.asset,
   339	                _tradeInfo.direction,
   340	                _price,
   341	                _tradeInfo.tpPrice,
   342	                _tradeInfo.slPrice,
   343	                _orderType,
   344	                _tigAsset
   345	            )
   346	        );
   347	        limitDelay[_id] = block.timestamp + 4;
   348	        emit PositionOpened(_tradeInfo, _orderType, _price, _id, _trader, _tradeInfo.margin);
   349	    }
   350	
   351	    /**
   352	     * @param _id position ID
   353	     * @param _trader address the trade is initiated for
   354	     */
   355	    function cancelLimitOrder(
   356	        uint256 _id,
   357	        address _trader
   358	    )
   359	        external
   360	    {
   361	        _validateProxy(_trader);
   362	        _checkOwner(_id, _trader);
   363	        IPosition.Trade memory _trade = position.trades(_id);
   364	        if (_trade.orderType == 0) revert();
   365	        IStable(_trade.tigAsset).mintFor(_trader, _trade.margin);
   366	        position.burn(_id);
   367	        emit LimitCancelled(_id, _trader);
   368	    }
   369	
   370	    /**
   371	     * @param _id position id
   372	     * @param _marginAsset Token being used to add to the position
   373	     * @param _stableVault StableVault address
   374	     * @param _addMargin margin amount being added to the position
   375	     * @param _permitData data and signature needed for token approval
   376	     * @param _trader address the trade is initiated for
   377	     */
   378	    function addMargin(
   379	        uint256 _id,
   380	        address _marginAsset,
   381	        address _stableVault,
   382	        uint256 _addMargin,
   383	        ERC20PermitData calldata _permitData,
   384	        address _trader
   385	    )
   386	        external
   387	    {
   388	        _validateProxy(_trader);
   389	        _checkOwner(_id, _trader);
   390	        _checkVault(_stableVault, _marginAsset);
   391	        IPosition.Trade memory _trade = position.trades(_id);
   392	        if (_trade.orderType != 0) revert(); //IsLimit
   393	        IPairsContract.Asset memory asset = pairsContract.idToAsset(_trade.asset);
   394	        _handleDeposit(_trade.tigAsset, _marginAsset, _addMargin, _stableVault, _permitData, _trader);
   395	        unchecked {
   396	            uint256 _newMargin = _trade.margin + _addMargin;
   397	            uint256 _newLeverage = _trade.margin * _trade.leverage / _newMargin;
   398	            if (_newLeverage < asset.minLeverage) revert("!lev");
   399	            position.modifyMargin(_id, _newMargin, _newLeverage);
   400	            emit MarginModified(_id, _newMargin, _newLeverage, true, _trader);
   401	        }
   402	    }
   403	
   404	    /**
   405	     * @param _id position id
   406	     * @param _stableVault StableVault address
   407	     * @param _outputToken token the trader will receive
   408	     * @param _removeMargin margin amount being removed from the position
   409	     * @param _priceData verifiable off-chain price data
   410	     * @param _signature node signature
   411	     * @param _trader address the trade is initiated for
   412	     */
   413	    function removeMargin(
   414	        uint256 _id,
   415	        address _stableVault,
   416	        address _outputToken,
   417	        uint256 _removeMargin,
   418	        PriceData calldata _priceData,
   419	        bytes calldata _signature,
   420	        address _trader
   421	    )
   422	        external
   423	    {
   424	        _validateProxy(_trader);
   425	        _checkOwner(_id, _trader);
   426	        _checkVault(_stableVault, _outputToken);
   427	        IPosition.Trade memory _trade = position.trades(_id);
   428	        if (_trade.orderType != 0) revert(); //IsLimit
   429	        IPairsContract.Asset memory asset = pairsContract.idToAsset(_trade.asset);
   430	        uint256 _newMargin = _trade.margin - _removeMargin;
   431	        uint256 _newLeverage = _trade.margin * _trade.leverage / _newMargin;
   432	        if (_newLeverage > asset.maxLeverage) revert("!lev");
   433	        (uint _assetPrice,) = tradingExtension.getVerifiedPrice(_trade.asset, _priceData, _signature, 0);
   434	        (,int256 _payout) = TradingLibrary.pnl(_trade.direction, _assetPrice, _trade.price, _newMargin, _newLeverage, _trade.accInterest);
   435	        unchecked {
   436	            if (_payout <= int256(_newMargin*(DIVISION_CONSTANT-liqPercent)/DIVISION_CONSTANT)) revert LiqThreshold();
   437	        }
   438	        position.modifyMargin(_trade.id, _newMargin, _newLeverage);
   439	        _handleWithdraw(_trade, _stableVault, _outputToken, _removeMargin);
   440	        emit MarginModified(_trade.id, _newMargin, _newLeverage, false, _trader);
   441	    }
   442	
   443	    /**
   444	     * @param _type true for TP, false for SL
   445	     * @param _id position id
   446	     * @param _limitPrice TP/SL trigger price
   447	     * @param _priceData verifiable off-chain price data
   448	     * @param _signature node signature
   449	     * @param _trader address the trade is initiated for
   450	     */
   451	    function updateTpSl(
   452	        bool _type,
   453	        uint _id,
   454	        uint _limitPrice,
   455	        PriceData calldata _priceData,
   456	        bytes calldata _signature,
   457	        address _trader
   458	    )
   459	        external
   460	    {
   461	        _validateProxy(_trader);
   462	        _checkOwner(_id, _trader);
   463	        IPosition.Trade memory _trade = position.trades(_id);
   464	        if (_trade.orderType != 0) revert("4"); //IsLimit
   465	        if (_type) {
   466	            position.modifyTp(_id, _limitPrice);
   467	        } else {
   468	            (uint256 _price,) = tradingExtension.getVerifiedPrice(_trade.asset, _priceData, _signature, 0);
   469	            _checkSl(_limitPrice, _trade.direction, _price);
   470	            position.modifySl(_id, _limitPrice);
   471	        }
   472	        emit UpdateTPSL(_id, _type, _limitPrice, _trader);
   473	    }
   474	
   475	    /**
   476	     * @param _id position id
   477	     * @param _priceData verifiable off-chain price data
   478	     * @param _signature node signature
   479	     */
   480	    function executeLimitOrder(
   481	        uint _id, 
   482	        PriceData calldata _priceData,
   483	        bytes calldata _signature
   484	    ) 
   485	        external
   486	    {
   487	        unchecked {
   488	            _checkDelay(_id, true);
   489	            tradingExtension._checkGas();
   490	            if (tradingExtension.paused()) revert TradingPaused();
   491	            require(block.timestamp >= limitDelay[_id]);
   492	            IPosition.Trade memory trade = position.trades(_id);
   493	            uint _fee = _handleOpenFees(trade.asset, trade.margin*trade.leverage/1e18, trade.trader, trade.tigAsset, true);
   494	            (uint256 _price, uint256 _spread) = tradingExtension.getVerifiedPrice(trade.asset, _priceData, _signature, 0);
   495	            if (trade.orderType == 0) revert("5");
   496	            if (_price > trade.price+trade.price*limitOrderPriceRange/DIVISION_CONSTANT || _price < trade.price-trade.price*limitOrderPriceRange/DIVISION_CONSTANT) revert("6"); //LimitNotMet
   497	            if (trade.direction && trade.orderType == 1) {
   498	                if (trade.price < _price) revert("6"); //LimitNotMet
   499	            } else if (!trade.direction && trade.orderType == 1) {
   500	                if (trade.price > _price) revert("6"); //LimitNotMet
   501	            } else if (!trade.direction && trade.orderType == 2) {
   502	                if (trade.price < _price) revert("6"); //LimitNotMet
   503	                trade.price = _price;
   504	            } else {
   505	                if (trade.price > _price) revert("6"); //LimitNotMet
   506	                trade.price = _price;
   507	            } 
   508	            if(trade.direction) {
   509	                trade.price += trade.price * _spread / DIVISION_CONSTANT;
   510	            } else {
   511	                trade.price -= trade.price * _spread / DIVISION_CONSTANT;
   512	            }
   513	            if (trade.direction) {
   514	                tradingExtension.modifyLongOi(trade.asset, trade.tigAsset, true, trade.margin*trade.leverage/1e18);
   515	            } else {
   516	                tradingExtension.modifyShortOi(trade.asset, trade.tigAsset, true, trade.margin*trade.leverage/1e18);
   517	            }
   518	            _updateFunding(trade.asset, trade.tigAsset);
   519	            position.executeLimitOrder(_id, trade.price, trade.margin - _fee);
   520	            emit LimitOrderExecuted(trade.asset, trade.direction, trade.price, trade.leverage, trade.margin - _fee, _id, trade.trader, _msgSender());
   521	        }
   522	    }
   523	
   524	    /**
   525	     * @notice liquidate position
   526	     * @param _id id of the position NFT
   527	     * @param _priceData verifiable off-chain data
   528	     * @param _signature node signature
   529	     */
   530	    function liquidatePosition(
   531	        uint _id,
   532	        PriceData calldata _priceData,
   533	        bytes calldata _signature
   534	    )
   535	        external
   536	    {
   537	        unchecked {
   538	            tradingExtension._checkGas();
   539	            IPosition.Trade memory _trade = position.trades(_id);
   540	            if (_trade.orderType != 0) revert("4"); //IsLimit
   541	
   542	            (uint256 _price,) = tradingExtension.getVerifiedPrice(_trade.asset, _priceData, _signature, 0);
   543	            (uint256 _positionSizeAfterPrice, int256 _payout) = TradingLibrary.pnl(_trade.direction, _price, _trade.price, _trade.margin, _trade.leverage, _trade.accInterest);
   544	            uint256 _positionSize = _trade.margin*_trade.leverage/1e18;
   545	            if (_payout > int256(_trade.margin*(DIVISION_CONSTANT-liqPercent)/DIVISION_CONSTANT)) revert NotLiquidatable();
   546	            if (_trade.direction) {
   547	                tradingExtension.modifyLongOi(_trade.asset, _trade.tigAsset, false, _positionSize);
   548	            } else {
   549	                tradingExtension.modifyShortOi(_trade.asset, _trade.tigAsset, false, _positionSize);
   550	            }
   551	            _updateFunding(_trade.asset, _trade.tigAsset);
   552	            _handleCloseFees(_trade.asset, type(uint).max, _trade.tigAsset, _positionSizeAfterPrice, _trade.trader, true);
   553	            position.burn(_id);
   554	            emit PositionLiquidated(_id, _trade.trader, _msgSender());
   555	        }
   556	    }
   557	
   558	    /**
   559	     * @dev close position at a pre-set price
   560	     * @param _id id of the position NFT
   561	     * @param _tp true if take profit
   562	     * @param _priceData verifiable off-chain price data
   563	     * @param _signature node signature
   564	     */
   565	    function limitClose(
   566	        uint _id,
   567	        bool _tp,
   568	        PriceData calldata _priceData,
   569	        bytes calldata _signature
   570	    )
   571	        external
   572	    {
   573	        _checkDelay(_id, false);
   574	        (uint _limitPrice, address _tigAsset) = tradingExtension._limitClose(_id, _tp, _priceData, _signature);
   575	        _closePosition(_id, DIVISION_CONSTANT, _limitPrice, address(0), _tigAsset, true);
   576	    }
   577	
   578	    /**
   579	     * @notice Trader can approve a proxy wallet address for it to trade on its behalf. Can also provide proxy wallet with gas.
   580	     * @param _proxy proxy wallet address
   581	     * @param _timestamp end timestamp of approval period
   582	     */
   583	    function approveProxy(address _proxy, uint256 _timestamp) external payable {
   584	        proxyApprovals[_msgSender()] = Proxy(
   585	            _proxy,
   586	            _timestamp
   587	        );
   588	        payable(_proxy).transfer(msg.value);
   589	    }
   590	
   591	    // ===== INTERNAL FUNCTIONS =====
   592	
   593	    /**
   594	     * @dev close the initiated position.
   595	     * @param _id id of the position NFT
   596	     * @param _percent percent of the position being closed
   597	     * @param _price pair price
   598	     * @param _stableVault StableVault address
   599	     * @param _outputToken Token that trader will receive
   600	     * @param _isBot false if closed via market order
   601	     */
   602	    function _closePosition(
   603	        uint _id,
   604	        uint _percent,
   605	        uint _price,
   606	        address _stableVault,
   607	        address _outputToken,
   608	        bool _isBot
   609	    )
   610	        internal
   611	    {
   612	        (IPosition.Trade memory _trade, uint256 _positionSize, int256 _payout) = tradingExtension._closePosition(_id, _price, _percent);
   613	        position.setAccInterest(_id);
   614	        _updateFunding(_trade.asset, _trade.tigAsset);
   615	        if (_percent < DIVISION_CONSTANT) {
   616	            if ((_trade.margin*_trade.leverage*(DIVISION_CONSTANT-_percent)/DIVISION_CONSTANT)/1e18 < tradingExtension.minPos(_trade.tigAsset)) revert("!size");
   617	            position.reducePosition(_id, _percent);
   618	        } else {
   619	            position.burn(_id);
   620	        }
   621	        uint256 _toMint;
   622	        if (_payout > 0) {
   623	            unchecked {
   624	                _toMint = _handleCloseFees(_trade.asset, uint256(_payout)*_percent/DIVISION_CONSTANT, _trade.tigAsset, _positionSize*_percent/DIVISION_CONSTANT, _trade.trader, _isBot);
   625	                if (maxWinPercent > 0 && _toMint > _trade.margin*maxWinPercent/DIVISION_CONSTANT) {
   626	                    _toMint = _trade.margin*maxWinPercent/DIVISION_CONSTANT;
   627	                }
   628	            }
   629	            _handleWithdraw(_trade, _stableVault, _outputToken, _toMint);
   630	        }
   631	        emit PositionClosed(_id, _price, _percent, _toMint, _trade.trader, _isBot ? _msgSender() : _trade.trader);
   632	    }
   633	
   634	    /**
   635	     * @dev handle stablevault deposits for different trading functions
   636	     * @param _tigAsset tigAsset token address
   637	     * @param _marginAsset token being deposited into stablevault
   638	     * @param _margin amount being deposited
   639	     * @param _stableVault StableVault address
   640	     * @param _permitData Data for approval via permit
   641	     * @param _trader Trader address to take tokens from
   642	     */
   643	    function _handleDeposit(address _tigAsset, address _marginAsset, uint256 _margin, address _stableVault, ERC20PermitData calldata _permitData, address _trader) internal {
   644	        IStable tigAsset = IStable(_tigAsset);
   645	        if (_tigAsset != _marginAsset) {
   646	            if (_permitData.usePermit) {
   647	                ERC20Permit(_marginAsset).permit(_trader, address(this), _permitData.amount, _permitData.deadline, _permitData.v, _permitData.r, _permitData.s);
   648	            }
   649	            uint256 _balBefore = tigAsset.balanceOf(address(this));
   650	            uint _marginDecMultiplier = 10**(18-ExtendedIERC20(_marginAsset).decimals());
   651	            IERC20(_marginAsset).transferFrom(_trader, address(this), _margin/_marginDecMultiplier);
   652	            IERC20(_marginAsset).approve(_stableVault, type(uint).max);
   653	            IStableVault(_stableVault).deposit(_marginAsset, _margin/_marginDecMultiplier);
   654	            if (tigAsset.balanceOf(address(this)) != _balBefore + _margin) revert BadDeposit();
   655	            tigAsset.burnFrom(address(this), tigAsset.balanceOf(address(this)));
   656	        } else {
   657	            tigAsset.burnFrom(_trader, _margin);
   658	        }        
   659	    }
   660	
   661	    /**
   662	     * @dev handle stablevault withdrawals for different trading functions
   663	     * @param _trade Position info
   664	     * @param _stableVault StableVault address
   665	     * @param _outputToken Output token address
   666	     * @param _toMint Amount of tigAsset minted to be used for withdrawal
   667	     */
   668	    function _handleWithdraw(IPosition.Trade memory _trade, address _stableVault, address _outputToken, uint _toMint) internal {
   669	        IStable(_trade.tigAsset).mintFor(address(this), _toMint);
   670	        if (_outputToken == _trade.tigAsset) {
   671	            IERC20(_outputToken).transfer(_trade.trader, _toMint);
   672	        } else {
   673	            uint256 _balBefore = IERC20(_outputToken).balanceOf(address(this));
   674	            IStableVault(_stableVault).withdraw(_outputToken, _toMint);
   675	            if (IERC20(_outputToken).balanceOf(address(this)) != _balBefore + _toMint/(10**(18-ExtendedIERC20(_outputToken).decimals()))) revert BadWithdraw();
   676	            IERC20(_outputToken).transfer(_trade.trader, IERC20(_outputToken).balanceOf(address(this)) - _balBefore);
   677	        }        
   678	    }
   679	
   680	    /**
   681	     * @dev handle fees distribution for opening
   682	     * @param _asset asset id
   683	     * @param _positionSize position size
   684	     * @param _trader trader address
   685	     * @param _tigAsset tigAsset address
   686	     * @param _isBot false if opened via market order
   687	     * @return _feePaid total fees paid during opening
   688	     */
   689	    function _handleOpenFees(
   690	        uint _asset,
   691	        uint _positionSize,
   692	        address _trader,
   693	        address _tigAsset,
   694	        bool _isBot
   695	    )
   696	        internal
   697	        returns (uint _feePaid)
   698	    {
   699	        IPairsContract.Asset memory asset = pairsContract.idToAsset(_asset);
   700	        Fees memory _fees = openFees;
   701	        unchecked {
   702	            _fees.daoFees = _fees.daoFees * asset.feeMultiplier / DIVISION_CONSTANT;
   703	            _fees.burnFees = _fees.burnFees * asset.feeMultiplier / DIVISION_CONSTANT;
   704	            _fees.referralFees = _fees.referralFees * asset.feeMultiplier / DIVISION_CONSTANT;
   705	            _fees.botFees = _fees.botFees * asset.feeMultiplier / DIVISION_CONSTANT;
   706	        }
   707	        address _referrer = tradingExtension.getRef(_trader); //referrals.getReferral(referrals.getReferred(_trader));
   708	        if (_referrer != address(0)) {
   709	            unchecked {
   710	                IStable(_tigAsset).mintFor(
   711	                    _referrer,
   712	                    _positionSize
   713	                    * _fees.referralFees // get referral fee%
   714	                    / DIVISION_CONSTANT // divide by 100%
   715	                );
   716	            }
   717	            _fees.daoFees = _fees.daoFees - _fees.referralFees*2;
   718	        }
   719	        if (_isBot) {
   720	            unchecked {
   721	                IStable(_tigAsset).mintFor(
   722	                    _msgSender(),
   723	                    _positionSize
   724	                    * _fees.botFees // get bot fee%
   725	                    / DIVISION_CONSTANT // divide by 100%
   726	                );
   727	            }
   728	            _fees.daoFees = _fees.daoFees - _fees.botFees;
   729	        } else {
   730	            _fees.botFees = 0;
   731	        }
   732	        unchecked {
   733	            uint _daoFeesPaid = _positionSize * _fees.daoFees / DIVISION_CONSTANT;
   734	            _feePaid =
   735	                _positionSize
   736	                * (_fees.burnFees + _fees.botFees) // get total fee%
   737	                / DIVISION_CONSTANT // divide by 100%
   738	                + _daoFeesPaid;
   739	            emit FeesDistributed(
   740	                _tigAsset,
   741	                _daoFeesPaid,
   742	                _positionSize * _fees.burnFees / DIVISION_CONSTANT,
   743	                _referrer != address(0) ? _positionSize * _fees.referralFees / DIVISION_CONSTANT : 0,
   744	                _positionSize * _fees.botFees / DIVISION_CONSTANT,
   745	                _referrer
   746	            );
   747	            IStable(_tigAsset).mintFor(address(this), _daoFeesPaid);
   748	        }
   749	        gov.distribute(_tigAsset, IStable(_tigAsset).balanceOf(address(this)));
   750	    }
   751	
   752	    /**
   753	     * @dev handle fees distribution for closing
   754	     * @param _asset asset id
   755	     * @param _payout payout to trader before fees
   756	     * @param _tigAsset margin asset
   757	     * @param _positionSize position size
   758	     * @param _trader trader address
   759	     * @param _isBot false if closed via market order
   760	     * @return payout_ payout to trader after fees
   761	     */
   762	    function _handleCloseFees(
   763	        uint _asset,
   764	        uint _payout,
   765	        address _tigAsset,
   766	        uint _positionSize,
   767	        address _trader,
   768	        bool _isBot
   769	    )
   770	        internal
   771	        returns (uint payout_)
   772	    {
   773	        IPairsContract.Asset memory asset = pairsContract.idToAsset(_asset);
   774	        Fees memory _fees = closeFees;
   775	        uint _daoFeesPaid;
   776	        uint _burnFeesPaid;
   777	        uint _referralFeesPaid;
   778	        unchecked {
   779	            _daoFeesPaid = (_positionSize*_fees.daoFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
   780	            _burnFeesPaid = (_positionSize*_fees.burnFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
   781	        }
   782	        uint _botFeesPaid;
   783	        address _referrer = tradingExtension.getRef(_trader);//referrals.getReferral(referrals.getReferred(_trader));
   784	        if (_referrer != address(0)) {
   785	            unchecked {
   786	                _referralFeesPaid = (_positionSize*_fees.referralFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
   787	            }
   788	            IStable(_tigAsset).mintFor(
   789	                _referrer,
   790	                _referralFeesPaid
   791	            );
   792	             _daoFeesPaid = _daoFeesPaid-_referralFeesPaid*2;
   793	        }
   794	        if (_isBot) {
   795	            unchecked {
   796	                _botFeesPaid = (_positionSize*_fees.botFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
   797	                IStable(_tigAsset).mintFor(
   798	                    _msgSender(),
   799	                    _botFeesPaid
   800	                );
   801	            }
   802	            _daoFeesPaid = _daoFeesPaid - _botFeesPaid;
   803	        }
   804	        emit FeesDistributed(_tigAsset, _daoFeesPaid, _burnFeesPaid, _referralFeesPaid, _botFeesPaid, _referrer);
   805	        payout_ = _payout - _daoFeesPaid - _burnFeesPaid - _botFeesPaid;
   806	        IStable(_tigAsset).mintFor(address(this), _daoFeesPaid);
   807	        IStable(_tigAsset).approve(address(gov), type(uint).max);
   808	        gov.distribute(_tigAsset, _daoFeesPaid);
   809	        return payout_;
   810	    }
   811	
   812	    /**
   813	     * @dev update funding rates after open interest changes
   814	     * @param _asset asset id
   815	     * @param _tigAsset tigAsset used for OI
   816	     */
   817	    function _updateFunding(uint256 _asset, address _tigAsset) internal {
   818	        position.updateFunding(
   819	            _asset,
   820	            _tigAsset,
   821	            pairsContract.idToOi(_asset, _tigAsset).longOi,
   822	            pairsContract.idToOi(_asset, _tigAsset).shortOi,
   823	            pairsContract.idToAsset(_asset).baseFundingRate,
   824	            vaultFundingPercent
   825	        );
   826	    }
   827	
   828	    /**
   829	     * @dev check that SL price is valid compared to market price
   830	     * @param _sl SL price
   831	     * @param _direction long/short
   832	     * @param _price market price
   833	     */
   834	    function _checkSl(uint _sl, bool _direction, uint _price) internal pure {
   835	        if (_direction) {
   836	            if (_sl > _price) revert("3"); //BadStopLoss
   837	        } else {
   838	            if (_sl < _price && _sl != 0) revert("3"); //BadStopLoss
   839	        }
   840	    }
   841	
   842	    /**
   843	     * @dev check that trader address owns the position
   844	     * @param _id position id
   845	     * @param _trader trader address
   846	     */
   847	    function _checkOwner(uint _id, address _trader) internal view {
   848	        if (position.ownerOf(_id) != _trader) revert("2"); //NotPositionOwner   
   849	    }
   850	
   851	    /**
   852	     * @notice Check that sufficient time has passed between opening and closing
   853	     * @dev This is to prevent profitable opening and closing in the same tx with two different prices in the "valid signature pool".
   854	     * @param _id position id
   855	     * @param _type true for opening, false for closing
   856	     */
   857	    function _checkDelay(uint _id, bool _type) internal {
   858	        unchecked {
   859	            Delay memory _delay = blockDelayPassed[_id];
   860	            if (_delay.actionType == _type) {
   861	                blockDelayPassed[_id].delay = block.number + blockDelay;
   862	            } else {
   863	                if (block.number < _delay.delay) revert("0"); //Wait
   864	                blockDelayPassed[_id].delay = block.number + blockDelay;
   865	                blockDelayPassed[_id].actionType = _type;
   866	            }
   867	        }
   868	    }
   869	
   870	    /**
   871	     * @dev Check that the stablevault input is whitelisted and the margin asset is whitelisted in the vault
   872	     * @param _stableVault StableVault address
   873	     * @param _token Margin asset token address
   874	     */
   875	    function _checkVault(address _stableVault, address _token) internal view {
   876	        require(allowedVault[_stableVault], "Unapproved stablevault");
   877	        require(_token == IStableVault(_stableVault).stable() || IStableVault(_stableVault).allowed(_token), "Token not approved in vault");
   878	    }
   879	
   880	    /**
   881	     * @dev Check that the trader has approved the proxy address to trade for it
   882	     * @param _trader Trader address
   883	     */
   884	    function _validateProxy(address _trader) internal view {
   885	        if (_trader != _msgSender()) {
   886	            Proxy memory _proxy = proxyApprovals[_trader];
   887	            require(_proxy.proxy == _msgSender() && _proxy.time >= block.timestamp, "Proxy not approved");
   888	        }
   889	    }
   890	
   891	    // ===== GOVERNANCE-ONLY =====
   892	
   893	    /**
   894	     * @dev Sets block delay between opening and closing
   895	     * @notice In blocks not seconds
   896	     * @param _blockDelay delay amount
   897	     */
   898	    function setBlockDelay(
   899	        uint _blockDelay
   900	    )
   901	        external
   902	        onlyOwner
   903	    {
   904	        blockDelay = _blockDelay;
   905	    }
   906	
   907	    /**
   908	     * @dev Whitelists a stablevault contract address
   909	     * @param _stableVault StableVault address
   910	     * @param _bool true if allowed
   911	     */
   912	    function setAllowedVault(
   913	        address _stableVault,
   914	        bool _bool
   915	    )
   916	        external
   917	        onlyOwner
   918	    {
   919	        allowedVault[_stableVault] = _bool;
   920	    }
   921	
   922	    /**
   923	     * @dev Sets max payout % compared to margin
   924	     * @param _maxWinPercent payout %
   925	     */
   926	    function setMaxWinPercent(
   927	        uint _maxWinPercent
   928	    )
   929	        external
   930	        onlyOwner
   931	    {
   932	        maxWinPercent = _maxWinPercent;
   933	    }
   934	
   935	    /**
   936	     * @dev Sets executable price range for limit orders
   937	     * @param _range price range in %
   938	     */
   939	    function setLimitOrderPriceRange(uint _range) external onlyOwner {
   940	        limitOrderPriceRange = _range;
   941	    }
   942	
   943	    /**
   944	     * @dev Sets the fees for the trading protocol
   945	     * @param _open True if open fees are being set
   946	     * @param _daoFees Fees distributed to the DAO
   947	     * @param _burnFees Fees which get burned
   948	     * @param _referralFees Fees given to referrers
   949	     * @param _botFees Fees given to bots that execute limit orders
   950	     * @param _percent Percent of earned funding fees going to StableVault
   951	     */
   952	    function setFees(bool _open, uint _daoFees, uint _burnFees, uint _referralFees, uint _botFees, uint _percent) external onlyOwner {
   953	        unchecked {
   954	            require(_daoFees >= _botFees+_referralFees*2);
   955	            if (_open) {
   956	                openFees.daoFees = _daoFees;
   957	                openFees.burnFees = _burnFees;
   958	                openFees.referralFees = _referralFees;
   959	                openFees.botFees = _botFees;
   960	            } else {
   961	                closeFees.daoFees = _daoFees;
   962	                closeFees.burnFees = _burnFees;
   963	                closeFees.referralFees = _referralFees;
   964	                closeFees.botFees = _botFees;                
   965	            }
   966	            require(_percent <= DIVISION_CONSTANT);
   967	            vaultFundingPercent = _percent;
   968	        }
   969	    }
   970	
   971	    /**
   972	     * @dev Sets the extension contract address for trading
   973	     * @param _ext extension contract address
   974	     */
   975	    function setTradingExtension(
   976	        address _ext
   977	    ) external onlyOwner() {
   978	        tradingExtension = ITradingExtension(_ext);
   979	    }
   980	
   981	    // ===== EVENTS =====
   982	
   983	    event PositionOpened(
   984	        TradeInfo _tradeInfo,
   985	        uint _orderType,
   986	        uint _price,
   987	        uint _id,
   988	        address _trader,
   989	        uint _marginAfterFees
   990	    );
   991	
   992	    event PositionClosed(
   993	        uint _id,
   994	        uint _closePrice,
   995	        uint _percent,
   996	        uint _payout,
   997	        address _trader,
   998	        address _executor
   999	    );
  1000	
  1001	    event PositionLiquidated(
  1002	        uint _id,
  1003	        address _trader,
  1004	        address _executor
  1005	    );
  1006	
  1007	    event LimitOrderExecuted(
  1008	        uint _asset,
  1009	        bool _direction,
  1010	        uint _openPrice,
  1011	        uint _lev,
  1012	        uint _margin,
  1013	        uint _id,
  1014	        address _trader,
  1015	        address _executor
  1016	    );
  1017	
  1018	    event UpdateTPSL(
  1019	        uint _id,
  1020	        bool _isTp,
  1021	        uint _price,
  1022	        address _trader
  1023	    );
  1024	
  1025	    event LimitCancelled(
  1026	        uint _id,
  1027	        address _trader
  1028	    );
  1029	
  1030	    event MarginModified(
  1031	        uint _id,
  1032	        uint _newMargin,
  1033	        uint _newLeverage,
  1034	        bool _isMarginAdded,
  1035	        address _trader
  1036	    );
  1037	
  1038	    event AddToPosition(
  1039	        uint _id,
  1040	        uint _newMargin,
  1041	        uint _newPrice,
  1042	        address _trader
  1043	    );
  1044	
  1045	    event FeesDistributed(
  1046	        address _tigAsset,
  1047	        uint _daoFees,
  1048	        uint _burnFees,
  1049	        uint _refFees,
  1050	        uint _botFees,
  1051	        address _referrer
  1052	    );
  1053	}
