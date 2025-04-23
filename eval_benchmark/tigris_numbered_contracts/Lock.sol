     1	// SPDX-License-Identifier: UNLICENSED
     2	pragma solidity ^0.8.0;
     3	
     4	import "hardhat/console.sol";
     5	import "@openzeppelin/contracts/access/Ownable.sol";
     6	import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
     7	import "./interfaces/IBondNFT.sol";
     8	import "./interfaces/IGovNFT.sol";
     9	
    10	contract Lock is Ownable{
    11	
    12	    uint public constant minPeriod = 7;
    13	    uint public constant maxPeriod = 365;
    14	
    15	    IBondNFT public immutable bondNFT;
    16	    IGovNFT public immutable govNFT;
    17	
    18	    mapping(address => bool) public allowedAssets;
    19	    mapping(address => uint) public totalLocked;
    20	
    21	    constructor(
    22	        address _bondNFTAddress,
    23	        address _govNFT
    24	    ) {
    25	        bondNFT = IBondNFT(_bondNFTAddress);
    26	        govNFT = IGovNFT(_govNFT);
    27	    }
    28	
    29	    /**
    30	     * @notice Claim pending rewards from a bond
    31	     * @param _id Bond NFT id
    32	     * @return address claimed tigAsset address
    33	     */
    34	    function claim(
    35	        uint256 _id
    36	    ) public returns (address) {
    37	        claimGovFees();
    38	        (uint _amount, address _tigAsset) = bondNFT.claim(_id, msg.sender);
    39	        IERC20(_tigAsset).transfer(msg.sender, _amount);
    40	        return _tigAsset;
    41	    }
    42	
    43	    /**
    44	     * @notice Claim pending rewards left over from a bond transfer
    45	     * @param _tigAsset token address being claimed
    46	     */
    47	    function claimDebt(
    48	        address _tigAsset
    49	    ) external {
    50	        claimGovFees();
    51	        uint amount = bondNFT.claimDebt(msg.sender, _tigAsset);
    52	        IERC20(_tigAsset).transfer(msg.sender, amount);
    53	    }
    54	
    55	    /**
    56	     * @notice Lock up tokens to create a bond
    57	     * @param _asset tigAsset being locked
    58	     * @param _amount tigAsset amount
    59	     * @param _period number of days to be locked for
    60	     */
    61	    function lock(
    62	        address _asset,
    63	        uint _amount,
    64	        uint _period
    65	    ) public {
    66	        require(_period <= maxPeriod, "MAX PERIOD");
    67	        require(_period >= minPeriod, "MIN PERIOD");
    68	        require(allowedAssets[_asset], "!asset");
    69	
    70	        claimGovFees();
    71	
    72	        IERC20(_asset).transferFrom(msg.sender, address(this), _amount);
    73	        totalLocked[_asset] += _amount;
    74	        
    75	        bondNFT.createLock( _asset, _amount, _period, msg.sender);
    76	    }
    77	
    78	    /**
    79	     * @notice Reset the lock time and extend the period and/or token amount
    80	     * @param _id Bond id being extended
    81	     * @param _amount tigAsset amount being added
    82	     * @param _period number of days being added
    83	     */
    84	    function extendLock(
    85	        uint _id,
    86	        uint _amount,
    87	        uint _period
    88	    ) public {
    89	        address _asset = claim(_id);
    90	        IERC20(_asset).transferFrom(msg.sender, address(this), _amount);
    91	        bondNFT.extendLock(_id, _asset, _amount, _period, msg.sender);
    92	    }
    93	
    94	    /**
    95	     * @notice Release the bond once it's expired
    96	     * @param _id Bond id being released
    97	     */
    98	    function release(
    99	        uint _id
   100	    ) public {
   101	        claimGovFees();
   102	        (uint amount, uint lockAmount, address asset, address _owner) = bondNFT.release(_id, msg.sender);
   103	        totalLocked[asset] -= lockAmount;
   104	        IERC20(asset).transfer(_owner, amount);
   105	    }
   106	
   107	    /**
   108	     * @notice Claim rewards from gov nfts and distribute them to bonds
   109	     */
   110	    function claimGovFees() public {
   111	        address[] memory assets = bondNFT.getAssets();
   112	
   113	        for (uint i=0; i < assets.length; i++) {
   114	            uint balanceBefore = IERC20(assets[i]).balanceOf(address(this));
   115	            IGovNFT(govNFT).claim(assets[i]);
   116	            uint balanceAfter = IERC20(assets[i]).balanceOf(address(this));
   117	            IERC20(assets[i]).approve(address(bondNFT), type(uint256).max);
   118	            bondNFT.distribute(assets[i], balanceAfter - balanceBefore);
   119	        }
   120	    }
   121	
   122	    /**
   123	     * @notice Whitelist an asset
   124	     * @param _tigAsset tigAsset token address
   125	     * @param _isAllowed set tigAsset as allowed
   126	     */
   127	    function editAsset(
   128	        address _tigAsset,
   129	        bool _isAllowed
   130	    ) external onlyOwner() {
   131	        allowedAssets[_tigAsset] = _isAllowed;
   132	    }
   133	
   134	    /**
   135	     * @notice Owner can retreive Gov NFTs
   136	     * @param _ids array of gov nft ids
   137	     */
   138	    function sendNFTs(
   139	        uint[] memory _ids
   140	    ) external onlyOwner() {
   141	        govNFT.safeTransferMany(msg.sender, _ids);
   142	    }
   143	}
