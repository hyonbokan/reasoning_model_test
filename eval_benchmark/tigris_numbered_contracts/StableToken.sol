     1	// SPDX-License-Identifier: MIT
     2	pragma solidity ^0.8.0;
     3	
     4	import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
     5	import "./utils/MetaContext.sol";
     6	
     7	contract StableToken is ERC20Permit, MetaContext {
     8	
     9	    mapping(address => bool) public isMinter;
    10	
    11	    constructor(string memory name_, string memory symbol_) ERC20Permit(name_) ERC20(name_, symbol_) {}
    12	
    13	    function burnFrom(
    14	        address account,
    15	        uint256 amount
    16	    ) 
    17	        public 
    18	        virtual 
    19	        onlyMinter() 
    20	    {
    21	        _burn(account, amount);
    22	    }
    23	
    24	    function mintFor(
    25	        address account,
    26	        uint256 amount
    27	    ) 
    28	        public 
    29	        virtual 
    30	        onlyMinter() 
    31	    {  
    32	        _mint(account, amount);
    33	    }
    34	
    35	    /**
    36	     * @dev Sets the status of minter.
    37	     */
    38	    function setMinter(
    39	        address _address,
    40	        bool _status
    41	    ) 
    42	        public
    43	        onlyOwner()
    44	    {
    45	        isMinter[_address] = _status;
    46	    }
    47	
    48	    /**
    49	     * @dev Throws if called by any account that is not minter.
    50	     */
    51	    modifier onlyMinter() {
    52	        require(isMinter[_msgSender()], "!Minter");
    53	        _;
    54	    }
    55	
    56	    // META-TX
    57	    function _msgSender() internal view override(Context, MetaContext) returns (address sender) {
    58	        return MetaContext._msgSender();
    59	    }
    60	
    61	    // Unreachable
    62	    function _msgData() internal view override(Context, MetaContext) returns (bytes calldata) {
    63	        return MetaContext._msgData();
    64	    }
    65	}