     1	// SPDX-License-Identifier: MIT
     2	pragma solidity ^0.8.0;
     3	
     4	import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
     5	import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
     6	import "./interfaces/ILayerZeroEndpoint.sol";
     7	import "./interfaces/ILayerZeroReceiver.sol";
     8	import "./utils/MetaContext.sol";
     9	import "./interfaces/IGovNFT.sol";
    10	import "./utils/ExcessivelySafeCall.sol";
    11	
    12	contract GovNFT is ERC721Enumerable, ILayerZeroReceiver, MetaContext, IGovNFT {
    13	    using ExcessivelySafeCall for address;
    14	    
    15	    uint256 private counter = 1;
    16	    uint256 private constant MAX = 10000;
    17	    uint256 public gas = 150000;
    18	    string public baseURI;
    19	    uint256 public maxBridge = 20;
    20	    ILayerZeroEndpoint public endpoint;
    21	
    22	    mapping(uint16 => mapping(address => bool)) public isTrustedAddress;
    23	    mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) public failedMessages;
    24	    event MessageFailed(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes _payload, bytes _reason);
    25	    event RetryMessageSuccess(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes32 _payloadHash);
    26	    event ReceiveNFT(
    27	        uint16 _srcChainId,
    28	        address _from,
    29	        uint256[] _tokenId
    30	    );
    31	
    32	    constructor(
    33	        address _endpoint,
    34	        string memory _setBaseURI,
    35	        string memory _name,
    36	        string memory _symbol
    37	    ) ERC721(_name, _symbol) {
    38	        endpoint = ILayerZeroEndpoint(_endpoint);
    39	        baseURI = _setBaseURI;
    40	    }
    41	
    42	    function _baseURI() internal override view returns (string memory) {
    43	        return baseURI;
    44	    }
    45	
    46	    function setBaseURI(string calldata _newBaseURI) external onlyOwner {
    47	        baseURI = _newBaseURI;
    48	    }
    49	
    50	    function _mint(address to, uint256 tokenId) internal override {
    51	        require(counter <= MAX, "Exceeds supply");
    52	        counter += 1;
    53	        for (uint i=0; i<assetsLength(); i++) {
    54	            userPaid[to][assets[i]] += accRewardsPerNFT[assets[i]];
    55	        }
    56	        super._mint(to, tokenId);
    57	    }
    58	
    59	    /**
    60	     * @dev should only be called by layer zero
    61	     * @param to the address to receive the bridged NFTs
    62	     * @param tokenId the NFT id
    63	     */
    64	    function _bridgeMint(address to, uint256 tokenId) public {
    65	        require(msg.sender == address(this) || _msgSender() == owner(), "NotBridge");
    66	        require(tokenId <= 10000, "BadID");
    67	        for (uint i=0; i<assetsLength(); i++) {
    68	            userPaid[to][assets[i]] += accRewardsPerNFT[assets[i]];
    69	        }
    70	        super._mint(to, tokenId);
    71	    }
    72	
    73	    /**
    74	    * @notice updates userDebt 
    75	    */
    76	    function _burn(uint256 tokenId) internal override {
    77	        address owner = ownerOf(tokenId);
    78	        for (uint i=0; i<assetsLength(); i++) {
    79	            userDebt[owner][assets[i]] += accRewardsPerNFT[assets[i]];
    80	            userDebt[owner][assets[i]] -= userPaid[owner][assets[i]]/balanceOf(owner);
    81	            userPaid[owner][assets[i]] -= userPaid[owner][assets[i]]/balanceOf(owner);            
    82	        }
    83	        super._burn(tokenId);
    84	    }
    85	
    86	    /**
    87	    * @notice updates userDebt for both to and from
    88	    */
    89	    function _transfer(
    90	        address from,
    91	        address to,
    92	        uint256 tokenId
    93	    ) internal override {
    94	        require(ownerOf(tokenId) == from, "!Owner");
    95	        for (uint i=0; i<assetsLength(); i++) {
    96	            userDebt[from][assets[i]] += accRewardsPerNFT[assets[i]];
    97	            userDebt[from][assets[i]] -= userPaid[from][assets[i]]/balanceOf(from);
    98	            userPaid[from][assets[i]] -= userPaid[from][assets[i]]/balanceOf(from);
    99	            userPaid[to][assets[i]] += accRewardsPerNFT[assets[i]];
   100	        }
   101	        super._transfer(from, to, tokenId);
   102	    }
   103	
   104	    function mintMany(uint _amount) external onlyOwner {
   105	        for (uint i=0; i<_amount; i++) {
   106	            _mint(_msgSender(), counter);
   107	        }
   108	    }
   109	
   110	    function mint() external onlyOwner {
   111	        _mint(_msgSender(), counter);
   112	    }
   113	
   114	    function setTrustedAddress(uint16 _chainId, address _contract, bool _bool) external onlyOwner {
   115	        isTrustedAddress[_chainId][_contract] = _bool;
   116	    }
   117	
   118	    /**
   119	    * @notice used to bridge NFTs crosschain using layer zero
   120	    * @param _dstChainId the layer zero id of the dest chain
   121	    * @param _to receiving address on dest chain
   122	    * @param tokenId array of the ids of the NFTs to be bridged
   123	    */
   124	    function crossChain(
   125	        uint16 _dstChainId,
   126	        bytes memory _destination,
   127	        address _to,
   128	        uint256[] memory tokenId
   129	    ) public payable {
   130	        require(tokenId.length > 0, "Not bridging");
   131	        for (uint i=0; i<tokenId.length; i++) {
   132	            require(_msgSender() == ownerOf(tokenId[i]), "Not the owner");
   133	            // burn NFT
   134	            _burn(tokenId[i]);
   135	        }
   136	        address targetAddress;
   137	        assembly {
   138	            targetAddress := mload(add(_destination, 20))
   139	        }
   140	        require(isTrustedAddress[_dstChainId][targetAddress], "!Trusted");
   141	        bytes memory payload = abi.encode(_to, tokenId);
   142	        // encode adapterParams to specify more gas for the destination
   143	        uint16 version = 1;
   144	        uint256 _gas = 500_000 + gas*tokenId.length;
   145	        bytes memory adapterParams = abi.encodePacked(version, _gas);
   146	        (uint256 messageFee, ) = endpoint.estimateFees(
   147	            _dstChainId,
   148	            address(this),
   149	            payload,
   150	            false,
   151	            adapterParams
   152	        );
   153	        require(
   154	            msg.value >= messageFee,
   155	            "Must send enough value to cover messageFee"
   156	        );
   157	        endpoint.send{value: msg.value}(
   158	            _dstChainId,
   159	            _destination,
   160	            payload,
   161	            payable(_msgSender()),
   162	            address(0x0),
   163	            adapterParams
   164	        );
   165	    }
   166	
   167	
   168	    function lzReceive(
   169	        uint16 _srcChainId,
   170	        bytes memory _srcAddress,
   171	        uint64 _nonce,
   172	        bytes memory _payload
   173	    ) external override {
   174	        require(_msgSender() == address(endpoint), "!Endpoint");
   175	        (bool success, bytes memory reason) = address(this).excessivelySafeCall(gasleft()*4/5, 150, abi.encodeWithSelector(this.nonblockingLzReceive.selector, _srcChainId, _srcAddress, _nonce, _payload));
   176	        // try-catch all errors/exceptions
   177	        if (!success) {
   178	            failedMessages[_srcChainId][_srcAddress][_nonce] = keccak256(_payload);
   179	            emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload, reason);
   180	        }
   181	    }
   182	
   183	    function nonblockingLzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) public {
   184	        // only internal transaction
   185	        require(msg.sender == address(this), "NonblockingLzApp: caller must be app");
   186	        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
   187	    }
   188	
   189	    function _nonblockingLzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64, bytes memory _payload) internal {
   190	        address fromAddress;
   191	        assembly {
   192	            fromAddress := mload(add(_srcAddress, 20))
   193	        }
   194	        require(isTrustedAddress[_srcChainId][fromAddress], "!TrustedAddress");
   195	        (address toAddress, uint256[] memory tokenId) = abi.decode(
   196	            _payload,
   197	            (address, uint256[])
   198	        );
   199	        // mint the tokens
   200	        for (uint i=0; i<tokenId.length; i++) {
   201	            _bridgeMint(toAddress, tokenId[i]);
   202	        }
   203	        emit ReceiveNFT(_srcChainId, toAddress, tokenId);
   204	    }
   205	
   206	    function retryMessage(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) public {
   207	        // assert there is message to retry
   208	        bytes32 payloadHash = failedMessages[_srcChainId][_srcAddress][_nonce];
   209	        require(payloadHash != bytes32(0), "NonblockingLzApp: no stored message");
   210	        require(keccak256(_payload) == payloadHash, "NonblockingLzApp: invalid payload");
   211	        // clear the stored message
   212	        failedMessages[_srcChainId][_srcAddress][_nonce] = bytes32(0);
   213	        // execute the message. revert if it fails again
   214	        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
   215	        emit RetryMessageSuccess(_srcChainId, _srcAddress, _nonce, payloadHash);
   216	    }
   217	
   218	    // Endpoint.sol estimateFees() returns the fees for the message
   219	    function estimateFees(
   220	        uint16 _dstChainId,
   221	        address _userApplication,
   222	        bytes calldata _payload,
   223	        bool _payInZRO,
   224	        bytes calldata _adapterParams
   225	    ) external view returns (uint256 nativeFee, uint256 zroFee) {
   226	        return
   227	            endpoint.estimateFees(
   228	                _dstChainId,
   229	                _userApplication,
   230	                _payload,
   231	                _payInZRO,
   232	                _adapterParams
   233	            );
   234	    }
   235	
   236	    function setGas(uint _gas) external onlyOwner {
   237	        gas = _gas;
   238	    }
   239	
   240	    function setEndpoint(ILayerZeroEndpoint _endpoint) external onlyOwner {
   241	        require(address(_endpoint) != address(0), "ZeroAddress");
   242	        endpoint = _endpoint;
   243	    }
   244	
   245	    function safeTransferMany(address _to, uint[] calldata _ids) external {
   246	        for (uint i=0; i<_ids.length; i++) {
   247	            _transfer(_msgSender(), _to, _ids[i]);
   248	        }
   249	    }
   250	
   251	    function safeTransferFromMany(address _from, address _to, uint[] calldata _ids) external {
   252	        for (uint i=0; i<_ids.length; i++) {
   253	            safeTransferFrom(_from, _to, _ids[i]);
   254	        }
   255	    }
   256	
   257	    function approveMany(address _to, uint[] calldata _ids) external {
   258	        for (uint i=0; i<_ids.length; i++) {
   259	            approve(_to, _ids[i]);
   260	        }
   261	    }
   262	
   263	    // Rewards
   264	    address[] public assets;
   265	    mapping(address => bool) private _allowedAsset;
   266	    mapping(address => uint) private assetsIndex;
   267	    mapping(address => mapping(address => uint256)) private userPaid;
   268	    mapping(address => mapping(address => uint256)) private userDebt;
   269	    mapping(address => uint256) private accRewardsPerNFT;
   270	
   271	    /**
   272	    * @notice claimable by anyone to claim pending rewards tokens
   273	    * @param _tigAsset reward token address
   274	    */
   275	    function claim(address _tigAsset) external {
   276	        address _msgsender = _msgSender();
   277	        uint256 amount = pending(_msgsender, _tigAsset);
   278	        userPaid[_msgsender][_tigAsset] += amount;
   279	        IERC20(_tigAsset).transfer(_msgsender, amount);
   280	    }
   281	
   282	    /**
   283	    * @notice add rewards for NFT holders
   284	    * @param _tigAsset reward token address
   285	    * @param _amount amount to be distributed
   286	    */
   287	    function distribute(address _tigAsset, uint _amount) external {
   288	        if (assets.length == 0 || assets[assetsIndex[_tigAsset]] == address(0) || totalSupply() == 0 || !_allowedAsset[_tigAsset]) return;
   289	        try IERC20(_tigAsset).transferFrom(_msgSender(), address(this), _amount) {
   290	            accRewardsPerNFT[_tigAsset] += _amount/totalSupply();
   291	        } catch {
   292	            return;
   293	        }
   294	    }
   295	
   296	    function pending(address user, address _tigAsset) public view returns (uint256) {
   297	        return userDebt[user][_tigAsset] + balanceOf(user)*accRewardsPerNFT[_tigAsset] - userPaid[user][_tigAsset]; 
   298	    }
   299	
   300	    function addAsset(address _asset) external onlyOwner {
   301	        require(assets.length == 0 || assets[assetsIndex[_asset]] != _asset, "Already added");
   302	        assetsIndex[_asset] = assets.length;
   303	        assets.push(_asset);
   304	        _allowedAsset[_asset] = true;
   305	    }
   306	
   307	    function setAllowedAsset(address _asset, bool _bool) external onlyOwner {
   308	        _allowedAsset[_asset] = _bool;
   309	    }
   310	
   311	    function setMaxBridge(uint256 _max) external onlyOwner {
   312	        maxBridge = _max;
   313	    }
   314	
   315	    function assetsLength() public view returns (uint256) {
   316	        return assets.length;
   317	    }
   318	
   319	    function allowedAsset(address _asset) external view returns (bool) {
   320	        return _allowedAsset[_asset];
   321	    }
   322	
   323	    function balanceIds(address _user) external view returns (uint[] memory) {
   324	        uint[] memory _ids = new uint[](balanceOf(_user));
   325	        for (uint i=0; i<_ids.length; i++) {
   326	            _ids[i] = tokenOfOwnerByIndex(_user, i);
   327	        }
   328	        return _ids;
   329	    }
   330	
   331	    // META-TX
   332	    function _msgSender() internal view override(Context, MetaContext) returns (address sender) {
   333	        return MetaContext._msgSender();
   334	    }
   335	    function _msgData() internal view override(Context, MetaContext) returns (bytes calldata) {
   336	        return MetaContext._msgData();
   337	    }
   338	}