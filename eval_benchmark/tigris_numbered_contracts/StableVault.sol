     1	// SPDX-License-Identifier: MIT
     2	pragma solidity ^0.8.0;
     3	
     4	import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
     5	import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
     6	import "./utils/MetaContext.sol";
     7	import "./interfaces/IStableVault.sol";
     8	
     9	interface IERC20Mintable is IERC20 {
    10	    function mintFor(address, uint256) external;
    11	    function burnFrom(address, uint256) external;
    12	    function decimals() external view returns (uint);
    13	}
    14	
    15	interface ERC20Permit is IERC20 {
    16	    function permit(
    17	        address owner,
    18	        address spender,
    19	        uint256 value,
    20	        uint256 deadline,
    21	        uint8 v,
    22	        bytes32 r,
    23	        bytes32 s
    24	    ) external;
    25	}
    26	
    27	contract StableVault is MetaContext, IStableVault {
    28	
    29	    mapping(address => bool) public allowed;
    30	    mapping(address => uint) private tokenIndex;
    31	    address[] public tokens;
    32	
    33	    address public immutable stable;
    34	
    35	    constructor(address _stable) {
    36	        stable = _stable;
    37	    }
    38	
    39	    /**
    40	    * @notice deposit an allowed token and receive tigAsset
    41	    * @param _token address of the allowed token
    42	    * @param _amount amount of _token
    43	    */
    44	    function deposit(address _token, uint256 _amount) public {
    45	        require(allowed[_token], "Token not listed");
    46	        IERC20(_token).transferFrom(_msgSender(), address(this), _amount);
    47	        IERC20Mintable(stable).mintFor(
    48	            _msgSender(),
    49	            _amount*(10**(18-IERC20Mintable(_token).decimals()))
    50	        );
    51	    }
    52	
    53	    function depositWithPermit(address _token, uint256 _amount, uint256 _deadline, bool _permitMax, uint8 v, bytes32 r, bytes32 s) external {
    54	        uint _toAllow = _amount;
    55	        if (_permitMax) _toAllow = type(uint).max;
    56	        ERC20Permit(_token).permit(_msgSender(), address(this), _toAllow, _deadline, v, r, s);
    57	        deposit(_token, _amount);
    58	    }
    59	
    60	    /**
    61	    * @notice swap tigAsset to _token
    62	    * @param _token address of the token to receive
    63	    * @param _amount amount of _token
    64	    */
    65	    function withdraw(address _token, uint256 _amount) external returns (uint256 _output) {
    66	        IERC20Mintable(stable).burnFrom(_msgSender(), _amount);
    67	        _output = _amount/10**(18-IERC20Mintable(_token).decimals());
    68	        IERC20(_token).transfer(
    69	            _msgSender(),
    70	            _output
    71	        );
    72	    }
    73	
    74	    /**
    75	    * @notice allow a token to be used in vault
    76	    * @param _token address of the token
    77	    */
    78	    function listToken(address _token) external onlyOwner {
    79	        require(!allowed[_token], "Already added");
    80	        tokenIndex[_token] = tokens.length;
    81	        tokens.push(_token);
    82	        allowed[_token] = true;
    83	    }
    84	
    85	    /**
    86	    * @notice stop a token from being allowed in vault
    87	    * @param _token address of the token
    88	    */
    89	    function delistToken(address _token) external onlyOwner {
    90	        require(allowed[_token], "Not added");
    91	        tokenIndex[tokens[tokens.length-1]] = tokenIndex[_token];
    92	        tokens[tokenIndex[_token]] = tokens[tokens.length-1];
    93	        delete tokenIndex[_token];
    94	        tokens.pop();
    95	        allowed[_token] = false;
    96	    }
    97	}