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
    12	contract GovNFTBridged is ERC721Enumerable, ILayerZeroReceiver, MetaContext, IGovNFT {
    13	    using ExcessivelySafeCall for address;
    14	
    15	    uint256 public gas = 150000;
    16	    string public baseURI;
    17	    uint256 public maxBridge = 20;
    18	    ILayerZeroEndpoint public endpoint;
    19	
    20	    mapping(uint16 => mapping(address => bool)) public isTrustedAddress;
    21	    mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) public failedMessages;
    22	    event MessageFailed(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes _payload, bytes _reason);
    23	    event RetryMessageSuccess(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes32 _payloadHash);
    24	    event ReceiveNFT(
    25	        uint16 _srcChainId,
    26	        address _from,
    27	        uint256[] _tokenId
    28	    );
    29	
    30	    constructor(
    31	        address _endpoint,
    32	        string memory _setBaseURI,
    33	        string memory _name,
    34	        string memory _symbol
    35	    ) ERC721(_name, _symbol) {
    36	        endpoint = ILayerZeroEndpoint(_endpoint);
    37	        baseURI = _setBaseURI;
    38	    }
    39	
    40	    function _baseURI() internal override view returns (string memory) {
    41	        return baseURI;
    42	    }
    43	
    44	    function setBaseURI(string calldata _newBaseURI) external onlyOwner {
    45	        baseURI = _newBaseURI;
    46	    }
    47	
    48	    function _bridgeMint(address to, uint256 tokenId) public {
    49	        require(msg.sender == address(this) || _msgSender() == owner(), "NotBridge");
    50	        require(tokenId <= 10000 && tokenId != 0, "BadID");
    51	        for (uint i=0; i<assetsLength(); i++) {
    52	            userPaid[to][assets[i]] += accRewardsPerNFT[assets[i]];
    53	        }
    54	        super._mint(to, tokenId);
    55	    }
    56	
    57	    function _burn(uint256 tokenId) internal override {
    58	        address owner = ownerOf(tokenId);
    59	        for (uint i=0; i<assetsLength(); i++) {
    60	            userDebt[owner][assets[i]] += accRewardsPerNFT[assets[i]];
    61	            userDebt[owner][assets[i]] -= userPaid[owner][assets[i]]/balanceOf(owner);
    62	            userPaid[owner][assets[i]] -= userPaid[owner][assets[i]]/balanceOf(owner);            
    63	        }
    64	        super._burn(tokenId);
    65	    }
    66	
    67	    function _transfer(
    68	        address from,
    69	        address to,
    70	        uint256 tokenId
    71	    ) internal override {
    72	        require(ownerOf(tokenId) == from, "!Owner");
    73	        for (uint i=0; i<assetsLength(); i++) {
    74	            userDebt[from][assets[i]] += accRewardsPerNFT[assets[i]];
    75	            userDebt[from][assets[i]] -= userPaid[from][assets[i]]/balanceOf(from);
    76	            userPaid[from][assets[i]] -= userPaid[from][assets[i]]/balanceOf(from);
    77	            userPaid[to][assets[i]] += accRewardsPerNFT[assets[i]];
    78	        }
    79	        super._transfer(from, to, tokenId);
    80	    }
    81	
    82	    function setTrustedAddress(uint16 _chainId, address _contract, bool _bool) external onlyOwner {
    83	        isTrustedAddress[_chainId][_contract] = _bool;
    84	    }
    85	
    86	    function crossChain(
    87	        uint16 _dstChainId,
    88	        bytes memory _destination,
    89	        address _to,
    90	        uint256[] memory tokenId
    91	    ) public payable {
    92	        require(tokenId.length > 0, "Not bridging");
    93	        for (uint i=0; i<tokenId.length; i++) {
    94	            require(_msgSender() == ownerOf(tokenId[i]), "Not the owner");
    95	            // burn NFT
    96	            _burn(tokenId[i]);
    97	        }
    98	        address targetAddress;
    99	        assembly {
   100	            targetAddress := mload(add(_destination, 20))
   101	        }
   102	        require(isTrustedAddress[_dstChainId][targetAddress], "!Trusted");
   103	        bytes memory payload = abi.encode(_to, tokenId);
   104	        // encode adapterParams to specify more gas for the destination
   105	        uint16 version = 1;
   106	        uint256 _gas = 500_000 + gas*tokenId.length;
   107	        bytes memory adapterParams = abi.encodePacked(version, _gas);
   108	        (uint256 messageFee, ) = endpoint.estimateFees(
   109	            _dstChainId,
   110	            address(this),
   111	            payload,
   112	            false,
   113	            adapterParams
   114	        );
   115	        require(
   116	            msg.value >= messageFee,
   117	            "Must send enough value to cover messageFee"
   118	        );
   119	        endpoint.send{value: msg.value}(
   120	            _dstChainId,
   121	            _destination,
   122	            payload,
   123	            payable(_msgSender()),
   124	            address(0x0),
   125	            adapterParams
   126	        );
   127	    }
   128	    function lzReceive(
   129	        uint16 _srcChainId,
   130	        bytes memory _srcAddress,
   131	        uint64 _nonce,
   132	        bytes memory _payload
   133	    ) external override {
   134	        require(_msgSender() == address(endpoint), "!Endpoint");
   135	        (bool success, bytes memory reason) = address(this).excessivelySafeCall(gasleft()*4/5, 150, abi.encodeWithSelector(this.nonblockingLzReceive.selector, _srcChainId, _srcAddress, _nonce, _payload));
   136	        // try-catch all errors/exceptions
   137	        if (!success) {
   138	            failedMessages[_srcChainId][_srcAddress][_nonce] = keccak256(_payload);
   139	            emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload, reason);
   140	        }
   141	    }
   142	
   143	    function nonblockingLzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) public {
   144	        // only internal transaction
   145	        require(msg.sender == address(this), "NonblockingLzApp: caller must be app");
   146	        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
   147	    }
   148	
   149	    function _nonblockingLzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64, bytes memory _payload) internal {
   150	        address fromAddress;
   151	        assembly {
   152	            fromAddress := mload(add(_srcAddress, 20))
   153	        }
   154	        require(isTrustedAddress[_srcChainId][fromAddress], "!TrustedAddress");
   155	        (address toAddress, uint256[] memory tokenId) = abi.decode(
   156	            _payload,
   157	            (address, uint256[])
   158	        );
   159	        // mint the tokens
   160	        for (uint i=0; i<tokenId.length; i++) {
   161	            _bridgeMint(toAddress, tokenId[i]);
   162	        }
   163	        emit ReceiveNFT(_srcChainId, toAddress, tokenId);
   164	    }
   165	
   166	    function retryMessage(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) public {
   167	        // assert there is message to retry
   168	        bytes32 payloadHash = failedMessages[_srcChainId][_srcAddress][_nonce];
   169	        require(payloadHash != bytes32(0), "NonblockingLzApp: no stored message");
   170	        require(keccak256(_payload) == payloadHash, "NonblockingLzApp: invalid payload");
   171	        // clear the stored message
   172	        failedMessages[_srcChainId][_srcAddress][_nonce] = bytes32(0);
   173	        // execute the message. revert if it fails again
   174	        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
   175	        emit RetryMessageSuccess(_srcChainId, _srcAddress, _nonce, payloadHash);
   176	    }
   177	
   178	    // Endpoint.sol estimateFees() returns the fees for the message
   179	    function estimateFees(
   180	        uint16 _dstChainId,
   181	        address _userApplication,
   182	        bytes calldata _payload,
   183	        bool _payInZRO,
   184	        bytes calldata _adapterParams
   185	    ) external view returns (uint256 nativeFee, uint256 zroFee) {
   186	        return
   187	            endpoint.estimateFees(
   188	                _dstChainId,
   189	                _userApplication,
   190	                _payload,
   191	                _payInZRO,
   192	                _adapterParams
   193	            );
   194	    }
   195	
   196	    function setGas(uint _gas) external onlyOwner {
   197	        gas = _gas;
   198	    }
   199	
   200	    function setEndpoint(ILayerZeroEndpoint _endpoint) external onlyOwner {
   201	        require(address(_endpoint) != address(0), "ZeroAddress");
   202	        endpoint = _endpoint;
   203	    }
   204	
   205	    function safeTransferMany(address _to, uint[] calldata _ids) external {
   206	        for (uint i=0; i<_ids.length; i++) {
   207	            _transfer(_msgSender(), _to, _ids[i]);
   208	        }
   209	    }
   210	
   211	    function safeTransferFromMany(address _from, address _to, uint[] calldata _ids) external {
   212	        for (uint i=0; i<_ids.length; i++) {
   213	            safeTransferFrom(_from, _to, _ids[i]);
   214	        }
   215	    }
   216	
   217	    function approveMany(address _to, uint[] calldata _ids) external {
   218	        for (uint i=0; i<_ids.length; i++) {
   219	            approve(_to, _ids[i]);
   220	        }
   221	    }
   222	
   223	    // Rewards
   224	    address[] public assets;
   225	    mapping(address => bool) private _allowedAsset;
   226	    mapping(address => uint) private assetsIndex;
   227	    mapping(address => mapping(address => uint256)) private userPaid;
   228	    mapping(address => mapping(address => uint256)) private userDebt;
   229	    mapping(address => uint256) private accRewardsPerNFT;
   230	
   231	    function claim(address _tigAsset) external {
   232	        address _msgsender = _msgSender();
   233	        uint256 amount = pending(_msgsender, _tigAsset);
   234	        userPaid[_msgsender][_tigAsset] += amount;
   235	        IERC20(_tigAsset).transfer(_msgsender, amount);
   236	    }
   237	
   238	    function distribute(address _tigAsset, uint _amount) external {
   239	        if (assets.length == 0 || assets[assetsIndex[_tigAsset]] == address(0) || totalSupply() == 0 || !_allowedAsset[_tigAsset]) return;
   240	        try IERC20(_tigAsset).transferFrom(_msgSender(), address(this), _amount) {
   241	            accRewardsPerNFT[_tigAsset] += _amount/totalSupply();
   242	        } catch {
   243	            return;
   244	        }
   245	    }
   246	
   247	    function pending(address user, address _tigAsset) public view returns (uint256) {
   248	        return userDebt[user][_tigAsset] + balanceOf(user)*accRewardsPerNFT[_tigAsset] - userPaid[user][_tigAsset]; 
   249	    }
   250	
   251	    function addAsset(address _asset) external onlyOwner {
   252	        require(assets.length == 0 || assets[assetsIndex[_asset]] != _asset, "Already added");
   253	        assetsIndex[_asset] = assets.length;
   254	        assets.push(_asset);
   255	        _allowedAsset[_asset] = true;
   256	    }
   257	
   258	    function setAllowedAsset(address _asset, bool _bool) external onlyOwner {
   259	        _allowedAsset[_asset] = _bool;
   260	    }
   261	
   262	    function setMaxBridge(uint256 _max) external onlyOwner {
   263	        maxBridge = _max;
   264	    }
   265	
   266	    function assetsLength() public view returns (uint256) {
   267	        return assets.length;
   268	    }
   269	
   270	    function allowedAsset(address _asset) external view returns (bool) {
   271	        return _allowedAsset[_asset];
   272	    }
   273	
   274	    function balanceIds(address _user) external view returns (uint[] memory) {
   275	        uint[] memory _ids = new uint[](balanceOf(_user));
   276	        for (uint i=0; i<_ids.length; i++) {
   277	            _ids[i] = tokenOfOwnerByIndex(_user, i);
   278	        }
   279	        return _ids;
   280	    }
   281	
   282	    // META-TX
   283	    function _msgSender() internal view override(Context, MetaContext) returns (address sender) {
   284	        return MetaContext._msgSender();
   285	    }
   286	    function _msgData() internal view override(Context, MetaContext) returns (bytes calldata) {
   287	        return MetaContext._msgData();
   288	    }
   289	}