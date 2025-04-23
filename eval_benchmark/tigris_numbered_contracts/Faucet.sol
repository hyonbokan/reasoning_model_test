     1	//SPDX-License-Identifier: Unlicense
     2	pragma solidity ^0.8.0;
     3	
     4	interface IERC20 {
     5	    function mintFor(address, uint) external;
     6	}
     7	
     8	contract Faucet {
     9	
    10	    IERC20 public immutable usd;
    11	    mapping(address => bool) public used;
    12	    
    13	    constructor(address _usd) {
    14	        usd = IERC20(_usd);
    15	    }
    16	
    17	    function faucet() external {
    18	        require(!used[msg.sender], "Already used faucet");
    19	        require(msg.sender == tx.origin, "Is Contract");
    20	        usd.mintFor(msg.sender, 10000e18);
    21	        used[msg.sender] = true;
    22	    }
    23	}