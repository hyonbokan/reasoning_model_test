     1	//SPDX-License-Identifier: MIT
     2	pragma solidity ^0.8.0;
     3	
     4	import "@openzeppelin/contracts/governance/TimelockController.sol";
     5	
     6	contract Timelock is TimelockController {
     7	    constructor(address[] memory _proposers, address[] memory _executors, uint256 _time) TimelockController(_time, _proposers, _executors, address(0)) {}
     8	}
