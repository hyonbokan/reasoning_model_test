// File: Packs.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { NFT } from "./mock/NFT.sol";
import { ERC1155URIStorage, ERC1155 } from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IPacks } from "./IPacks.sol";

/**
 * @title Packs
 * @author zer0.tech
 * @custom:security-contact admin@zer0.tech
 * @notice ERC1155-based pack contract allowing multiple unseals per pack ID
 * @dev Implements IPacks, minimal changes from your original code
 */
contract Packs is IPacks, ERC1155URIStorage, AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    error NotPackOwner(address sender, uint256 packId);
    error Sealed(uint256 packId);
    error Paused();
    error InvalidPack(uint256 packId);
    error OutOfMetadata(uint256 packId);
    error ExceedsMaxMetadatas(uint256 packId, uint256 amount, uint256 numMetadatas, uint256 maxMetadatas);
    error NoAvailablePacks(address user, uint256 packId);
    error AlreadyUnsealedThisBlock(address user, uint256 blockNumber);
    error NoneUnsealed(uint256 packId);

    bool public override paused;
    uint256 public override unsealDelay;
    uint256 public override metadataInterval;

    mapping(uint256 packId => uint256[] blocks) public unsealBlocks;
    mapping(uint256 packId => uint256[] pool) public metadataPool;
    mapping(address sender => uint256 block) public lastUnsealBlock;

    NFT private nft1;
    NFT private nft2;
    NFT private nft3;

    /**
     * @notice Emitted when metadata is added to a pack ID
     * @param packId The pack ID
     * @param amount The number of new metadata entries added
     */
    event MetadataAdded(uint256 packId, uint256 amount);

    /**
     * @notice Emitted when the paused state changes
     * @param toState The new paused state
     */
    event PausedStateChanged(bool toState);

    /**
     * @notice Emitted when a user unseals a single copy of a pack
     * @param user The address unsealing the pack
     * @param packId The pack ID
     * @param atBlock The block at which unsealing happened (for logging)
     */
    event Unsealed(address indexed user, uint256 indexed packId, uint256 atBlock);

    /**
     * @notice Constructor for the Packs contract
     * @dev Grants DEFAULT_ADMIN_ROLE, ADMIN_ROLE, MINTER_ROLE to msg.sender
     * @param nft1_ First NFT contract
     * @param nft2_ Second NFT contract
     * @param nft3_ Third NFT contract
     * @param unsealDelay_ Number of blocks to wait between unseal and reveal
     * @param metadataInterval_ Must evenly divide a valid packId
     * @param metadataURI_ Base URI for ERC1155
     */
    constructor(
        NFT nft1_,
        NFT nft2_,
        NFT nft3_,
        uint256 unsealDelay_,
        uint256 metadataInterval_,
        string memory metadataURI_
    )
        ERC1155(metadataURI_)
    {
        nft1 = nft1_;
        nft2 = nft2_;
        nft3 = nft3_;
        unsealDelay = unsealDelay_;
        metadataInterval = metadataInterval_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    /**
     * @notice Modifier to ensure caller holds at least 1 copy of a given pack
     * @param packId The pack ID
     */
    modifier onlyPackOwner(uint256 packId) {
        if (balanceOf(msg.sender, packId) == 0) {
            revert NotPackOwner(msg.sender, packId);
        }
        _;
    }

    /**
     * @notice Sets the token-specific URI in ERC1155URIStorage
     * @param tokenId The token ID
     * @param tokenURI The new URI for that token
     */
    function setURI(uint256 tokenId, string memory tokenURI)
        external
        override
        onlyRole(ADMIN_ROLE)
    {
        _setURI(tokenId, tokenURI);
    }

    /**
     * @notice Sets the base URI in ERC1155URIStorage
     * @param baseURI The new base URI
     */
    function setBaseURI(string memory baseURI)
        external
        override
        onlyRole(ADMIN_ROLE)
    {
        _setBaseURI(baseURI);
    }

    /**
     * @notice Sets the fallback/global URI in ERC1155 (the _uri)
     * @param tokenURI The new fallback URI
     */
    function setFallbackURI(string memory tokenURI)
        external
        override
        onlyRole(ADMIN_ROLE)
    {
        _setURI(tokenURI);
    }

    /**
     * @notice Toggles the paused/unpaused state
     */
    function switchPaused() external override onlyRole(ADMIN_ROLE) {
        paused = !paused;
        emit PausedStateChanged(paused);
    }

    /**
     * @notice Adds new metadata to a given pack ID
     * @param packId The pack ID
     * @param amount Number of metadata entries to add
     */
    function addMetadata(uint256 packId, uint256 amount)
        external
        override
        onlyRole(ADMIN_ROLE)
    {
        if (packId == 0 || packId % metadataInterval != 0) {
            revert InvalidPack(packId);
        }
        uint256 currentLen = metadataPool[packId].length;
        uint256 targetLen = currentLen + amount;
        if (targetLen > metadataInterval) {
            revert ExceedsMaxMetadatas(packId, amount, currentLen, metadataInterval);
        }
        for (uint256 i = 0; i < amount; i++) {
            metadataPool[packId].push(packId + currentLen + i);
        }
        emit MetadataAdded(packId, amount);
    }

    /**
     * @notice Mints `amount` copies of `packId` to `to`
     * @param to Recipient
     * @param packId The pack ID
     * @param amount Number of copies
     */
    function mintPack(address to, uint256 packId, uint256 amount)
        external
        override
        onlyRole(MINTER_ROLE)
    {
        if (packId == 0 || packId % metadataInterval != 0) {
            revert InvalidPack(packId);
        }
        _mint(to, packId, amount, "");
    }

    /**
     * @notice Unseals one copy of `packId` for msg.sender
     * @param packId The pack ID
     */
    function unseal(uint256 packId) external override onlyPackOwner(packId) {
        if (paused) revert Paused();
        if (packId == 0) {
            revert InvalidPack(packId);
        }
        if (lastUnsealBlock[msg.sender] == block.number) {
            revert AlreadyUnsealedThisBlock(msg.sender, block.number);
        }
        lastUnsealBlock[msg.sender] = block.number;
        if (unsealBlocks[packId].length >= balanceOf(msg.sender, packId)) {
            revert NoAvailablePacks(msg.sender, packId);
        }
        unsealBlocks[packId].push(block.number + unsealDelay);
        emit Unsealed(msg.sender, packId, block.number);
    }

    /**
     * @notice Reveals one unsealed copy of `packId`
     * @param packId The pack ID
     */
    function reveal(uint256 packId) external override onlyPackOwner(packId) {
        if (metadataPool[packId].length == 0) {
            revert OutOfMetadata(packId);
        }
        if (paused) revert Paused();
        if (packId == 0) {
            revert InvalidPack(packId);
        }
        if (unsealBlocks[packId].length == 0) {
            revert NoneUnsealed(packId);
        }
        uint256 idx = unsealBlocks[packId].length - 1;
        uint256 unsealBlock = unsealBlocks[packId][idx];
        unsealBlocks[packId].pop();
        bytes32 bh = blockhash(unsealBlock);
        if (bh == bytes32(0)) {
            revert Sealed(packId);
        }
        uint256 index = uint256(bh) % metadataPool[packId].length;
        uint256 id = metadataPool[packId][index];
        metadataPool[packId][index] = metadataPool[packId][metadataPool[packId].length - 1];
        metadataPool[packId].pop();
        _burn(msg.sender, packId, 1);
        _mint(msg.sender, 0, 1, "");
        NFT(nft1).mint(msg.sender, id);
        NFT(nft2).mint(msg.sender, id);
        NFT(nft3).mint(msg.sender, id);
    }

    /**
     * @notice Supports ERC1155 + AccessControl + ERC165
     * @param interfaceId The interface ID
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}