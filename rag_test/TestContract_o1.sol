// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*//////////////////////////////////////////////////////////////
                          OWNABLE
//////////////////////////////////////////////////////////////*/
contract Ownable {
    address public owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not owner");
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

/*//////////////////////////////////////////////////////////////
                          IERC20
//////////////////////////////////////////////////////////////*/
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/*//////////////////////////////////////////////////////////////
                      LAYER ZERO INTERFACES
//////////////////////////////////////////////////////////////*/
interface ILayerZeroReceiver {
    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) external;
}

interface ILayerZeroEndpoint {
    function send(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes calldata adapterParams
    ) external payable;

    function estimateFees(
        uint16 _dstChainId,
        address _userApplication,
        bytes calldata _payload,
        bool _payInZRO,
        bytes calldata _adapterParams
    ) external view returns (uint256 nativeFee, uint256 zroFee);
}

/*//////////////////////////////////////////////////////////////
                       EXCESSIVELY SAFE CALL
                 (adapted from LayerZero examples)
//////////////////////////////////////////////////////////////*/
library ExcessivelySafeCall {
    function excessivelySafeCall(
        address target,
        uint256 gas,
        uint16 maxCopy,
        bytes memory callData
    )
        internal
        returns (bool success, bytes memory returnData)
    {
        // limit the call gas
        // use assembly to call arbitrary contract
        assembly {
            let freeMemPtr := mload(0x40)
            success := call(
                gas,            // gas
                target,         // to
                0,              // value
                add(callData, 0x20), // in
                mload(callData),     // insize
                0,              // out
                0               // outsize
            )
            let rsz := returndatasize()
            if gt(rsz, maxCopy) {
                rsz := maxCopy
            }
            mstore(freeMemPtr, rsz)
            returndatacopy(add(freeMemPtr, 0x20), 0, rsz)
            returnData := freeMemPtr
            mstore(0x40, add(freeMemPtr, add(rsz, 0x40)))
        }
    }
}

