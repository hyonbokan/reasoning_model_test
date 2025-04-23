     1	// SPDX-License-Identifier: MIT
     2	pragma solidity ^0.8.0;
     3	
     4	import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
     5	import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
     6	import "@openzeppelin/contracts/access/Ownable.sol";
     7	
     8	contract BondNFT is ERC721Enumerable, Ownable {
     9	    
    10	    uint constant private DAY = 24 * 60 * 60;
    11	
    12	    struct Bond {
    13	        uint id;
    14	        address owner;
    15	        address asset;
    16	        uint amount;
    17	        uint mintEpoch;
    18	        uint mintTime;
    19	        uint expireEpoch;
    20	        uint pending;
    21	        uint shares;
    22	        uint period;
    23	        bool expired;
    24	    }
    25	
    26	    mapping(address => uint256) public epoch;
    27	    uint private totalBonds;
    28	    string public baseURI;
    29	    address public manager;
    30	    address[] public assets;
    31	
    32	    mapping(address => bool) public allowedAsset;
    33	    mapping(address => uint) private assetsIndex;
    34	    mapping(uint256 => mapping(address => uint256)) private bondPaid;
    35	    mapping(address => mapping(uint256 => uint256)) private accRewardsPerShare; // tigAsset => epoch => accRewardsPerShare
    36	    mapping(uint => Bond) private _idToBond;
    37	    mapping(address => uint) public totalShares;
    38	    mapping(address => mapping(address => uint)) public userDebt; // user => tigAsset => amount
    39	
    40	    constructor(
    41	        string memory _setBaseURI,
    42	        string memory _name,
    43	        string memory _symbol
    44	    ) ERC721(_name, _symbol) {
    45	        baseURI = _setBaseURI;
    46	    }
    47	
    48	    /**
    49	     * @notice Create a bond
    50	     * @dev Should only be called by a manager contract
    51	     * @param _asset tigAsset token to lock
    52	     * @param _amount tigAsset amount
    53	     * @param _period time to lock for in days
    54	     * @param _owner address to receive the bond
    55	     * @return id ID of the minted bond
    56	     */
    57	    function createLock(
    58	        address _asset,
    59	        uint _amount,
    60	        uint _period,
    61	        address _owner
    62	    ) external onlyManager() returns(uint id) {
    63	        require(allowedAsset[_asset], "!Asset");
    64	        unchecked {
    65	            uint shares = _amount * _period / 365;
    66	            uint expireEpoch = epoch[_asset] + _period;
    67	            id = ++totalBonds;
    68	            totalShares[_asset] += shares;
    69	            Bond memory _bond = Bond(
    70	                id,             // id
    71	                address(0),     // owner
    72	                _asset,         // tigAsset token
    73	                _amount,        // tigAsset amount
    74	                epoch[_asset],  // mint epoch
    75	                block.timestamp,// mint timestamp
    76	                expireEpoch,    // expire epoch
    77	                0,              // pending
    78	                shares,         // linearly scaling share of rewards
    79	                _period,        // lock period
    80	                false           // is expired boolean
    81	            );
    82	            _idToBond[id] = _bond;
    83	            _mint(_owner, _bond);
    84	        }
    85	        emit Lock(_asset, _amount, _period, _owner, id);
    86	    }
    87	
    88	    /** 
    89	     * @notice Extend the lock period and/or amount of a bond
    90	     * @dev Should only be called by a manager contract
    91	     * @param _id ID of the bond
    92	     * @param _asset tigAsset token address
    93	     * @param _amount amount of tigAsset being added
    94	     * @param _period days being added to the bond
    95	     * @param _sender address extending the bond
    96	     */
    97	    function extendLock(
    98	        uint _id,
    99	        address _asset,
   100	        uint _amount,
   101	        uint _period,
   102	        address _sender
   103	    ) external onlyManager() {
   104	        Bond memory bond = idToBond(_id);
   105	        Bond storage _bond = _idToBond[_id];
   106	        require(bond.owner == _sender, "!owner");
   107	        require(!bond.expired, "Expired");
   108	        require(bond.asset == _asset, "!BondAsset");
   109	        require(bond.pending == 0);
   110	        require(epoch[bond.asset] == block.timestamp/DAY, "Bad epoch");
   111	        require(bond.period+_period <= 365, "MAX PERIOD");
   112	        unchecked {
   113	            uint shares = (bond.amount + _amount) * (bond.period + _period) / 365;
   114	            uint expireEpoch = block.timestamp/DAY + bond.period + _period;
   115	            totalShares[bond.asset] += shares-bond.shares;
   116	            _bond.shares = shares;
   117	            _bond.amount += _amount;
   118	            _bond.expireEpoch = expireEpoch;
   119	            _bond.period += _period;
   120	            _bond.mintTime = block.timestamp;
   121	            _bond.mintEpoch = epoch[bond.asset];
   122	            bondPaid[_id][bond.asset] = accRewardsPerShare[bond.asset][epoch[bond.asset]] * _bond.shares / 1e18;
   123	        }
   124	        emit ExtendLock(_period, _amount, _sender,  _id);
   125	    }
   126	
   127	    /**
   128	     * @notice Release a bond
   129	     * @dev Should only be called by a manager contract
   130	     * @param _id ID of the bond
   131	     * @param _releaser address initiating the release of the bond
   132	     * @return amount amount of tigAsset returned
   133	     * @return lockAmount amount of tigAsset locked in the bond
   134	     * @return asset tigAsset token released
   135	     * @return _owner bond owner
   136	     */
   137	    function release(
   138	        uint _id,
   139	        address _releaser
   140	    ) external onlyManager() returns(uint amount, uint lockAmount, address asset, address _owner) {
   141	        Bond memory bond = idToBond(_id);
   142	        require(bond.expired, "!expire");
   143	        if (_releaser != bond.owner) {
   144	            unchecked {
   145	                require(bond.expireEpoch + 7 < epoch[bond.asset], "Bond owner priority");
   146	            }
   147	        }
   148	        amount = bond.amount;
   149	        unchecked {
   150	            totalShares[bond.asset] -= bond.shares;
   151	            (uint256 _claimAmount,) = claim(_id, bond.owner);
   152	            amount += _claimAmount;
   153	        }
   154	        asset = bond.asset;
   155	        lockAmount = bond.amount;
   156	        _owner = bond.owner;
   157	        _burn(_id);
   158	        emit Release(asset, lockAmount, _owner, _id);
   159	    }
   160	    /**
   161	     * @notice Claim rewards from a bond
   162	     * @dev Should only be called by a manager contract
   163	     * @param _id ID of the bond to claim rewards from
   164	     * @param _claimer address claiming rewards
   165	     * @return amount amount of tigAsset claimed
   166	     * @return tigAsset tigAsset token address
   167	     */
   168	    function claim(
   169	        uint _id,
   170	        address _claimer
   171	    ) public onlyManager() returns(uint amount, address tigAsset) {
   172	        Bond memory bond = idToBond(_id);
   173	        require(_claimer == bond.owner, "!owner");
   174	        amount = bond.pending;
   175	        tigAsset = bond.asset;
   176	        unchecked {
   177	            if (bond.expired) {
   178	                uint _pendingDelta = (bond.shares * accRewardsPerShare[bond.asset][epoch[bond.asset]] / 1e18 - bondPaid[_id][bond.asset]) - (bond.shares * accRewardsPerShare[bond.asset][bond.expireEpoch-1] / 1e18 - bondPaid[_id][bond.asset]);
   179	                if (totalShares[bond.asset] > 0) {
   180	                    accRewardsPerShare[bond.asset][epoch[bond.asset]] += _pendingDelta*1e18/totalShares[bond.asset];
   181	                }
   182	            }
   183	            bondPaid[_id][bond.asset] += amount;
   184	        }
   185	        IERC20(tigAsset).transfer(manager, amount);
   186	        emit ClaimFees(tigAsset, amount, _claimer, _id);
   187	    }
   188	
   189	    /**
   190	     * @notice Claim user debt left from bond transfer
   191	     * @dev Should only be called by a manager contract
   192	     * @param _user user address
   193	     * @param _tigAsset tigAsset token address
   194	     * @return amount amount of tigAsset claimed
   195	     */
   196	    function claimDebt(
   197	        address _user,
   198	        address _tigAsset
   199	    ) public onlyManager() returns(uint amount) {
   200	        amount = userDebt[_user][_tigAsset];
   201	        userDebt[_user][_tigAsset] = 0;
   202	        IERC20(_tigAsset).transfer(manager, amount);
   203	        emit ClaimDebt(_tigAsset, amount, _user);
   204	    }
   205	
   206	    /**
   207	     * @notice Distribute rewards to bonds
   208	     * @param _tigAsset tigAsset token address
   209	     * @param _amount tigAsset amount
   210	     */
   211	    function distribute(
   212	        address _tigAsset,
   213	        uint _amount
   214	    ) external {
   215	        if (totalShares[_tigAsset] == 0 || !allowedAsset[_tigAsset]) return;
   216	        IERC20(_tigAsset).transferFrom(_msgSender(), address(this), _amount);
   217	        unchecked {
   218	            uint aEpoch = block.timestamp / DAY;
   219	            if (aEpoch > epoch[_tigAsset]) {
   220	                for (uint i=epoch[_tigAsset]; i<aEpoch; i++) {
   221	                    epoch[_tigAsset] += 1;
   222	                    accRewardsPerShare[_tigAsset][i+1] = accRewardsPerShare[_tigAsset][i];
   223	                }
   224	            }
   225	            accRewardsPerShare[_tigAsset][aEpoch] += _amount * 1e18 / totalShares[_tigAsset];
   226	        }
   227	        emit Distribution(_tigAsset, _amount);
   228	    }
   229	
   230	    /**
   231	     * @notice Get all data for a bond
   232	     * @param _id ID of the bond
   233	     * @return bond Bond object
   234	     */
   235	    function idToBond(uint256 _id) public view returns (Bond memory bond) {
   236	        bond = _idToBond[_id];
   237	        bond.owner = ownerOf(_id);
   238	        bond.expired = bond.expireEpoch <= epoch[bond.asset] ? true : false;
   239	        unchecked {
   240	            uint _accRewardsPerShare = accRewardsPerShare[bond.asset][bond.expired ? bond.expireEpoch-1 : epoch[bond.asset]];
   241	            bond.pending = bond.shares * _accRewardsPerShare / 1e18 - bondPaid[_id][bond.asset];
   242	        }
   243	    }
   244	
   245	    /*
   246	     * @notice Get expired boolean for a bond
   247	     * @param _id ID of the bond
   248	     * @return bool true if bond is expired
   249	     */
   250	    function isExpired(uint256 _id) public view returns (bool) {
   251	        Bond memory bond = _idToBond[_id];
   252	        return bond.expireEpoch <= epoch[bond.asset] ? true : false;
   253	    }
   254	
   255	    /*
   256	     * @notice Get pending rewards for a bond
   257	     * @param _id ID of the bond
   258	     * @return bool true if bond is expired
   259	     */
   260	    function pending(
   261	        uint256 _id
   262	    ) public view returns (uint256) {
   263	        return idToBond(_id).pending;
   264	    }
   265	
   266	    function totalAssets() public view returns (uint256) {
   267	        return assets.length;
   268	    }
   269	
   270	    /*
   271	     * @notice Gets an array of all whitelisted token addresses
   272	     * @return address array of addresses
   273	     */
   274	    function getAssets() public view returns (address[] memory) {
   275	        return assets;
   276	    }
   277	
   278	    function _baseURI() internal override view returns (string memory) {
   279	        return baseURI;
   280	    }
   281	
   282	    function safeTransferMany(address _to, uint[] calldata _ids) external {
   283	        unchecked {
   284	            for (uint i=0; i<_ids.length; i++) {
   285	                _transfer(_msgSender(), _to, _ids[i]);
   286	            }
   287	        }
   288	    }
   289	
   290	    function safeTransferFromMany(address _from, address _to, uint[] calldata _ids) external {
   291	        unchecked {
   292	            for (uint i=0; i<_ids.length; i++) {
   293	                safeTransferFrom(_from, _to, _ids[i]);
   294	            }
   295	        }
   296	    }
   297	
   298	    function approveMany(address _to, uint[] calldata _ids) external {
   299	        unchecked {
   300	            for (uint i=0; i<_ids.length; i++) {
   301	                approve(_to, _ids[i]);
   302	            }
   303	        }
   304	    }
   305	
   306	    function _mint(
   307	        address to,
   308	        Bond memory bond
   309	    ) internal {
   310	        unchecked {
   311	            bondPaid[bond.id][bond.asset] = accRewardsPerShare[bond.asset][epoch[bond.asset]] * bond.shares / 1e18;
   312	        }
   313	        _mint(to, bond.id);
   314	    }
   315	
   316	    function _burn(
   317	        uint256 _id
   318	    ) internal override {
   319	        delete _idToBond[_id];
   320	        super._burn(_id);
   321	    }
   322	
   323	    function _transfer(
   324	        address from,
   325	        address to,
   326	        uint256 _id
   327	    ) internal override {
   328	        Bond memory bond = idToBond(_id);
   329	        require(epoch[bond.asset] == block.timestamp/DAY, "Bad epoch");
   330	        require(!bond.expired, "Expired!");
   331	        unchecked {
   332	            require(block.timestamp > bond.mintTime + 300, "Recent update");
   333	            userDebt[from][bond.asset] += bond.pending;
   334	            bondPaid[_id][bond.asset] += bond.pending;
   335	        }
   336	        super._transfer(from, to, _id);
   337	    }
   338	
   339	    function balanceIds(address _user) public view returns (uint[] memory) {
   340	        uint[] memory _ids = new uint[](balanceOf(_user));
   341	        unchecked {
   342	            for (uint i=0; i<_ids.length; i++) {
   343	                _ids[i] = tokenOfOwnerByIndex(_user, i);
   344	            }
   345	        }
   346	        return _ids;
   347	    }
   348	
   349	    function addAsset(address _asset) external onlyOwner {
   350	        require(assets.length == 0 || assets[assetsIndex[_asset]] != _asset, "Already added");
   351	        assetsIndex[_asset] = assets.length;
   352	        assets.push(_asset);
   353	        allowedAsset[_asset] = true;
   354	        epoch[_asset] = block.timestamp/DAY;
   355	    }
   356	
   357	    function setAllowedAsset(address _asset, bool _bool) external onlyOwner {
   358	        require(assets[assetsIndex[_asset]] == _asset, "Not added");
   359	        allowedAsset[_asset] = _bool;
   360	    }
   361	
   362	    function setBaseURI(string calldata _newBaseURI) external onlyOwner {
   363	        baseURI = _newBaseURI;
   364	    }
   365	
   366	    function setManager(
   367	        address _manager
   368	    ) public onlyOwner() {
   369	        manager = _manager;
   370	    }
   371	
   372	    modifier onlyManager() {
   373	        require(msg.sender == manager, "!manager");
   374	        _;
   375	    }
   376	
   377	    event Distribution(address _tigAsset, uint256 _amount);
   378	    event Lock(address _tigAsset, uint256 _amount, uint256 _period, address _owner, uint256 _id);
   379	    event ExtendLock(uint256 _period, uint256 _amount, address _owner, uint256 _id);
   380	    event Release(address _tigAsset, uint256 _amount, address _owner, uint256 _id);
   381	    event ClaimFees(address _tigAsset, uint256 _amount, address _claimer, uint256 _id);
   382	    event ClaimDebt(address _tigAsset, uint256 _amount, address _owner);
   383	}