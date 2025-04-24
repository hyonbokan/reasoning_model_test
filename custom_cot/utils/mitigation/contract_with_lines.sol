     1	// File: Packs.sol
     2	// SPDX-License-Identifier: MIT
     3	pragma solidity ^0.8.29;
     4	
     5	import { NFT } from "./mock/NFT.sol";
     6	import { ERC1155URIStorage, ERC1155 } from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
     7	import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
     8	import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
     9	import { IPacks } from "./IPacks.sol";
    10	
    11	/**
    12	 * @title Packs
    13	 * @author zer0.tech
    14	 * @custom:security-contact admin@zer0.tech
    15	 * @notice ERC1155-based pack contract allowing multiple unseals per pack ID
    16	 * @dev Implements IPacks, minimal changes from your original code
    17	 */
    18	contract Packs is IPacks, ERC1155URIStorage, AccessControl {
    19	    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    20	    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    21	
    22	    error NotPackOwner(address sender, uint256 packId);
    23	    error Sealed(uint256 packId);
    24	    error Paused();
    25	    error InvalidPack(uint256 packId);
    26	    error OutOfMetadata(uint256 packId);
    27	    error ExceedsMaxMetadatas(uint256 packId, uint256 amount, uint256 numMetadatas, uint256 maxMetadatas);
    28	    error NoAvailablePacks(address user, uint256 packId);
    29	    error AlreadyUnsealedThisBlock(address user, uint256 blockNumber);
    30	    error NoneUnsealed(uint256 packId);
    31	
    32	    bool public override paused;
    33	    uint256 public override unsealDelay;
    34	    uint256 public override metadataInterval;
    35	
    36	    mapping(uint256 packId => uint256[] blocks) public unsealBlocks;
    37	    mapping(uint256 packId => uint256[] pool) public metadataPool;
    38	    mapping(address sender => uint256 block) public lastUnsealBlock;
    39	
    40	    NFT private nft1;
    41	    NFT private nft2;
    42	    NFT private nft3;
    43	
    44	    /**
    45	     * @notice Emitted when metadata is added to a pack ID
    46	     * @param packId The pack ID
    47	     * @param amount The number of new metadata entries added
    48	     */
    49	    event MetadataAdded(uint256 packId, uint256 amount);
    50	
    51	    /**
    52	     * @notice Emitted when the paused state changes
    53	     * @param toState The new paused state
    54	     */
    55	    event PausedStateChanged(bool toState);
    56	
    57	    /**
    58	     * @notice Emitted when a user unseals a single copy of a pack
    59	     * @param user The address unsealing the pack
    60	     * @param packId The pack ID
    61	     * @param atBlock The block at which unsealing happened (for logging)
    62	     */
    63	    event Unsealed(address indexed user, uint256 indexed packId, uint256 atBlock);
    64	
    65	    /**
    66	     * @notice Constructor for the Packs contract
    67	     * @dev Grants DEFAULT_ADMIN_ROLE, ADMIN_ROLE, MINTER_ROLE to msg.sender
    68	     * @param nft1_ First NFT contract
    69	     * @param nft2_ Second NFT contract
    70	     * @param nft3_ Third NFT contract
    71	     * @param unsealDelay_ Number of blocks to wait between unseal and reveal
    72	     * @param metadataInterval_ Must evenly divide a valid packId
    73	     * @param metadataURI_ Base URI for ERC1155
    74	     */
    75	    constructor(
    76	        NFT nft1_,
    77	        NFT nft2_,
    78	        NFT nft3_,
    79	        uint256 unsealDelay_,
    80	        uint256 metadataInterval_,
    81	        string memory metadataURI_
    82	    )
    83	        ERC1155(metadataURI_)
    84	    {
    85	        nft1 = nft1_;
    86	        nft2 = nft2_;
    87	        nft3 = nft3_;
    88	        unsealDelay = unsealDelay_;
    89	        metadataInterval = metadataInterval_;
    90	        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    91	        _grantRole(ADMIN_ROLE, msg.sender);
    92	        _grantRole(MINTER_ROLE, msg.sender);
    93	    }
    94	
    95	    /**
    96	     * @notice Modifier to ensure caller holds at least 1 copy of a given pack
    97	     * @param packId The pack ID
    98	     */
    99	    modifier onlyPackOwner(uint256 packId) {
   100	        if (balanceOf(msg.sender, packId) == 0) {
   101	            revert NotPackOwner(msg.sender, packId);
   102	        }
   103	        _;
   104	    }
   105	
   106	    /**
   107	     * @notice Sets the token-specific URI in ERC1155URIStorage
   108	     * @param tokenId The token ID
   109	     * @param tokenURI The new URI for that token
   110	     */
   111	    function setURI(uint256 tokenId, string memory tokenURI)
   112	        external
   113	        override
   114	        onlyRole(ADMIN_ROLE)
   115	    {
   116	        _setURI(tokenId, tokenURI);
   117	    }
   118	
   119	    /**
   120	     * @notice Sets the base URI in ERC1155URIStorage
   121	     * @param baseURI The new base URI
   122	     */
   123	    function setBaseURI(string memory baseURI)
   124	        external
   125	        override
   126	        onlyRole(ADMIN_ROLE)
   127	    {
   128	        _setBaseURI(baseURI);
   129	    }
   130	
   131	    /**
   132	     * @notice Sets the fallback/global URI in ERC1155 (the _uri)
   133	     * @param tokenURI The new fallback URI
   134	     */
   135	    function setFallbackURI(string memory tokenURI)
   136	        external
   137	        override
   138	        onlyRole(ADMIN_ROLE)
   139	    {
   140	        _setURI(tokenURI);
   141	    }
   142	
   143	    /**
   144	     * @notice Toggles the paused/unpaused state
   145	     */
   146	    function switchPaused() external override onlyRole(ADMIN_ROLE) {
   147	        paused = !paused;
   148	        emit PausedStateChanged(paused);
   149	    }
   150	
   151	    /**
   152	     * @notice Adds new metadata to a given pack ID
   153	     * @param packId The pack ID
   154	     * @param amount Number of metadata entries to add
   155	     */
   156	    function addMetadata(uint256 packId, uint256 amount)
   157	        external
   158	        override
   159	        onlyRole(ADMIN_ROLE)
   160	    {
   161	        if (packId == 0 || packId % metadataInterval != 0) {
   162	            revert InvalidPack(packId);
   163	        }
   164	        uint256 currentLen = metadataPool[packId].length;
   165	        uint256 targetLen = currentLen + amount;
   166	        if (targetLen > metadataInterval) {
   167	            revert ExceedsMaxMetadatas(packId, amount, currentLen, metadataInterval);
   168	        }
   169	        for (uint256 i = 0; i < amount; i++) {
   170	            metadataPool[packId].push(packId + currentLen + i);
   171	        }
   172	        emit MetadataAdded(packId, amount);
   173	    }
   174	
   175	    /**
   176	     * @notice Mints `amount` copies of `packId` to `to`
   177	     * @param to Recipient
   178	     * @param packId The pack ID
   179	     * @param amount Number of copies
   180	     */
   181	    function mintPack(address to, uint256 packId, uint256 amount)
   182	        external
   183	        override
   184	        onlyRole(MINTER_ROLE)
   185	    {
   186	        if (packId == 0 || packId % metadataInterval != 0) {
   187	            revert InvalidPack(packId);
   188	        }
   189	        _mint(to, packId, amount, "");
   190	    }
   191	
   192	    /**
   193	     * @notice Unseals one copy of `packId` for msg.sender
   194	     * @param packId The pack ID
   195	     */
   196	    function unseal(uint256 packId) external override onlyPackOwner(packId) {
   197	        if (paused) revert Paused();
   198	        if (packId == 0) {
   199	            revert InvalidPack(packId);
   200	        }
   201	        if (lastUnsealBlock[msg.sender] == block.number) {
   202	            revert AlreadyUnsealedThisBlock(msg.sender, block.number);
   203	        }
   204	        lastUnsealBlock[msg.sender] = block.number;
   205	        if (unsealBlocks[packId].length >= balanceOf(msg.sender, packId)) {
   206	            revert NoAvailablePacks(msg.sender, packId);
   207	        }
   208	        unsealBlocks[packId].push(block.number + unsealDelay);
   209	        emit Unsealed(msg.sender, packId, block.number);
   210	    }
   211	
   212	    /**
   213	     * @notice Reveals one unsealed copy of `packId`
   214	     * @param packId The pack ID
   215	     */
   216	    function reveal(uint256 packId) external override onlyPackOwner(packId) {
   217	        if (metadataPool[packId].length == 0) {
   218	            revert OutOfMetadata(packId);
   219	        }
   220	        if (paused) revert Paused();
   221	        if (packId == 0) {
   222	            revert InvalidPack(packId);
   223	        }
   224	        if (unsealBlocks[packId].length == 0) {
   225	            revert NoneUnsealed(packId);
   226	        }
   227	        uint256 idx = unsealBlocks[packId].length - 1;
   228	        uint256 unsealBlock = unsealBlocks[packId][idx];
   229	        unsealBlocks[packId].pop();
   230	        bytes32 bh = blockhash(unsealBlock);
   231	        if (bh == bytes32(0)) {
   232	            revert Sealed(packId);
   233	        }
   234	        uint256 index = uint256(bh) % metadataPool[packId].length;
   235	        uint256 id = metadataPool[packId][index];
   236	        metadataPool[packId][index] = metadataPool[packId][metadataPool[packId].length - 1];
   237	        metadataPool[packId].pop();
   238	        _burn(msg.sender, packId, 1);
   239	        _mint(msg.sender, 0, 1, "");
   240	        NFT(nft1).mint(msg.sender, id);
   241	        NFT(nft2).mint(msg.sender, id);
   242	        NFT(nft3).mint(msg.sender, id);
   243	    }
   244	
   245	    /**
   246	     * @notice Supports ERC1155 + AccessControl + ERC165
   247	     * @param interfaceId The interface ID
   248	     */
   249	    function supportsInterface(bytes4 interfaceId)
   250	        public
   251	        view
   252	        virtual
   253	        override(ERC1155, AccessControl)
   254	        returns (bool)
   255	    {
   256	        return super.supportsInterface(interfaceId);
   257	    }
   258	}