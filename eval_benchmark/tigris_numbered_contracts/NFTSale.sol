     1	//SPDX-License-Identifier: MIT
     2	pragma solidity ^0.8.0;
     3	
     4	import "@openzeppelin/contracts/access/Ownable.sol";
     5	
     6	interface IERC721 {
     7	    function balanceOf(address) external view returns (uint256);
     8	    function safeTransferMany(address, uint[] memory) external;
     9	    function claim(address) external;
    10	}
    11	
    12	interface IERC20 {
    13	    function balanceOf(address) external view returns (uint256);
    14	    function transfer(address, uint) external;
    15	    function transferFrom(address, address, uint) external;
    16	}
    17	
    18	contract NFTSale is Ownable {
    19	
    20	    uint public price;
    21	    IERC721 public nft;
    22	    IERC20 public token;
    23	
    24	    uint[] public availableIds;
    25	
    26	    constructor (IERC721 _nft, IERC20 _token) {
    27	        nft = _nft;
    28	        token = _token;
    29	    }
    30	
    31	
    32	    function setPrice(uint _price) external onlyOwner {
    33	        price = _price;
    34	    }
    35	
    36	    function available() external view returns (uint) {
    37	        return nft.balanceOf(address(this));
    38	    }
    39	
    40	    function buy(uint _amount) external {
    41	        require(_amount <= availableIds.length, "Not enough for sale");
    42	        uint _tokenAmount = _amount*price;
    43	        token.transferFrom(msg.sender, owner(), _tokenAmount);
    44	        uint[] memory _sold = new uint[](_amount);
    45	        for (uint i=0; i<_amount; i++) {
    46	            _sold[i] = availableIds[(availableIds.length-i) - 1];
    47	        }
    48	        for (uint i=0; i<_amount; i++) {
    49	            availableIds.pop();
    50	        }
    51	        nft.safeTransferMany(msg.sender, _sold);
    52	    }
    53	
    54	    function recovertoken() external {
    55	        token.transfer(owner(), token.balanceOf(address(this)));
    56	    }
    57	
    58	    function recoverNft() external onlyOwner {
    59	        nft.safeTransferMany(owner(), availableIds);
    60	        availableIds = new uint[](0);
    61	    }
    62	
    63	    function setIds(uint[] calldata _ids) external onlyOwner {
    64	        availableIds = _ids;
    65	    }
    66	
    67	    function claimPendingRev(address _tigAsset) external {
    68	        nft.claim(_tigAsset);
    69	        IERC20(_tigAsset).transfer(owner(), IERC20(_tigAsset).balanceOf(address(this)));
    70	    }
    71	}
