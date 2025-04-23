     1	//SPDX-License-Identifier: Unlicense
     2	pragma solidity ^0.8.0;
     3	
     4	import "@openzeppelin/contracts/access/Ownable.sol";
     5	import "./interfaces/IReferrals.sol";
     6	
     7	contract Referrals is Ownable, IReferrals {
     8	
     9	    bool private isInit;
    10	
    11	    address public protocol;
    12	
    13	    mapping(bytes32 => address) private _referral;
    14	    mapping(address => bytes32) private _referred;
    15	
    16	    /**
    17	    * @notice used by any address to create a ref code
    18	    * @param _hash hash of the string code
    19	    */
    20	    function createReferralCode(bytes32 _hash) external {
    21	        require(_referral[_hash] == address(0), "Referral code already exists");
    22	        _referral[_hash] = _msgSender();
    23	        emit ReferralCreated(_msgSender(), _hash);
    24	    }
    25	
    26	    /**
    27	    * @notice set the ref data
    28	    * @dev only callable by trading
    29	    * @param _referredTrader address of the trader
    30	    * @param _hash ref hash
    31	    */
    32	    function setReferred(address _referredTrader, bytes32 _hash) external onlyProtocol {
    33	        if (_referred[_referredTrader] != bytes32(0)) {
    34	            return;
    35	        }
    36	        if (_referredTrader == _referral[_hash]) {
    37	            return;
    38	        }
    39	        _referred[_referredTrader] = _hash;
    40	        emit Referred(_referredTrader, _hash);
    41	    }
    42	
    43	    function getReferred(address _trader) external view returns (bytes32) {
    44	        return _referred[_trader];
    45	    }
    46	
    47	    function getReferral(bytes32 _hash) external view returns (address) {
    48	        return _referral[_hash];
    49	    }
    50	
    51	    // Owner
    52	
    53	    function setProtocol(address _protocol) external onlyOwner {
    54	        protocol = _protocol;
    55	    }
    56	
    57	    /**
    58	    * @notice deprecated
    59	    */
    60	    function initRefs(
    61	        address[] memory _codeOwners,
    62	        bytes32[] memory _ownedCodes,
    63	        address[] memory _referredA,
    64	        bytes32[] memory _referredTo
    65	    ) external onlyOwner {
    66	        require(!isInit);
    67	        isInit = true;
    68	        uint _codeOwnersL = _codeOwners.length;
    69	        uint _referredAL = _referredA.length;
    70	        for (uint i=0; i<_codeOwnersL; i++) {
    71	            _referral[_ownedCodes[i]] = _codeOwners[i];
    72	        }
    73	        for (uint i=0; i<_referredAL; i++) {
    74	            _referred[_referredA[i]] = _referredTo[i];
    75	        }
    76	    }
    77	
    78	    // Modifiers
    79	
    80	    modifier onlyProtocol() {
    81	        require(_msgSender() == address(protocol), "!Protocol");
    82	        _;
    83	    }
    84	
    85	    event ReferralCreated(address _referrer, bytes32 _hash);
    86	    event Referred(address _referredTrader, bytes32 _hash);
    87	
    88	}