/*//////////////////////////////////////////////////////////////
                          META CONTEXT
    (Minimal override that replicates _msgSender / _msgData)
//////////////////////////////////////////////////////////////*/
contract MetaContext {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/*//////////////////////////////////////////////////////////////
                           IGovNFT
    (Empty or partial interface; add methods if truly needed)
//////////////////////////////////////////////////////////////*/
interface IGovNFT {
    // Add function signatures if needed. Currently empty for demonstration.
}

/*//////////////////////////////////////////////////////////////
                    MINIMAL ERC721 + ENUMERABLE
//////////////////////////////////////////////////////////////*/
contract ERC721Enumerable is MetaContext {
    // ERC165
    mapping(bytes4 => bool) internal _supportedInterfaces;

    // ERC721
    mapping(uint256 => address) internal _owners;
    mapping(address => uint256) internal _balances;
    mapping(uint256 => address) internal _tokenApprovals;
    mapping(address => mapping(address => bool)) internal _operatorApprovals;

    // ERC721Enumerable
    uint256[] internal _allTokens;
    mapping(uint256 => uint256) internal _allTokensIndex;
    mapping(address => uint256[]) internal _ownedTokens;
    mapping(uint256 => uint256) internal _ownedTokensIndex;

    string private _name;
    string private _symbol;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;

        // register ERC165 interfaces
        _supportedInterfaces[0x80ac58cd] = true; // ERC721
        _supportedInterfaces[0x780e9d63] = true; // ERC721Enumerable
        _supportedInterfaces[0x01ffc9a7] = true; // ERC165
    }

    /*//////////////////////////////////////////////////////////////
                        ERC165
    //////////////////////////////////////////////////////////////*/
    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return _supportedInterfaces[interfaceId];
    }

    /*//////////////////////////////////////////////////////////////
                        ERC721 VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function balanceOf(address owner) public view returns (uint256) {
        require(owner != address(0), "balance query for the zero address");
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address theOwner = _owners[tokenId];
        require(theOwner != address(0), "owner query for nonexistent token");
        return theOwner;
    }

    function totalSupply() public view returns (uint256) {
        return _allTokens.length;
    }

    function tokenByIndex(uint256 index) public view returns (uint256) {
        require(index < _allTokens.length, "global index out of bounds");
        return _allTokens[index];
    }

    function tokenOfOwnerByIndex(address owner, uint256 index) public view returns (uint256) {
        require(index < _ownedTokens[owner].length, "owner index out of bounds");
        return _ownedTokens[owner][index];
    }

    /*//////////////////////////////////////////////////////////////
                          ERC721 TRANSFERS
    //////////////////////////////////////////////////////////////*/
    function approve(address to, uint256 tokenId) public {
        address owner_ = ownerOf(tokenId);
        require(to != owner_, "approval to current owner");
        require(
            _msgSender() == owner_ || isApprovedForAll(owner_, _msgSender()),
            "approve caller is not owner nor approved for all"
        );
        _tokenApprovals[tokenId] = to;
        emit Approval(owner_, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        require(_exists(tokenId), "approved query for nonexistent token");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public {
        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    function isApprovedForAll(address owner_, address operator) public view returns (bool) {
        return _operatorApprovals[owner_][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public virtual {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "transfer caller is not owner nor approved");
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual {
        transferFrom(from, to, tokenId);
        require(_checkOnERC721Received(), "ERC721: transfer to non ERC721Receiver implementer");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory) public virtual {
        safeTransferFrom(from, to, tokenId);
    }

    // Dummy check for ERC721Receiver in a minimal example (always returns true)
    function _checkOnERC721Received() internal pure returns (bool) {
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner_ = ownerOf(tokenId);
        return (spender == owner_ ||
            getApproved(tokenId) == spender ||
            isApprovedForAll(owner_, spender));
    }

    function _mint(address to, uint256 tokenId) internal virtual {
        require(to != address(0), "mint to the zero address");
        require(!_exists(tokenId), "token already minted");

        _balances[to] += 1;
        _owners[tokenId] = to;

        _addTokenToOwnerEnumeration(to, tokenId);
        _addTokenToAllTokensEnumeration(tokenId);

        emit Transfer(address(0), to, tokenId);
    }

    function _burn(uint256 tokenId) internal virtual {
        address owner_ = ownerOf(tokenId);

        // Clear approvals
        delete _tokenApprovals[tokenId];

        _balances[owner_] -= 1;
        delete _owners[tokenId];

        _removeTokenFromOwnerEnumeration(owner_, tokenId);
        _removeTokenFromAllTokensEnumeration(tokenId);

        emit Transfer(owner_, address(0), tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) internal virtual {
        require(ownerOf(tokenId) == from, "transfer of token that is not own");
        require(to != address(0), "transfer to the zero address");

        // Clear approvals from the previous owner
        delete _tokenApprovals[tokenId];

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        _removeTokenFromOwnerEnumeration(from, tokenId);
        _addTokenToOwnerEnumeration(to, tokenId);

        emit Transfer(from, to, tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                        ENUMERABLE HELPERS
    //////////////////////////////////////////////////////////////*/
    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId];

        // when the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _allTokens[lastTokenIndex];
            _allTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _allTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        _allTokens.pop();
        delete _allTokensIndex[tokenId];
    }

    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        _ownedTokensIndex[tokenId] = _ownedTokens[to].length;
        _ownedTokens[to].push(tokenId);
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        uint256 lastTokenIndex = _ownedTokens[from].length - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];
            _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        _ownedTokens[from].pop();
        delete _ownedTokensIndex[tokenId];
    }

    /*//////////////////////////////////////////////////////////////
                         HOOKS / OVERRIDES
    //////////////////////////////////////////////////////////////*/
    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }
}

/*//////////////////////////////////////////////////////////////
                          GOVNFT
    (Combines bridging, rewards, etc.)
//////////////////////////////////////////////////////////////*/
contract GovNFT is
    ERC721Enumerable,
    ILayerZeroReceiver,
    MetaContext,
    IGovNFT,
    Ownable
{
    using ExcessivelySafeCall for address;

    // Basic GovNFT config
    uint256 private counter = 1;
    uint256 private constant MAX = 10000;
    uint256 public gas = 150000;
    string public baseURI;
    uint256 public maxBridge = 20;

    ILayerZeroEndpoint public endpoint;

    mapping(uint16 => mapping(address => bool)) public isTrustedAddress;
    mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) public failedMessages;

    event MessageFailed(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes _payload, bytes _reason);
    event RetryMessageSuccess(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes32 _payloadHash);
    event ReceiveNFT(uint16 _srcChainId, address _from, uint256[] _tokenId);

    // Rewards Storage
    address[] public assets;                  // reward token addresses
    mapping(address => bool) private _allowedAsset;
    mapping(address => uint) private assetsIndex;
    mapping(address => mapping(address => uint256)) private userPaid; // userPaid[user][token]
    mapping(address => mapping(address => uint256)) private userDebt; // userDebt[user][token]
    mapping(address => uint256) private accRewardsPerNFT; // accumulative reward per NFT

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address _endpoint,
        string memory _setBaseURI,
        string memory _name,
        string memory _symbol
    ) ERC721Enumerable(_name, _symbol) {
        endpoint = ILayerZeroEndpoint(_endpoint);
        baseURI = _setBaseURI;
    }

    /*//////////////////////////////////////////////////////////////
                           BASE URI OVERRIDE
    //////////////////////////////////////////////////////////////*/
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string calldata _newBaseURI) external onlyOwner {
        baseURI = _newBaseURI;
    }

    /*//////////////////////////////////////////////////////////////
                        OVERRIDDEN _MINT
    ////////////////////////////////////////////////////////////////*/
    function _mint(address to, uint256 tokenId) internal override {
        require(counter <= MAX, "Exceeds supply");
        counter += 1;
        // apply reward logic
        for (uint i=0; i<assetsLength(); i++) {
            userPaid[to][assets[i]] += accRewardsPerNFT[assets[i]];
        }
        // then do the real mint
        super._mint(to, tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                    BRIDGE MINT (only internal or owner)
    ////////////////////////////////////////////////////////////////*/
    function _bridgeMint(address to, uint256 tokenId) public {
        require(msg.sender == address(this) || _msgSender() == owner, "NotBridge");
        require(tokenId <= 10000, "BadID");
        for (uint i=0; i<assetsLength(); i++) {
            userPaid[to][assets[i]] += accRewardsPerNFT[assets[i]];
        }
        super._mint(to, tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                          OVERRIDDEN _BURN
    ////////////////////////////////////////////////////////////////*/
    function _burn(uint256 tokenId) internal override {
        address owner_ = ownerOf(tokenId);
        // update reward logic
        for (uint i=0; i<assetsLength(); i++) {
            userDebt[owner_][assets[i]] += accRewardsPerNFT[assets[i]];
            // if user has X NFTs, remove fraction from userPaid
            // simple approach: userPaid[owner]/balanceOf(owner)
            uint256 bal = balanceOf(owner_);
            if (bal > 0) {
                userDebt[owner_][assets[i]] -= userPaid[owner_][assets[i]] / bal;
                userPaid[owner_][assets[i]] -= userPaid[owner_][assets[i]] / bal;
            }
        }
        super._burn(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                      OVERRIDDEN _TRANSFER
    ////////////////////////////////////////////////////////////////*/
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        require(ownerOf(tokenId) == from, "!Owner");
        // update reward logic for from + to
        for (uint i=0; i<assetsLength(); i++) {
            userDebt[from][assets[i]] += accRewardsPerNFT[assets[i]];
            uint256 balFrom = balanceOf(from);
            if (balFrom > 0) {
                userDebt[from][assets[i]] -= userPaid[from][assets[i]] / balFrom;
                userPaid[from][assets[i]] -= userPaid[from][assets[i]] / balFrom;
            }
            userPaid[to][assets[i]] += accRewardsPerNFT[assets[i]];
        }
        super._transfer(from, to, tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                       OWNER MINTING
    ////////////////////////////////////////////////////////////////*/
    function mintMany(uint _amount) external onlyOwner {
        for (uint i=0; i<_amount; i++) {
            _mint(_msgSender(), counter);
        }
    }

    function mint() external onlyOwner {
        _mint(_msgSender(), counter);
    }

    /*//////////////////////////////////////////////////////////////
                     TRUSTED ADDRESSES
    ////////////////////////////////////////////////////////////////*/
    function setTrustedAddress(uint16 _chainId, address _contract, bool _bool) external onlyOwner {
        isTrustedAddress[_chainId][_contract] = _bool;
    }

    /*//////////////////////////////////////////////////////////////
                      CROSS-CHAIN BRIDGE
    ////////////////////////////////////////////////////////////////*/
    function crossChain(
        uint16 _dstChainId,
        bytes memory _destination,
        address _to,
        uint256[] memory tokenId
    ) public payable {
        require(tokenId.length > 0, "Not bridging");
        for (uint i=0; i<tokenId.length; i++) {
            require(_msgSender() == ownerOf(tokenId[i]), "Not the owner");
            // burn NFT
            _burn(tokenId[i]);
        }
        address targetAddress;
        assembly {
            targetAddress := mload(add(_destination, 20))
        }
        require(isTrustedAddress[_dstChainId][targetAddress], "!Trusted");
        bytes memory payload = abi.encode(_to, tokenId);

        // adapter params
        uint16 version = 1;
        uint256 _gas = 500_000 + gas * tokenId.length;
        bytes memory adapterParams = abi.encodePacked(version, _gas);

        (uint256 messageFee, ) = endpoint.estimateFees(
            _dstChainId,
            address(this),
            payload,
            false,
            adapterParams
        );
        require(msg.value >= messageFee, "Not enough messageFee");

        endpoint.send{value: msg.value}(
            _dstChainId,
            _destination,
            payload,
            payable(_msgSender()),
            address(0),
            adapterParams
        );
    }

    /*//////////////////////////////////////////////////////////////
                      LAYER ZERO RECEIVER
    ////////////////////////////////////////////////////////////////*/
    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) external override {
        require(_msgSender() == address(endpoint), "!Endpoint");
        (bool success, bytes memory reason) = address(this).excessivelySafeCall(
            gasleft() * 4 / 5,
            150,
            abi.encodeWithSelector(
                this.nonblockingLzReceive.selector,
                _srcChainId,
                _srcAddress,
                _nonce,
                _payload
            )
        );
        if (!success) {
            failedMessages[_srcChainId][_srcAddress][_nonce] = keccak256(_payload);
            emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload, reason);
        }
    }

    function nonblockingLzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) public {
        require(msg.sender == address(this), "NonblockingLzApp: caller must be app");
        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64,
        bytes memory _payload
    ) internal {
        address fromAddress;
        assembly {
            fromAddress := mload(add(_srcAddress, 20))
        }
        require(isTrustedAddress[_srcChainId][fromAddress], "!TrustedAddress");
        (address toAddress, uint256[] memory tokenId) = abi.decode(_payload, (address, uint256[]));
        for (uint i=0; i<tokenId.length; i++) {
            _bridgeMint(toAddress, tokenId[i]);
        }
        emit ReceiveNFT(_srcChainId, toAddress, tokenId);
    }

    function retryMessage(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) public {
        bytes32 payloadHash = failedMessages[_srcChainId][_srcAddress][_nonce];
        require(payloadHash != bytes32(0), "No stored message");
        require(keccak256(_payload) == payloadHash, "Invalid payload");
        failedMessages[_srcChainId][_srcAddress][_nonce] = bytes32(0);
        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
        emit RetryMessageSuccess(_srcChainId, _srcAddress, _nonce, payloadHash);
    }

    function estimateFees(
        uint16 _dstChainId,
        address _userApplication,
        bytes calldata _payload,
        bool _payInZRO,
        bytes calldata _adapterParams
    ) external view returns (uint256 nativeFee, uint256 zroFee) {
        return endpoint.estimateFees(
            _dstChainId,
            _userApplication,
            _payload,
            _payInZRO,
            _adapterParams
        );
    }

    /*//////////////////////////////////////////////////////////////
                 SETTERS (OWNER-ONLY) FOR GAS/ENDPOINT
    ////////////////////////////////////////////////////////////////*/
    function setGas(uint _gas) external onlyOwner {
        gas = _gas;
    }

    function setEndpoint(ILayerZeroEndpoint _endpoint) external onlyOwner {
        require(address(_endpoint) != address(0), "ZeroAddress");
        endpoint = _endpoint;
    }

    function setMaxBridge(uint256 _max) external onlyOwner {
        maxBridge = _max;
    }

    /*//////////////////////////////////////////////////////////////
                 BATCH OPERATIONS FOR TRANSFERS
    ////////////////////////////////////////////////////////////////*/
    function safeTransferMany(address _to, uint[] calldata _ids) external {
        for (uint i=0; i<_ids.length; i++) {
            _transfer(_msgSender(), _to, _ids[i]);
        }
    }

    function safeTransferFromMany(address _from, address _to, uint[] calldata _ids) external {
        for (uint i=0; i<_ids.length; i++) {
            safeTransferFrom(_from, _to, _ids[i]);
        }
    }

    function approveMany(address _to, uint[] calldata _ids) external {
        for (uint i=0; i<_ids.length; i++) {
            approve(_to, _ids[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        REWARD FUNCTIONS
    ////////////////////////////////////////////////////////////////*/
    /**
    * @notice Claim any pending rewards in `_tigAsset`.
    */
    function claim(address _tigAsset) external {
        address sender = _msgSender();
        uint256 amount = pending(sender, _tigAsset);
        userPaid[sender][_tigAsset] += amount;
        IERC20(_tigAsset).transfer(sender, amount);
    }

    /**
    * @notice Add `_amount` of reward tokens for distribution to all NFT holders.
    */
    function distribute(address _tigAsset, uint _amount) external {
        if (
            assets.length == 0 ||
            assets[assetsIndex[_tigAsset]] == address(0) ||
            totalSupply() == 0 ||
            !_allowedAsset[_tigAsset]
        ) {
            return;
        }
        try IERC20(_tigAsset).transferFrom(_msgSender(), address(this), _amount) {
            accRewardsPerNFT[_tigAsset] += _amount / totalSupply();
        } catch {
            // if transfer fails, do nothing
            return;
        }
    }

    /**
    * @notice View how many tokens are claimable for `user`.
    */
    function pending(address user, address _tigAsset) public view returns (uint256) {
        return userDebt[user][_tigAsset] + balanceOf(user)*accRewardsPerNFT[_tigAsset] - userPaid[user][_tigAsset];
    }

    function addAsset(address _asset) external onlyOwner {
        // ensure not already added
        if (assets.length > 0 && assets[assetsIndex[_asset]] == _asset) {
            revert("Already added");
        }
        assetsIndex[_asset] = assets.length;
        assets.push(_asset);
        _allowedAsset[_asset] = true;
    }

    function setAllowedAsset(address _asset, bool _bool) external onlyOwner {
        _allowedAsset[_asset] = _bool;
    }

    function assetsLength() public view returns (uint256) {
        return assets.length;
    }

    function allowedAsset(address _asset) external view returns (bool) {
        return _allowedAsset[_asset];
    }

    function balanceIds(address _user) external view returns (uint[] memory) {
        uint[] memory _ids = new uint[](balanceOf(_user));
        for (uint i=0; i<_ids.length; i++) {
            _ids[i] = tokenOfOwnerByIndex(_user, i);
        }
        return _ids;
    }

    /*//////////////////////////////////////////////////////////////
                  META-TX OVERRIDES (if needed)
    ////////////////////////////////////////////////////////////////*/
    function _msgSender() internal view override(MetaContext, Ownable) returns (address) {
        // If your MetaContext does special forwarding logic, use that.
        // Otherwise, fallback to standard.
        return MetaContext._msgSender();
    }

    function _msgData() internal view override(MetaContext) returns (bytes calldata) {
        return MetaContext._msgData();
    }
}