
## **Summary of the project:**
The Vultisig protocol is a token-based system with whitelist functionality and initial liquidity offering (ILO) capabilities. The protocol consists of several interconnected contracts that work together to provide a controlled token distribution mechanism.

At the core of the protocol is the `Vultisig` token, an ERC20 token with an initial supply of 100 million tokens. The token is extended by the `VultisigWhitelisted` contract, which adds whitelist functionality to control token transfers during a restricted period. This whitelist mechanism is managed by the `Whitelist` contract, which maintains a list of approved addresses and enforces various restrictions on token transfers.

The whitelist system includes several key features:
- Self-whitelist functionality where users can register themselves (when enabled)
- Blacklist capability to block specific addresses
- Maximum contribution caps per address (default 3 ETH)
- Whitelist index tracking to prioritize certain addresses
- Oracle integration to calculate token prices using Uniswap V3 TWAP (Time-Weighted Average Price)

The protocol also includes an Initial Liquidity Offering (ILO) system through the `ILOManager` and `ILOPool` contracts. This system allows for:
- Creating projects with specific sale and raise tokens
- Initializing ILO pools with customizable parameters
- Managing token sales with hardcap and softcap requirements
- Vesting schedules for token distribution
- Launching liquidity on Uniswap V3 after successful sales

The ILO system includes safety mechanisms such as:
- Refund capabilities if launch deadlines are missed
- Whitelist controls for participation
- Platform and performance fees
- Vesting schedules to control token release over time

## Main Entry Points and Actors

### Vultisig Token
- `approveAndCall(address spender, uint256 amount, bytes calldata extraData)`: Allows users to approve token spending and trigger a callback function in a single transaction.

### Whitelist Contract
- `receive()`: Allows users to self-whitelist by sending ETH to the contract (when self-whitelist is enabled).
- `checkWhitelist(address from, address to, uint256 amount)`: Called by the Vultisig token during transfers to enforce whitelist rules.

### ILOManager
- `initProject(InitProjectParams calldata params)`: Allows project creators to initialize a new project with specific parameters.
- `initILOPool(InitPoolParams calldata params)`: Allows project admins to create ILO pools for their projects.
- `launch(address uniV3PoolAddress)`: Triggers the launch of a project's ILO pools after the sale period.
- `claimRefund(address uniV3PoolAddress)`: Allows project admins to claim refunds if the project fails to launch.
- `transferAdminProject(address admin, address uniV3Pool)`: Allows project admins to transfer admin rights to another address.

### ILOPool
- `buy(uint256 raiseAmount, address recipient)`: Allows whitelisted users to participate in token sales.
- `claim(uint256 tokenId)`: Allows token holders to claim their tokens according to vesting schedules.
- `claimRefund(uint256 tokenId)`: Allows users to claim refunds if a project fails to launch.
- `setOpenToAll(bool openToAll)`: Allows project admins to open the sale to all users (bypassing whitelist).
- `batchWhitelist(address[] calldata users)`: Allows project admins to add multiple addresses to the whitelist.
- `batchRemoveWhitelist(address[] calldata users)`: Allows project admins to remove multiple addresses from the whitelist.

### Actors
- **Users**: Can participate in token sales if whitelisted, claim tokens according to vesting schedules, and claim refunds if projects fail.
- **Project Admins**: Can create and manage ILO projects, control whitelist settings, and claim project refunds.
- **Protocol Owner**: Can set global parameters like platform fees, performance fees, and fee recipients.
- **Fee Taker**: Receives platform and performance fees from successful ILO projects.

## **Documentation of the project (if any):**

# Additional Documentation

Q: Additional audit information?
A: Vultisig is a multi-chain, multi-platform, threshold signature vault/wallet that requires no special hardware. It supports most UTXO, EVM, BFT and EdDSA chains. Based on Binance tss-lib, but adapted for mobile environment. It aims to improve security through multi-factor authentication while improving user onboarding and wallet management. This eliminates the need for the user to secure a seed phrase and improves on-chain privacy with multi-party computation archived with the Threshold Signature Scheme.

Vultisig token will be initially listed on UniswapV3(VULT/ETH pool). Whitelist contract will handle the initial whitelist launch and after this period, we will set whitelist contract address in Vultisig contract back to address(0) so tokens will be transferred without any restrictions.

In whitelist contract, there's checkWhitelist function which checks If from address is uniswap v3 pool which holds liquidity, then it means, this transfer is the buy action. We will apply the following WL logic. But if to address is owner address, then still ignore. Because owner has exclusive access like increase/decrease liquidity as well as collecting fees. - Token purchase is locked or not - Buyer is blacklisted or not - Buyer whitelist index is within allowed index range(starting from 1 and within 1 ~ allowedWhitelistIndex - inclusive) - ETH amount is greater than max address cap(default 3 ETH) or not.

Whitelist contract owner can:

- Set locked period

- Set maximum address cap

- Set vultisig token contract

- Set self whitelisted period

- Set TWAP oracle address

- Set blacklisted flag for certain addresses

- Set allowed whitelisted index(Especially when self whitelist is allowed, anyone can just send ETH and get whitelisted slot and each slot will be assigned by an index called whitelistIndex. There could be some suspicious actors so owner can add those addresses to the blacklist. In this case, the total whitelisted addresses will be whitelistCount - blacklistedCount. So owner can increase allowedWhitelistedIndex by blacklistedCount to make sure that always 1k whitelisted slots are secured.) - Add whitelisted addresses(single address and batched list).

Regarding ILO contracts:

- ILOPool.saleInfo: contains infomation for a sale like hard cap(max raise amount), soft cap(min raise amount to launch), max cap per user, sale start, sale end, max sale amount

- ILOPool._vestingConfigs: contains vesting config for both investor and project. First element will be config for investor.

- ILOManager._initializedILOPools: ilo pools associated with a project. When launch project, all ilo pools needs to launch successfully, otherwise, it will reverted. When project admin claim refund. it will claim refund for all initialized pools.

- ILOManager owner(trusted role) can extend/set refund deadline to any projects at any time. But after refund triggered or after launch, this is meaningless.

- Only project admin can init ilo pool for project and claim project refund (sale token deposited into ilo pool)

- iloPool belongs to only one project. One project can create many ilo pool.

- iloPool can only launch from manager. only project admin can launch project(aka launch all ilo pool)

- Anyone can trigger refund when refund condition met.

- Anyone can launch pool when all condition met.

- After refund triggered, no one can launch pool anymore.

- After pool launch, no one can trigger refund anymore.

- Once project inits, it inits a uniswap v3 pool. That pool address will be used as project id. You cannot change initial price after project is initialized. The Vultisig token should be burnable.


## **Invariants to consider (if any):**
```json
{"invariants": [{"description": "Total supply after deployment equals 100 million tokens", "function": "constructor", "condition": "```solidity\ntotalSupply() == 100_000_000 * 1e18\n```", "path": "hardhat-vultisig/contracts/Vultisig.sol"}, {"description": "Only the configured Vultisig contract can invoke whitelist checks", "function": "onlyVultisig modifier", "condition": "```solidity\nmsg.sender == _vultisig\n```", "path": "hardhat-vultisig/contracts/Whitelist.sol"}, {"description": "When adding a new whitelisted address index and count increment correctly", "function": "_addWhitelistedAddress", "condition": "```solidity\nif (_whitelistIndex[user] == 0) {\n  _whitelistCount == oldCount + 1 &&\n  _whitelistIndex[user] == _whitelistCount;\n}\n```", "path": "hardhat-vultisig/contracts/Whitelist.sol"}, {"description": "Receive only whitelists when self-whitelist enabled and not blacklisted", "function": "receive", "condition": "```solidity\n!_isSelfWhitelistDisabled && !_isBlacklisted[msg.sender]\n```", "path": "hardhat-vultisig/contracts/Whitelist.sol"}, {"description": "After self-whitelist, sender index must be non-zero", "function": "receive", "condition": "```solidity\n_whitelistIndex[msg.sender] > 0\n```", "path": "hardhat-vultisig/contracts/Whitelist.sol"}, {"description": "Contributed ETH never exceeds maxAddressCap", "function": "checkWhitelist", "condition": "```solidity\n_contributed[to] + estimatedETHAmount <= _maxAddressCap\n```", "path": "hardhat-vultisig/contracts/Whitelist.sol"}, {"description": "Lock flag enforced during pool-to-user transfers in whitelist period", "function": "checkWhitelist", "condition": "```solidity\nif (from == _pool && to != owner()) require(!_locked);\n```", "path": "hardhat-vultisig/contracts/Whitelist.sol"}, {"description": "Buyer must be whitelisted within allowed index on buy actions", "function": "checkWhitelist", "condition": "```solidity\n_allowedWhitelistIndex > 0 && _whitelistIndex[to] <= _allowedWhitelistIndex\n```", "path": "hardhat-vultisig/contracts/Whitelist.sol"}, {"description": "UniswapV3Oracle.peek output includes 5% slippage max", "function": "peek", "condition": "```solidity\npeek(baseAmount) <= quotedWETHAmount * baseAmount * 95 / 1e20\n```", "path": "hardhat-vultisig/contracts/oracles/uniswap/UniswapV3Oracle.sol"}, {"description": "OracleLibrary.consult rejects zero period", "function": "consult", "condition": "```solidity\nperiod != 0\n```", "path": "hardhat-vultisig/contracts/oracles/uniswap/uniswapv0.8/OracleLibrary.sol"}, {"description": "TickMath.getSqrtRatioAtTick input tick within allowed bounds", "function": "getSqrtRatioAtTick", "condition": "```solidity\nabs(tick) <= MAX_TICK\n```", "path": "hardhat-vultisig/contracts/oracles/uniswap/uniswapv0.8/TickMath.sol"}, {"description": "TickMath.getTickAtSqrtRatio enforces sqrtPriceX96 in valid range", "function": "getTickAtSqrtRatio", "condition": "```solidity\nMIN_SQRT_RATIO <= sqrtPriceX96 < MAX_SQRT_RATIO\n```", "path": "hardhat-vultisig/contracts/oracles/uniswap/uniswapv0.8/TickMath.sol"}, {"description": "FullMath.mulDiv denominator non-zero and result <2^256", "function": "mulDiv", "condition": "```solidity\ndenominator > 0 && result <= type(uint256).max\n```", "path": "hardhat-vultisig/contracts/oracles/uniswap/uniswapv0.8/FullMath.sol"}, {"description": "ILOManager.initialize only runs once", "function": "initialize", "condition": "```solidity\n!_initialized\n```", "path": "src/base/Initializable.sol"}, {"description": "initProject caches project with non-zero pool address", "function": "initProject", "condition": "```solidity\n_cachedProject[uniV3Pool].uniV3PoolAddress == uniV3Pool;\n```", "path": "src/ILOManager.sol"}, {"description": "Existing Uniswap V3 pool must match initial price if already initialized", "function": "_initUniV3PoolIfNecessary", "condition": "```solidity\nif (existingPrice != 0) require(existingPrice == sqrtPriceX96);\n```", "path": "src/ILOManager.sol"}, {"description": "initILOPool enforces sale window before launch", "function": "initILOPool", "condition": "```solidity\nparams.start < params.end && params.end < project.launchTime\n```", "path": "src/ILOManager.sol"}, {"description": "initILOPool price bounds valid relative to initial pool price", "function": "initILOPool", "condition": "```solidity\nsqrtLower < project.initialPoolPriceX96 && sqrtLower < sqrtUpper\n```", "path": "src/ILOManager.sol"}, {"description": "ILOPool.initialize computes maxSaleAmount \u2265 hardCap requirement", "function": "initialize", "condition": "```solidity\nsaleInfo.maxSaleAmount >= saleInfo.hardCap\n```", "path": "src/ILOPool.sol"}, {"description": "buy enforces whitelist and sale timing", "function": "buy", "condition": "```solidity\n_isWhitelisted(recipient) && block.timestamp > saleInfo.start && block.timestamp < saleInfo.end\n```", "path": "src/ILOPool.sol"}, {"description": "buy respects hard cap and per-user cap", "function": "buy", "condition": "```solidity\ntotalRaised + raiseAmount <= saleInfo.hardCap &&\n_position.raiseAmount + raiseAmount <= saleInfo.maxCapPerUser\n```", "path": "src/ILOPool.sol"}, {"description": "buy produces strictly positive liquidityDelta", "function": "buy", "condition": "```solidity\nliquidityDelta > 0\n```", "path": "src/ILOPool.sol"}, {"description": "totalSold never exceeds maxSaleAmount", "function": "buy", "condition": "```solidity\ntotalSold() <= saleInfo.maxSaleAmount\n```", "path": "src/ILOPool.sol"}, {"description": "claim only after successful launch and with sufficient liquidity", "function": "claim", "condition": "```solidity\n_launchSucceeded && position.liquidity >= liquidity2Claim\n```", "path": "src/ILOPool.sol"}, {"description": "launch only once and after soft cap met", "function": "launch", "condition": "```solidity\n!_launchSucceeded && !_refundTriggered && totalRaised >= saleInfo.softCap\n```", "path": "src/ILOPool.sol"}, {"description": "refund triggers only if not launched and past deadline", "function": "refundable modifier", "condition": "```solidity\n!_launchSucceeded && block.timestamp >= project.refundDeadline\n```", "path": "src/ILOPool.sol"}, {"description": "Unlocked liquidity never exceeds total liquidity", "function": "_unlockedLiquidity", "condition": "```solidity\nliquidityUnlocked <= totalLiquidity\n```", "path": "src/ILOPool.sol"}, {"description": "LiquidityAmounts.getLiquidityForAmount0 returns uint128 with no overflow", "function": "getLiquidityForAmount0", "condition": "```solidity\nliquidity <= type(uint128).max\n```", "path": "src/libraries/LiquidityAmounts.sol"}]}
```

## **Additional context from web to assist with the audit (if any):**
# Solidity Compiler and EVM Upgrades: Security Considerations

## Security Impact of Solidity 0.8.24 ("Cancun") Features

- **Changing EVM Behavior:**  
    - Deployed contracts may behave differently due to changes in underlying opcodes (notably SELFDESTRUCT).  
    - Developers must carefully review all contract logic that relies on deprecated features, especially upgrade and destruction patterns.

- **Transient Storage (`tload`, `tstore`) [EIP-1153]:**  
    - Useful for intra-transaction data passing and secure reentrancy guards, but improper logic may introduce intra-transaction state leaks or accidentally bypass security invariants.
    - Use of new storage locations means tailored auditing for each use case is essential.

- **EIP-4844 (Blob Transactions, `blobhash`, `block.blobbasefee`):**  
    - Blobhashes expose new features but require trust in external data sources and new potential for misuse.
    - Be cautious integrating any external data commitment (such as KZG commitments).

- **MCOPY Opcode [EIP-5656]:**  
    - New efficient memory copy can be used only via assembly/Yul.  
    - Custom memory manipulation may introduce vulnerabilities—including memory corruption or unexpected reentrancy—if not expertly implemented.

- **SELFDESTRUCT [EIP-6780]:**  
    - Major behavior change: SELFDESTRUCT no longer removes code/storage except within contract creation–affecting proxy "upgrade", self-destruct-on-finalize, etc.
    - Auditors and developers **should avoid** using SELFDESTRUCT in new contracts.

```solidity
// Solidity addition: access the blob base fee
uint blobFee = block.blobbasefee;

// Solidity: retrieve versioned hash of a blob
bytes32 commitment = blobhash(uint(blobIndex));
```

---

# Token Integration Security: Risks & Audit Points

## 1. ERC-20 Tokens — Security-Related Behaviors & Best Practices

- **Blacklisting/Whitelisting:**  
    - Tokens (e.g., USDT, USDC) may block transfers to/from specified addresses.
    - Always assess for sender/receiver blacklist/whitelist logic.

    ```solidity
    // Pseudocode
    function isBlacklisted(address account) external view returns (bool);
    ```

- **Pausability:**  
    - Some tokens can pause all transfers.
    - Transfers and approvals must be guarded by such checks.

    ```solidity
    function pause() public onlyOwner {}
    function transfer(address, uint256) public whenNotPaused {}
    ```

- **Hooks & Arbitrary Receiver Code (ERC777/721):**  
    - Transfer hooks can enable reentrancy.
    - Always consider the possibility of code execution on token send/receive.

- **Transfer Restrictions:**  
    - E.g., cannot transfer to zero address or to token contract, or zero-value transfer forbidden.
    - Always check for explicit require statements or custom logic in token transfer code.

- **Deflationary/Fee-On-Transfer Tokens:**  
    - Internal balance accounting must always be based on `balanceOf` after transfer completes, due to possible transfer fees.

    ```solidity
    // Receive-after pattern (Compound, CErc20)
    uint preBalance = token.balanceOf(address(this));
    token.transferFrom(sender, address(this), amount);
    uint postBalance = token.balanceOf(address(this));
    uint actuallyReceived = postBalance - preBalance;
    ```

- **Non-Standard Return Values:**  
    - Some tokens revert, some return `false`, some return nothing.
    - Use OpenZeppelin's `SafeERC20`:

    ```solidity
    import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
    ```

- **Flash Mint/Loan Behavior:**  
    - Balances may swing wildly due to flash loans/mints, affecting protocol invariants.

- **Elastic/Interest-Bearing Tokens:**  
    - `balanceOf` may autonomously change due to rebasing/yield; never cache balances.

- **Infinite Approvals & Allowance Logic:**  
    - Don't assume allowance always decrements with transfer; check for weirdness (DAI et al).

    ```solidity
    // Some tokens require allowance to be set to zero before an update
    // OpenZeppelin's SafeERC20 handles this
    ```

- **Variable Decimals & Metadata:**  
    - Not all tokens provide `decimals`, `name`, or `symbol`. Defend with `try/catch` or explicit guards.
    ```solidity
    try token.decimals() returns (uint8 d) {
        // Use decimals
    } catch {
        // Fallback
    }
    ```

- **Upgradeable Token Contracts:**  
    - Implementation may change beneath integrators' feet; monitor logic for proxy-based tokens.

## Summary Recommendations

- Always review, document and/or restrict which tokens a protocol accepts.
- Use battle-tested wrappers (OpenZeppelin `SafeERC20`) and never make assumptions about ERC-20 conformance.
- Practice the "zero trust" principle: treat all external tokens as untrusted, potentially malicious code.

---

# Oracle Manipulation Risks (Uniswap V3)

- **TWAP Oracle Manipulation:**
    - Uniswap v3's TWAP (Time-Weighted Average Price) can be manipulated by exploiting low liquidity or skewed liquidity profiles.
    - Attacks involve pushing pool prices (spot, over a given window) at significant economic costs. Calculators and simulators exist to help audit risk.

- **Mitigation:**
    - Use longer TWAP windows.
    - Cross-check on/off chain price (e.g., Binance vs Uniswap TWAP).
    - Use multiple oracles for redundancy.

---

# ERC-20: Common Vulnerabilities and Secure Patterns

- **Reentrancy Attacks:**  
    - Prevent via checks-effects-interactions:
    ```solidity
    function withdraw(uint256 _amount) public {
        require(balances[msg.sender] >= _amount, "Insufficient balance");
        balances[msg.sender] -= _amount;
        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Transfer failed");
    }
    ```

- **Overflow/Underflow:**  
    - Use Solidity 0.8+ (checked by default) or `SafeMath` library.
    ```solidity
    using SafeMath for uint256;
    uint256 newBalance = balance.add(_amount);
    ```

- **Access Control:**  
    - Always implement and test robust owner/admin modifiers.

- **Allowance Sniping:**  
    - Always set `approve(spender, 0)` before granting a new nonzero allowance.

- **Phishing/Impersonation:**  
    - Communicate official contract addresses, warn users to verify contracts.

---

# Threshold Signature Scheme (TSS): Security & Adoption Concerns

- **Binance tss-lib (Binance multi-party threshold vaults):**
    - Serious historical vulnerabilities (CVE-2020-12118 and more).
    - Replay attacks, hash collisions, non-constant-time crypto operations.
    - Dependency risks if built atop outdated Go cryptographic libraries.

- **Best Practices:**
    - Always keep tss-lib updated (≥ v1.2.0).
    - Ensure session IDs are enforced for every protocol round.
    - Avoid production use unless all issues are resolved and code extensively audited.

---

# Summary: Security Best Practices for Auditors

- Audit for all edge-cases and non-compliance to standard token interfaces.
- Verify token and vault contracts use explicit access control, secure math, and safe patterns for transfers.
- Triple-check for reliance on oracles—especially custom or Uniswap-based TWAP implementations—and model manipulation cost/probabilities.
- For any TSS/key management, ensure protocol and cryptographic primitives are industry-audited, supply chain dependencies are current, and implementation follows the latest published guidelines.

---

**References & Tools:**
- [OpenZeppelin SafeERC20](https://docs.openzeppelin.com/contracts/4.x/api/token/erc20#SafeERC20)
- [Uniswap Oracle Attack Simulator](https://oracle.euler.finance/)
- [Token Integration Checklist](https://github.com/crytic/building-secure-contracts/blob/master/development-guidelines/token_integration.md)
- [CVE-2020-12118 Binance tss-lib vulnerability and patch](https://github.com/binance-chain/tss-lib/pull/89)

---

**NOTE:** All Solidity code blocks and patterns above are relevant for secure smart contract implementation and direct use in documentation or audit reviews.

---

## **Contracts to audit:**
```solidity
// File: Vultisig.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IApproveAndCallReceiver} from "./interfaces/IApproveAndCallReceiver.sol";

/**
 * @title ERC20 based Vultisig token contract
 */
contract Vultisig is ERC20, Ownable {
    constructor() ERC20("Vultisig Token", "VULT") {
        _mint(_msgSender(), 100_000_000 * 1e18);
    }

    function approveAndCall(address spender, uint256 amount, bytes calldata extraData) external returns (bool) {
        // Approve the spender to spend the tokens
        _approve(msg.sender, spender, amount);

        // Call the receiveApproval function on the spender contract
        IApproveAndCallReceiver(spender).receiveApproval(msg.sender, amount, address(this), extraData);

        return true;
    }
}


// File: Whitelist.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IOracle} from "./interfaces/IOracle.sol";

/**
 * @title The contract handles whitelist related features
 * @notice The main functionalities are:
 * - Self whitelist by sending ETH to this contract(only when self whitelist is allowed - controlled by _isSelfWhitelistDisabled flag)
 * - Ownable: Add whitelisted/blacklisted addresses
 * - Ownable: Set max ETH amount to buy(default 3 ETH)
 * - Ownable: Set univ3 TWAP oracle
 * - Vultisig contract `_beforeTokenTransfer` hook will call `checkWhitelist` function and this function will check if buyer is eligible
 */
contract Whitelist is Ownable {
    error NotWhitelisted();
    error Locked();
    error NotVultisig();
    error SelfWhitelistDisabled();
    error Blacklisted();
    error MaxAddressCapOverflow();

    /// @notice Maximum ETH amount to contribute
    uint256 private _maxAddressCap;
    /// @notice Flag for locked period
    bool private _locked;
    /// @notice Flag for self whitelist period
    bool private _isSelfWhitelistDisabled;
    /// @notice Vultisig token contract address
    address private _vultisig;
    /// @notice Uniswap v3 TWAP oracle
    address private _oracle;
    /// @notice Uniswap v3 pool address
    address private _pool;
    /// @notice Total number of whitelisted addresses
    uint256 private _whitelistCount;
    /// @notice Max index allowed
    uint256 private _allowedWhitelistIndex;
    /// @notice Whitelist index for each whitelisted address
    mapping(address => uint256) private _whitelistIndex;
    /// @notice Mapping for blacklisted addresses
    mapping(address => bool) private _isBlacklisted;
    /// @notice Contributed ETH amounts
    mapping(address => uint256) private _contributed;

    /// @notice Set the default max address cap to 3 ETH and lock token transfers initially
    constructor() {
        _maxAddressCap = 3 ether;
        _locked = true; // Initially, liquidity will be locked
    }

    /// @notice Check if called from vultisig token contract.
    modifier onlyVultisig() {
        if (_msgSender() != _vultisig) {
            revert NotVultisig();
        }
        _;
    }

    /// @notice Self-whitelist using ETH transfer
    /// @dev reverts if whitelist is disabled
    /// @dev reverts if address is already blacklisted
    /// @dev ETH will be sent back to the sender
    receive() external payable {
        if (_isSelfWhitelistDisabled) {
            revert SelfWhitelistDisabled();
        }
        if (_isBlacklisted[_msgSender()]) {
            revert Blacklisted();
        }
        _addWhitelistedAddress(_msgSender());
        payable(_msgSender()).transfer(msg.value);
    }

    /// @notice Returns max address cap
    function maxAddressCap() external view returns (uint256) {
        return _maxAddressCap;
    }

    /// @notice Returns vultisig address
    function vultisig() external view returns (address) {
        return _vultisig;
    }

    /// @notice Returns the whitelisted index. If not whitelisted, then it will be 0
    /// @param account The address to be checked
    function whitelistIndex(address account) external view returns (uint256) {
        return _whitelistIndex[account];
    }

    /// @notice Returns if the account is blacklisted or not
    /// @param account The address to be checked
    function isBlacklisted(address account) external view returns (bool) {
        return _isBlacklisted[account];
    }

    /// @notice Returns if self-whitelist is allowed or not
    function isSelfWhitelistDisabled() external view returns (bool) {
        return _isSelfWhitelistDisabled;
    }

    /// @notice Returns Univ3 TWAP oracle address
    function oracle() external view returns (address) {
        return _oracle;
    }

    /// @notice Returns Univ3 pool address
    function pool() external view returns (address) {
        return _pool;
    }

    /// @notice Returns current whitelisted address count
    function whitelistCount() external view returns (uint256) {
        return _whitelistCount;
    }

    /// @notice Returns current allowed whitelist index
    function allowedWhitelistIndex() external view returns (uint256) {
        return _allowedWhitelistIndex;
    }

    /// @notice Returns contributed ETH amount for address
    /// @param to The address to be checked
    function contributed(address to) external view returns (uint256) {
        return _contributed[to];
    }

    /// @notice If token transfer is locked or not
    function locked() external view returns (bool) {
        return _locked;
    }

    /// @notice Setter for locked flag
    /// @param newLocked New flag to be set
    function setLocked(bool newLocked) external onlyOwner {
        _locked = newLocked;
    }

    /// @notice Setter for max address cap
    /// @param newCap New cap for max ETH amount
    function setMaxAddressCap(uint256 newCap) external onlyOwner {
        _maxAddressCap = newCap;
    }

    /// @notice Setter for vultisig token
    /// @param newVultisig New vultisig token address
    function setVultisig(address newVultisig) external onlyOwner {
        _vultisig = newVultisig;
    }

    /// @notice Setter for self-whitelist period
    /// @param newFlag New flag for self-whitelist period
    function setIsSelfWhitelistDisabled(bool newFlag) external onlyOwner {
        _isSelfWhitelistDisabled = newFlag;
    }

    /// @notice Setter for Univ3 TWAP oracle
    /// @param newOracle New oracle address
    function setOracle(address newOracle) external onlyOwner {
        _oracle = newOracle;
    }

    /// @notice Setter for Univ3 pool
    /// @param newPool New pool address
    function setPool(address newPool) external onlyOwner {
        _pool = newPool;
    }

    /// @notice Setter for blacklist
    /// @param blacklisted Address to be added
    /// @param flag New flag for address
    function setBlacklisted(address blacklisted, bool flag) external onlyOwner {
        _isBlacklisted[blacklisted] = flag;
    }

    /// @notice Setter for allowed whitelist index
    /// @param newIndex New index for allowed whitelist
    function setAllowedWhitelistIndex(uint256 newIndex) external onlyOwner {
        _allowedWhitelistIndex = newIndex;
    }

    /// @notice Add whitelisted address
    /// @param whitelisted Address to be added
    function addWhitelistedAddress(address whitelisted) external onlyOwner {
        _addWhitelistedAddress(whitelisted);
    }

    /// @notice Add batch whitelists
    /// @param whitelisted Array of addresses to be added
    function addBatchWhitelist(address[] calldata whitelisted) external onlyOwner {
        for (uint i = 0; i < whitelisted.length; i++) {
            _addWhitelistedAddress(whitelisted[i]);
        }
    }

    /// @notice Check if address to is eligible for whitelist
    /// @param from sender address
    /// @param to recipient address
    /// @param amount Number of tokens to be transferred
    /// @dev Check WL should be applied only
    /// @dev Revert if locked, not whitelisted, blacklisted or already contributed more than capped amount
    /// @dev Update contributed amount
    function checkWhitelist(address from, address to, uint256 amount) external onlyVultisig {
        if (from == _pool && to != owner()) {
            // We only add limitations for buy actions via uniswap v3 pool
            // Still need to ignore WL check if it's owner related actions
            if (_locked) {
                revert Locked();
            }

            if (_isBlacklisted[to]) {
                revert Blacklisted();
            }

            if (_allowedWhitelistIndex == 0 || _whitelistIndex[to] > _allowedWhitelistIndex) {
                revert NotWhitelisted();
            }

            // // Calculate rough ETH amount for VULT amount
            uint256 estimatedETHAmount = IOracle(_oracle).peek(amount);
            if (_contributed[to] + estimatedETHAmount > _maxAddressCap) {
                revert MaxAddressCapOverflow();
            }

            _contributed[to] += estimatedETHAmount;
        }
    }

    /// @notice Internal function used for whitelisting. Only increase whitelist count if address is not whitelisted before
    /// @param whitelisted Address to be added
    function _addWhitelistedAddress(address whitelisted) private {
        if (_whitelistIndex[whitelisted] == 0) {
            _whitelistIndex[whitelisted] = ++_whitelistCount;
        }
    }
}


// File: VultisigWhitelisted.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vultisig} from "../Vultisig.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

/**
 * @title Extended Vultisig token contract with whitelist contract interactions
 * @notice During whitelist period, `_beforeTokenTransfer` function will call `checkWhitelist` function of whitelist contract
 * @notice If whitelist period is ended, owner will set whitelist contract address back to address(0) and tokens will be transferred freely
 */
contract VultisigWhitelisted is Vultisig {
    /// @notice whitelist contract address
    address private _whitelistContract;

    /// @notice Returns current whitelist contract address
    function whitelistContract() external view returns (address) {
        return _whitelistContract;
    }

    /// @notice Ownable function to set new whitelist contract address
    function setWhitelistContract(address newWhitelistContract) external onlyOwner {
        _whitelistContract = newWhitelistContract;
    }

    /// @notice Before token transfer hook
    /// @dev It will call `checkWhitelist` function and if it's succsessful, it will transfer tokens, unless revert
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (_whitelistContract != address(0)) {
            IWhitelist(_whitelistContract).checkWhitelist(from, to, amount);
        }
        super._beforeTokenTransfer(from, to, amount);
    }
}


// File: UniswapV3Oracle.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from "./uniswapv0.8/OracleLibrary.sol";
import {IOracle} from "../../interfaces/IOracle.sol";

/**
 * @title UniswapV3Oracle
 * @notice For VULT/ETH pool, it will return TWAP price for the last 30 mins and add 5% slippage
 * @dev This price will be used in whitelist contract to calculate the ETH tokenIn amount.
 * The actual amount could be different because, the ticks used at the time of purchase won't be the same as this TWAP
 */
contract UniswapV3Oracle is IOracle {
    /// @notice TWAP period
    uint32 public constant PERIOD = 30 minutes;
    /// @notice Will calculate 1 VULT price in ETH
    uint128 public constant BASE_AMOUNT = 1e18; // VULT has 18 decimals

    /// @notice VULT/WETH pair
    address public immutable pool;
    /// @notice VULT token address
    address public immutable baseToken;
    /// @notice WETH token address
    address public immutable WETH;

    constructor(address _pool, address _baseToken, address _WETH) {
        pool = _pool;
        baseToken = _baseToken;
        WETH = _WETH;
    }

    /// @notice Returns VULT/WETH Univ3TWAP
    function name() external pure returns (string memory) {
        return "VULT/WETH Univ3TWAP";
    }

    /// @notice Returns TWAP price for 1 VULT for the last 30 mins
    function peek(uint256 baseAmount) external view returns (uint256) {
        uint32 longestPeriod = OracleLibrary.getOldestObservationSecondsAgo(pool);
        uint32 period = PERIOD < longestPeriod ? PERIOD : longestPeriod;
        int24 tick = OracleLibrary.consult(pool, period);
        uint256 quotedWETHAmount = OracleLibrary.getQuoteAtTick(tick, BASE_AMOUNT, baseToken, WETH);
        // Apply 5% slippage
        return (quotedWETHAmount * baseAmount * 95) / 1e20; // 100 / 1e18
    }
}


// File: FullMath.sol
// SPDX-License-Identifier: MIT
pragma solidity >=0.4.0;

/// @title Contains 512-bit math functions
/// @notice Facilitates multiplication and division that can have overflow of an intermediate value without any loss of precision
/// @dev Handles "phantom overflow" i.e., allows multiplication and division where an intermediate value overflows 256 bits
library FullMath {
    /// @notice Calculates floor(a×b÷denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return result The 256-bit result
    /// @dev Credit to Remco Bloemen under MIT license https://xn--2-umb.com/21/muldiv
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        // 512-bit multiply [prod1 prod0] = a * b
        // Compute the product mod 2**256 and mod 2**256 - 1
        // then use the Chinese Remainder Theorem to reconstruct
        // the 512 bit result. The result is stored in two 256
        // variables such that product = prod1 * 2**256 + prod0
        uint256 prod0; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // Handle non-overflow cases, 256 by 256 division
        if (prod1 == 0) {
            require(denominator > 0);
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }

        // Make sure the result is less than 2**256.
        // Also prevents denominator == 0
        require(denominator > prod1);

        ///////////////////////////////////////////////
        // 512 by 256 division.
        ///////////////////////////////////////////////

        // Make division exact by subtracting the remainder from [prod1 prod0]
        // Compute remainder using mulmod
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        // Subtract 256 bit number from 512 bit number
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        // Factor powers of two out of denominator
        // Compute largest power of two divisor of denominator.
        // Always >= 1.
        uint256 twos = (~denominator + 1) & denominator;
        // Divide denominator by power of two
        assembly {
            denominator := div(denominator, twos)
        }

        // Divide [prod1 prod0] by the factors of two
        assembly {
            prod0 := div(prod0, twos)
        }
        // Shift in bits from prod1 into prod0. For this we need
        // to flip `twos` such that it is 2**256 / twos.
        // If twos is zero, then it becomes one
        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;

        // Invert denominator mod 2**256
        // Now that denominator is an odd number, it has an inverse
        // modulo 2**256 such that denominator * inv = 1 mod 2**256.
        // Compute the inverse by starting with a seed that is correct
        // correct for four bits. That is, denominator * inv = 1 mod 2**4
        uint256 inv = (3 * denominator) ^ 2;
        // Now use Newton-Raphson iteration to improve the precision.
        // Thanks to Hensel's lifting lemma, this also works in modular
        // arithmetic, doubling the correct bits in each step.
        inv *= 2 - denominator * inv; // inverse mod 2**8
        inv *= 2 - denominator * inv; // inverse mod 2**16
        inv *= 2 - denominator * inv; // inverse mod 2**32
        inv *= 2 - denominator * inv; // inverse mod 2**64
        inv *= 2 - denominator * inv; // inverse mod 2**128
        inv *= 2 - denominator * inv; // inverse mod 2**256

        // Because the division is now exact we can divide by multiplying
        // with the modular inverse of denominator. This will give us the
        // correct result modulo 2**256. Since the precoditions guarantee
        // that the outcome is less than 2**256, this is the final result.
        // We don't need to compute the high bits of the result and prod1
        // is no longer required.
        result = prod0 * inv;
        return result;
    }

    /// @notice Calculates ceil(a×b÷denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return result The 256-bit result
    function mulDivRoundingUp(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        result = mulDiv(a, b, denominator);
        if (mulmod(a, b, denominator) > 0) {
            require(result < type(uint256).max);
            result++;
        }
    }
}


// File: OracleLibrary.sol
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./FullMath.sol";
import "./TickMath.sol";

/// @title Oracle library
/// @notice Provides functions to integrate with V3 pool oracle
library OracleLibrary {
    /// @notice Fetches time-weighted average tick using Uniswap V3 oracle
    /// @param pool Address of Uniswap V3 pool that we want to observe
    /// @param period Number of seconds in the past to start calculating time-weighted average
    /// @return timeWeightedAverageTick The time-weighted average tick from (block.timestamp - period) to block.timestamp
    function consult(address pool, uint32 period) internal view returns (int24 timeWeightedAverageTick) {
        require(period != 0, "BP");

        uint32[] memory secondAgos = new uint32[](2);
        secondAgos[0] = period;
        secondAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(secondAgos);
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        timeWeightedAverageTick = int24(tickCumulativesDelta / int56(uint56(period)));

        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(period)) != 0)) timeWeightedAverageTick--;
    }

    /// @notice Given a tick and a token amount, calculates the amount of token received in exchange
    /// @param tick Tick value used to calculate the quote
    /// @param baseAmount Amount of token to be converted
    /// @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
    /// @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
    /// @return quoteAmount Amount of quoteToken received for baseAmount of baseToken
    function getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) internal pure returns (uint256 quoteAmount) {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }

    /// @notice Given a pool, it returns the number of seconds ago of the oldest stored observation
    /// @param pool Address of Uniswap V3 pool that we want to observe
    /// @return secondsAgo The number of seconds ago of the oldest observation stored for the pool
    function getOldestObservationSecondsAgo(address pool) internal view returns (uint32 secondsAgo) {
        (, , uint16 observationIndex, uint16 observationCardinality, , , ) = IUniswapV3Pool(pool).slot0();
        require(observationCardinality > 0, "NI");

        (uint32 observationTimestamp, , , bool initialized) = IUniswapV3Pool(pool).observations(
            (observationIndex + 1) % observationCardinality
        );

        // The next index might not be initialized if the cardinality is in the process of increasing
        // In this case the oldest observation is always in index 0
        if (!initialized) {
            (observationTimestamp, , , ) = IUniswapV3Pool(pool).observations(0);
        }

        secondsAgo = uint32(block.timestamp) - observationTimestamp;
    }
}


// File: TickMath.sol
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Math library for computing sqrt prices from ticks and vice versa
/// @notice Computes sqrt price for ticks of size 1.0001, i.e. sqrt(1.0001^tick) as fixed point Q64.96 numbers. Supports
/// prices between 2**-128 and 2**128
library TickMath {
    /// @dev The minimum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**-128
    int24 internal constant MIN_TICK = -887272;
    /// @dev The maximum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**128
    int24 internal constant MAX_TICK = -MIN_TICK;

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    /// @notice Calculates sqrt(1.0001^tick) * 2^96
    /// @dev Throws if |tick| > max tick
    /// @param tick The input tick for the above formula
    /// @return sqrtPriceX96 A Fixed point Q64.96 number representing the sqrt of the ratio of the two assets (token1/token0)
    /// at the given tick
    function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
        uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
        require(absTick <= uint256(uint24(MAX_TICK)), "T");

        uint256 ratio = absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        if (tick > 0) ratio = type(uint256).max / ratio;

        // this divides by 1<<32 rounding up to go from a Q128.128 to a Q128.96.
        // we then downcast because we know the result always fits within 160 bits due to our tick input constraint
        // we round up in the division so getTickAtSqrtRatio of the output price is always consistent
        sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }

    /// @notice Calculates the greatest tick value such that getRatioAtTick(tick) <= ratio
    /// @dev Throws in case sqrtPriceX96 < MIN_SQRT_RATIO, as MIN_SQRT_RATIO is the lowest value getRatioAtTick may
    /// ever return.
    /// @param sqrtPriceX96 The sqrt ratio for which to compute the tick as a Q64.96
    /// @return tick The greatest tick for which the ratio is less than or equal to the input ratio
    function getTickAtSqrtRatio(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
        // second inequality must be < because the price can never reach the price at the max tick
        require(sqrtPriceX96 >= MIN_SQRT_RATIO && sqrtPriceX96 < MAX_SQRT_RATIO, "R");
        uint256 ratio = uint256(sqrtPriceX96) << 32;

        uint256 r = ratio;
        uint256 msb = 0;

        assembly {
            let f := shl(7, gt(r, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(6, gt(r, 0xFFFFFFFFFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(5, gt(r, 0xFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(4, gt(r, 0xFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(3, gt(r, 0xFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(2, gt(r, 0xF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(1, gt(r, 0x3))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := gt(r, 0x1)
            msb := or(msb, f)
        }

        if (msb >= 128) r = ratio >> (msb - 127);
        else r = ratio << (127 - msb);

        int256 log_2 = (int256(msb) - 128) << 64;

        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(63, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(62, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(61, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(60, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(59, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(58, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(57, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(56, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(55, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(54, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(53, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(52, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(51, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(50, f))
        }

        int256 log_sqrt10001 = log_2 * 255738958999603826347141; // 128.128 number

        int24 tickLow = int24((log_sqrt10001 - 3402992956809132418596140100660247210) >> 128);
        int24 tickHi = int24((log_sqrt10001 + 291339464771989622907027621153398088495) >> 128);

        tick = tickLow == tickHi
            ? tickLow
            : getSqrtRatioAtTick(tickHi) <= sqrtPriceX96
                ? tickHi
                : tickLow;
    }
}


// File: ILOManager.sol
// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import "./interfaces/IILOManager.sol";
import "./interfaces/IILOPool.sol";
import "./libraries/ChainId.sol";
import './base/Initializable.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import "@openzeppelin/contracts/access/Ownable.sol";
import '@openzeppelin/contracts/proxy/Clones.sol';

contract ILOManager is IILOManager, Ownable, Initializable {
    address public override UNIV3_FACTORY;
    address public override WETH9;

    uint64 private DEFAULT_DEADLINE_OFFSET = 7 * 24 * 60 * 60; // 7 days
    uint16 public override PLATFORM_FEE;
    uint16 public override PERFORMANCE_FEE;
    address public override FEE_TAKER;
    address public override ILO_POOL_IMPLEMENTATION;

    mapping(address => Project) private _cachedProject; // map uniV3Pool => project (aka projectId => project)
    mapping(address => address[]) private _initializedILOPools; // map uniV3Pool => list of initialized ilo pools

    /// @dev since deploy via deployer so we need to claim ownership
    constructor () {
        transferOwnership(tx.origin);
    }

    function initialize(
        address initialOwner,
        address _feeTaker,
        address iloPoolImplementation,
        address uniV3Factory,
        address weth9,
        uint16 platformFee,
        uint16 performanceFee
    ) external override whenNotInitialized() {
        PLATFORM_FEE = platformFee;
        PERFORMANCE_FEE = performanceFee;
        FEE_TAKER = _feeTaker;
        transferOwnership(initialOwner);
        UNIV3_FACTORY = uniV3Factory;
        ILO_POOL_IMPLEMENTATION = iloPoolImplementation;
        WETH9 = weth9;
    }

    modifier onlyProjectAdmin(address uniV3Pool) {
        require(_cachedProject[uniV3Pool].admin == msg.sender, "UA");
        _;
    }

    /// @inheritdoc IILOManager
    function initProject(InitProjectParams calldata params) external override afterInitialize() returns(address uniV3PoolAddress) {
        uint64 refundDeadline = params.launchTime + DEFAULT_DEADLINE_OFFSET;

        PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(params.saleToken, params.raiseToken, params.fee);
        uniV3PoolAddress = _initUniV3PoolIfNecessary(poolKey, params.initialPoolPriceX96);
        
        _cacheProject(uniV3PoolAddress, params.saleToken, params.raiseToken, params.fee, params.initialPoolPriceX96, params.launchTime, refundDeadline);
        emit ProjectCreated(uniV3PoolAddress, _cachedProject[uniV3PoolAddress]);
    }

    function project(address uniV3PoolAddress) external override view returns (Project memory) {
        return _cachedProject[uniV3PoolAddress];
    }

    /// @inheritdoc IILOManager
    function initILOPool(InitPoolParams calldata params) external override onlyProjectAdmin(params.uniV3Pool) returns (address iloPoolAddress) {
        Project storage _project = _cachedProject[params.uniV3Pool];
        {
            require(_project.uniV3PoolAddress != address(0), "NI");
            // validate time for sale start and end compared to launch time
            require(params.start < params.end && params.end < _project.launchTime, "PT");
            // this salt make sure that pool address can not be represented in any other chains
            bytes32 salt = keccak256(abi.encodePacked(
                ChainId.get(),
                params.uniV3Pool,
                _initializedILOPools[params.uniV3Pool].length
            ));
            iloPoolAddress = Clones.cloneDeterministic(ILO_POOL_IMPLEMENTATION, salt);
            emit ILOPoolCreated(_project.uniV3PoolAddress, iloPoolAddress, _initializedILOPools[params.uniV3Pool].length);
        }

        uint160 sqrtRatioLowerX96 = TickMath.getSqrtRatioAtTick(params.tickLower);
        uint160 sqrtRatioUpperX96 = TickMath.getSqrtRatioAtTick(params.tickUpper);
        require(sqrtRatioLowerX96 < _project.initialPoolPriceX96 && sqrtRatioLowerX96 < sqrtRatioUpperX96, "RANGE");

        IILOPool.InitPoolParams memory initParams = IILOPool.InitPoolParams({
            uniV3Pool: params.uniV3Pool,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            sqrtRatioLowerX96: sqrtRatioLowerX96,
            sqrtRatioUpperX96: sqrtRatioUpperX96,
            hardCap: params.hardCap,
            softCap: params.softCap,
            maxCapPerUser: params.maxCapPerUser,
            start: params.start,
            end: params.end,
            vestingConfigs: params.vestingConfigs
        });
        IILOPool(iloPoolAddress).initialize(initParams);
        _initializedILOPools[params.uniV3Pool].push(iloPoolAddress);
    }

    function _initUniV3PoolIfNecessary(PoolAddress.PoolKey memory poolKey, uint160 sqrtPriceX96) internal returns (address pool) {
        pool = IUniswapV3Factory(UNIV3_FACTORY).getPool(poolKey.token0, poolKey.token1, poolKey.fee);
        if (pool == address(0)) {
            pool = IUniswapV3Factory(UNIV3_FACTORY).createPool(poolKey.token0, poolKey.token1, poolKey.fee);
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);
        } else {
            (uint160 sqrtPriceX96Existing, , , , , , ) = IUniswapV3Pool(pool).slot0();
            if (sqrtPriceX96Existing == 0) {
                IUniswapV3Pool(pool).initialize(sqrtPriceX96);
            } else {
                require(sqrtPriceX96Existing == sqrtPriceX96, "UV3P");
            }
        }
    }

    function _cacheProject(
        address uniV3PoolAddress,
        address saleToken,
        address raiseToken,
        uint24 fee,
        uint160 initialPoolPriceX96,
        uint64 launchTime,
        uint64 refundDeadline
    ) internal {
        Project storage _project = _cachedProject[uniV3PoolAddress];
        require(_project.uniV3PoolAddress == address(0), "RE");

        _project.platformFee = PLATFORM_FEE;
        _project.performanceFee = PERFORMANCE_FEE;
        _project.admin = msg.sender;
        _project.saleToken = saleToken;
        _project.raiseToken = raiseToken;
        _project.fee = fee;
        _project.initialPoolPriceX96 = initialPoolPriceX96;
        _project.launchTime = launchTime;
        _project.refundDeadline = refundDeadline;
        _project.uniV3PoolAddress = uniV3PoolAddress;
        _project._cachedPoolKey = PoolAddress.getPoolKey(saleToken, raiseToken, fee);
    }

    /// @notice set platform fee for decrease liquidity. Platform fee is imutable among all project's pools
    function setPlatformFee(uint16 _platformFee) external onlyOwner() {
        PLATFORM_FEE = _platformFee;
    }

    /// @notice set platform fee for decrease liquidity. Platform fee is imutable among all project's pools
    function setPerformanceFee(uint16 _performanceFee) external onlyOwner() {
        PERFORMANCE_FEE = _performanceFee;
    }

    /// @notice set platform fee for decrease liquidity. Platform fee is imutable among all project's pools
    function setFeeTaker(address _feeTaker) external override onlyOwner() {
        FEE_TAKER = _feeTaker;
    }

    function setILOPoolImplementation(address iloPoolImplementation) external override onlyOwner() {
        emit PoolImplementationChanged(ILO_POOL_IMPLEMENTATION, iloPoolImplementation);
        ILO_POOL_IMPLEMENTATION = iloPoolImplementation;
    }

    function transferAdminProject(address admin, address uniV3Pool) external override onlyProjectAdmin(uniV3Pool) {
        Project storage _project = _cachedProject[uniV3Pool];
        _project.admin = admin;
        emit ProjectAdminChanged(uniV3Pool, msg.sender, admin);
    }

    function setDefaultDeadlineOffset(uint64 defaultDeadlineOffset) external override onlyOwner() {
        emit DefaultDeadlineOffsetChanged(owner(), DEFAULT_DEADLINE_OFFSET, defaultDeadlineOffset);
        DEFAULT_DEADLINE_OFFSET = defaultDeadlineOffset;
    }

    function setRefundDeadlineForProject(address uniV3Pool, uint64 refundDeadline) external override onlyOwner() {
        Project storage _project = _cachedProject[uniV3Pool];
        emit RefundDeadlineChanged(uniV3Pool, _project.refundDeadline, refundDeadline);
        _project.refundDeadline = refundDeadline;
    }

    /// @inheritdoc IILOManager
    function launch(address uniV3PoolAddress) external override {
        require(block.timestamp > _cachedProject[uniV3PoolAddress].launchTime, "LT");
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniV3PoolAddress).slot0();
        require(_cachedProject[uniV3PoolAddress].initialPoolPriceX96 == sqrtPriceX96, "UV3P");
        address[] memory initializedPools = _initializedILOPools[uniV3PoolAddress];
        require(initializedPools.length > 0, "NP");
        for (uint256 i = 0; i < initializedPools.length; i++) {
            IILOPool(initializedPools[i]).launch();
        }

        emit ProjectLaunch(uniV3PoolAddress);
    }

    /// @inheritdoc IILOManager
    function claimRefund(address uniV3PoolAddress) external override onlyProjectAdmin(uniV3PoolAddress) returns(uint256 totalRefundAmount) {
        require(_cachedProject[uniV3PoolAddress].refundDeadline < block.timestamp, "RFT");
        address[] memory initializedPools = _initializedILOPools[uniV3PoolAddress];
        for (uint256 i = 0; i < initializedPools.length; i++) {
            totalRefundAmount += IILOPool(initializedPools[i]).claimProjectRefund(_cachedProject[uniV3PoolAddress].admin);
        }
    }
}


// File: ILOPool.sol
// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint128.sol';
import '@uniswap/v3-core/contracts/libraries/FullMath.sol';

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';

import './interfaces/IILOPool.sol';
import './interfaces/IILOManager.sol';
import './libraries/PositionKey.sol';
import './libraries/SqrtPriceMathPartial.sol';
import './base/ILOVest.sol';
import './base/LiquidityManagement.sol';
import './base/ILOPoolImmutableState.sol';
import './base/Initializable.sol';
import './base/Multicall.sol';
import "./base/ILOWhitelist.sol";

/// @title NFT positions
/// @notice Wraps Uniswap V3 positions in the ERC721 non-fungible token interface
contract ILOPool is
    ERC721,
    IILOPool,
    ILOWhitelist,
    ILOVest,
    Initializable,
    Multicall,
    ILOPoolImmutableState,
    LiquidityManagement
{
    SaleInfo saleInfo;

    /// @dev when lauch successfully we can not refund anymore
    bool private _launchSucceeded;

    /// @dev when refund triggered, we can not launch anymore
    bool private _refundTriggered;

    /// @dev The token ID position data
    mapping(uint256 => Position) private _positions;
    VestingConfig[] private _vestingConfigs;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint256 private _nextId;
    uint256 totalRaised;
    constructor() ERC721('', '') {
        _disableInitialize();
    }

    function name() public pure override(ERC721, IERC721Metadata) returns (string memory) {
        return 'KRYSTAL ILOPool V1';
    }

    function symbol() public pure override(ERC721, IERC721Metadata) returns (string memory) {
        return 'KRYSTAL-ILO-V1';
    }

    function initialize(InitPoolParams calldata params) external override whenNotInitialized() {
        _nextId = 1;
        // initialize imutable state
        MANAGER = msg.sender;
        IILOManager.Project memory _project = IILOManager(MANAGER).project(params.uniV3Pool);

        WETH9 = IILOManager(MANAGER).WETH9();
        RAISE_TOKEN = _project.raiseToken;
        SALE_TOKEN = _project.saleToken;
        _cachedUniV3PoolAddress = params.uniV3Pool;
        _cachedPoolKey = _project._cachedPoolKey;
        TICK_LOWER = params.tickLower;
        TICK_UPPER = params.tickUpper;
        SQRT_RATIO_LOWER_X96 = params.sqrtRatioLowerX96;
        SQRT_RATIO_UPPER_X96 = params.sqrtRatioUpperX96;
        SQRT_RATIO_X96 = _project.initialPoolPriceX96;

        // rounding up to make sure that the number of sale token is enough for sale
        (uint256 maxSaleAmount,) = _saleAmountNeeded(params.hardCap);
        // initialize sale
        saleInfo = SaleInfo({
            hardCap: params.hardCap,
            softCap: params.softCap,
            maxCapPerUser: params.maxCapPerUser,
            start: params.start,
            end: params.end,
            maxSaleAmount: maxSaleAmount
        });

        _validateSharesAndVests(_project.launchTime, params.vestingConfigs);
        // initialize vesting
        for (uint256 index = 0; index < params.vestingConfigs.length; index++) {
            _vestingConfigs.push(params.vestingConfigs[index]);
        }

        emit ILOPoolInitialized(
            params.uniV3Pool,
            TICK_LOWER,
            TICK_UPPER,
            saleInfo,
            params.vestingConfigs
        );
    }

    /// @inheritdoc IILOPool
    function positions(uint256 tokenId)
        external
        view
        override
        returns (
            uint128 liquidity,
            uint256 raiseAmount,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128
        )
    {
        return (
            _positions[tokenId].liquidity,
            _positions[tokenId].raiseAmount,
            _positions[tokenId].feeGrowthInside0LastX128,
            _positions[tokenId].feeGrowthInside1LastX128
        );
    }

    /// @inheritdoc IILOSale
    function buy(uint256 raiseAmount, address recipient)
        external override 
        returns (
            uint256 tokenId,
            uint128 liquidityDelta
        )
    {
        require(_isWhitelisted(recipient), "UA");
        require(block.timestamp > saleInfo.start && block.timestamp < saleInfo.end, "ST");
        // check if raise amount over capacity
        require(saleInfo.hardCap - totalRaised >= raiseAmount, "HC");
        totalRaised += raiseAmount;

        require(totalSold() <= saleInfo.maxSaleAmount, "SA");

        // if investor already have a position, just increase raise amount and liquidity
        // otherwise, mint new nft for investor and assign vesting schedules
        if (balanceOf(recipient) == 0) {
            _mint(recipient, (tokenId = _nextId++));
            _positionVests[tokenId].schedule = _vestingConfigs[0].schedule;
        } else {
            tokenId = tokenOfOwnerByIndex(recipient, 0);
        }

        Position storage _position = _positions[tokenId];
        require(raiseAmount <= saleInfo.maxCapPerUser - _position.raiseAmount, "UC");
        _position.raiseAmount += raiseAmount;

        // get amount of liquidity associated with raise amount
        if (RAISE_TOKEN == _cachedPoolKey.token0) {
            liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(SQRT_RATIO_X96, SQRT_RATIO_UPPER_X96, raiseAmount);
        } else {
            liquidityDelta = LiquidityAmounts.getLiquidityForAmount1(SQRT_RATIO_LOWER_X96, SQRT_RATIO_X96, raiseAmount);
        }

        require(liquidityDelta > 0, "ZA");

        // calculate amount of share liquidity investor recieve by INVESTOR_SHARES config
        liquidityDelta = uint128(FullMath.mulDiv(liquidityDelta, _vestingConfigs[0].shares, BPS));
        
        // increase investor's liquidity
        _position.liquidity += liquidityDelta;

        // update total liquidity locked for vest and assiging vesing schedules
        _positionVests[tokenId].totalLiquidity = _position.liquidity;

        // transfer fund into contract
        TransferHelper.safeTransferFrom(RAISE_TOKEN, msg.sender, address(this), raiseAmount);

        emit Buy(recipient, tokenId, raiseAmount, liquidityDelta);
    }

    modifier isAuthorizedForToken(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId), 'UA');
        _;
    }

    /// @inheritdoc IILOPool
    function claim(uint256 tokenId)
        external
        payable
        override
        isAuthorizedForToken(tokenId)
        returns (uint256 amount0, uint256 amount1)
    {
        // only can claim if the launch is successfully
        require(_launchSucceeded, "PNL");

        // calculate amount of unlocked liquidity for the position
        uint128 liquidity2Claim = _claimableLiquidity(tokenId);
        IUniswapV3Pool pool = IUniswapV3Pool(_cachedUniV3PoolAddress);
        Position storage position = _positions[tokenId];
        {
            IILOManager.Project memory _project = IILOManager(MANAGER).project(address(pool));

            uint128 positionLiquidity = position.liquidity;
            require(positionLiquidity >= liquidity2Claim);

            // get amount of token0 and token1 that pool will return for us
            (amount0, amount1) = pool.burn(TICK_LOWER, TICK_UPPER, liquidity2Claim);

            // get amount of token0 and token1 after deduct platform fee
            (amount0, amount1) = _deductFees(amount0, amount1, _project.platformFee);

            bytes32 positionKey = PositionKey.compute(address(this), TICK_LOWER, TICK_UPPER);

            // calculate amount of fees that position generated
            (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);
            uint256 fees0 = FullMath.mulDiv(
                                feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                                positionLiquidity,
                                FixedPoint128.Q128
                            );
            
            uint256 fees1 = FullMath.mulDiv(
                                feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                                positionLiquidity,
                                FixedPoint128.Q128
                            );

            // amount of fees after deduct performance fee
            (fees0, fees1) = _deductFees(fees0, fees1, _project.performanceFee);

            // fees is combined with liquidity token amount to return to the user
            amount0 += fees0;
            amount1 += fees1;

            position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
            position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;

            // subtraction is safe because we checked positionLiquidity is gte liquidity2Claim
            position.liquidity = positionLiquidity - liquidity2Claim;
            emit DecreaseLiquidity(tokenId, liquidity2Claim, amount0, amount1);

        }
        // real amount collected from uintswap pool
        (uint128 amountCollected0, uint128 amountCollected1) = pool.collect(
            address(this),
            TICK_LOWER,
            TICK_UPPER,
            type(uint128).max,
            type(uint128).max
        );
        emit Collect(tokenId, address(this), amountCollected0, amountCollected1);

        // transfer token for user
        TransferHelper.safeTransfer(_cachedPoolKey.token0, ownerOf(tokenId), amount0);
        TransferHelper.safeTransfer(_cachedPoolKey.token1, ownerOf(tokenId), amount1);

        emit Claim(ownerOf(tokenId), tokenId,liquidity2Claim, amount0, amount1, position.feeGrowthInside0LastX128, position.feeGrowthInside1LastX128);

        address feeTaker = IILOManager(MANAGER).FEE_TAKER();
        // transfer fee to fee taker
        TransferHelper.safeTransfer(_cachedPoolKey.token0, feeTaker, amountCollected0-amount0);
        TransferHelper.safeTransfer(_cachedPoolKey.token1, feeTaker, amountCollected1-amount1);
    }

    modifier OnlyManager() {
        require(msg.sender == MANAGER, "UA");
        _;
    }

    /// @inheritdoc IILOPool
    function launch() external override OnlyManager() {
        require(!_launchSucceeded, "PL");
        // when refund triggered, we can not launch pool anymore
        require(!_refundTriggered, "IRF");
        // make sure that soft cap requirement match
        require(totalRaised >= saleInfo.softCap, "SC");
        uint128 liquidity;
        address uniV3PoolAddress = _cachedUniV3PoolAddress;
        {
            uint256 amount0;
            uint256 amount1;
            uint256 amount0Min;
            uint256 amount1Min;
            address token0Addr = _cachedPoolKey.token0;

            // calculate sale amount of tokens needed for launching pool
            if (token0Addr == RAISE_TOKEN) {
                amount0 = totalRaised;
                amount0Min = totalRaised;
                (amount1, liquidity) = _saleAmountNeeded(totalRaised);
            } else {
                (amount0, liquidity) = _saleAmountNeeded(totalRaised);
                amount1 = totalRaised;
                amount1Min = totalRaised;
            }

            // actually deploy liquidity to uniswap pool
            (amount0, amount1) = addLiquidity(AddLiquidityParams({
                pool: IUniswapV3Pool(uniV3PoolAddress),
                liquidity: liquidity,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: amount0Min,
                amount1Min: amount1Min
            }));

            emit PoolLaunch(uniV3PoolAddress, liquidity, amount0, amount1);
        }

        IILOManager.Project memory _project = IILOManager(MANAGER).project(uniV3PoolAddress);

        // assigning vests for the project configuration
        for (uint256 index = 1; index < _vestingConfigs.length; index++) {
            uint256 tokenId;
            VestingConfig memory projectConfig = _vestingConfigs[index];
            // mint nft for recipient
            _mint(projectConfig.recipient, (tokenId = _nextId++));
            uint128 liquidityShares = uint128(FullMath.mulDiv(liquidity, projectConfig.shares, BPS));

            Position storage _position = _positions[tokenId];
            _position.liquidity = liquidityShares;
            _positionVests[tokenId].totalLiquidity = liquidityShares;

            // assign vesting schedule
            LinearVest[] storage schedule = _positionVests[tokenId].schedule;
            for (uint256 i = 0; i < projectConfig.schedule.length; i++) {
                schedule.push(projectConfig.schedule[i]);
            }

            emit Buy(projectConfig.recipient, tokenId, 0, liquidityShares);
        }

        // transfer back leftover sale token to project admin
        _refundProject(_project.admin);

        _launchSucceeded = true;
    }

    modifier refundable() {
        if (!_refundTriggered) {
            // if ilo pool is lauch sucessfully, we can not refund anymore
            require(!_launchSucceeded, "PL");
            IILOManager.Project memory _project = IILOManager(MANAGER).project(_cachedUniV3PoolAddress);
            require(block.timestamp >= _project.refundDeadline, "RFT");

            _refundTriggered = true;
        }
        _;
    }

    /// @inheritdoc IILOPool
    function claimRefund(uint256 tokenId) external override refundable() isAuthorizedForToken(tokenId) {
        uint256 refundAmount = _positions[tokenId].raiseAmount;
        address tokenOwner = ownerOf(tokenId);

        delete _positions[tokenId];
        delete _positionVests[tokenId];
        _burn(tokenId);

        TransferHelper.safeTransfer(RAISE_TOKEN, tokenOwner, refundAmount);
        emit UserRefund(tokenOwner, tokenId,refundAmount);
    }

    /// @inheritdoc IILOPool
    function claimProjectRefund(address projectAdmin) external override refundable() OnlyManager() returns(uint256 refundAmount) {
        return _refundProject(projectAdmin);
    }

    function _refundProject(address projectAdmin) internal returns (uint256 refundAmount) {
        refundAmount = IERC20(SALE_TOKEN).balanceOf(address(this));
        if (refundAmount > 0) {
            TransferHelper.safeTransfer(SALE_TOKEN, projectAdmin, refundAmount);
            emit ProjectRefund(projectAdmin, refundAmount);
        }
    }

    /// @inheritdoc IILOSale
    function totalSold() public view override returns (uint256 _totalSold) {
        (_totalSold,) =_saleAmountNeeded(totalRaised);
    }

    /// @notice return sale token amount needed for the raiseAmount.
    /// @dev sale token amount is rounded up
    function _saleAmountNeeded(uint256 raiseAmount) internal view returns (
        uint256 saleAmountNeeded,
        uint128 liquidity
    ) {
        if (raiseAmount == 0) return (0, 0);

        if (_cachedPoolKey.token0 == SALE_TOKEN) {
            // liquidity1 raised
            liquidity = LiquidityAmounts.getLiquidityForAmount1(SQRT_RATIO_LOWER_X96, SQRT_RATIO_X96, raiseAmount);
            saleAmountNeeded = SqrtPriceMathPartial.getAmount0Delta(SQRT_RATIO_X96, SQRT_RATIO_UPPER_X96, liquidity, true);
        } else {
            // liquidity0 raised
            liquidity = LiquidityAmounts.getLiquidityForAmount0(SQRT_RATIO_X96, SQRT_RATIO_UPPER_X96, raiseAmount);
            saleAmountNeeded = SqrtPriceMathPartial.getAmount1Delta(SQRT_RATIO_LOWER_X96, SQRT_RATIO_X96, liquidity, true);
        }
    }

    /// @inheritdoc ILOVest
    function _unlockedLiquidity(uint256 tokenId) internal view override returns (uint128 liquidityUnlocked) {
        PositionVest storage _positionVest = _positionVests[tokenId];
        LinearVest[] storage vestingSchedule = _positionVest.schedule;
        uint128 totalLiquidity = _positionVest.totalLiquidity;

        for (uint256 index = 0; index < vestingSchedule.length; index++) {

            LinearVest storage vest = vestingSchedule[index];

            // if vest is not started, skip this vest and all following vest
            if (block.timestamp < vest.start) {
                break;
            }

            // if vest already end, all the shares are unlocked
            // otherwise we calculate shares of unlocked times and get the unlocked share number
            // all vest after current unlocking vest is ignored
            if (vest.end < block.timestamp) {
                liquidityUnlocked += uint128(FullMath.mulDiv(
                    vest.shares, 
                    totalLiquidity, 
                    BPS
                ));
            } else {
                liquidityUnlocked += uint128(FullMath.mulDiv(
                    vest.shares * totalLiquidity, 
                    block.timestamp - vest.start, 
                    (vest.end - vest.start) * BPS
                ));
            }
        }
    }

    /// @notice calculate the amount left after deduct fee
    /// @param amount0 the amount of token0 before deduct fee
    /// @param amount1 the amount of token1 before deduct fee
    /// @return amount0Left the amount of token0 after deduct fee
    /// @return amount1Left the amount of token1 after deduct fee
    function _deductFees(uint256 amount0, uint256 amount1, uint16 feeBPS) internal pure 
        returns (
            uint256 amount0Left, 
            uint256 amount1Left
        ) {
        amount0Left = amount0 - FullMath.mulDiv(amount0, feeBPS, BPS);
        amount1Left = amount1 - FullMath.mulDiv(amount1, feeBPS, BPS);
    }

    /// @inheritdoc IILOVest
    function vestingStatus(uint256 tokenId) external view override returns (
        uint128 unlockedLiquidity,
        uint128 claimedLiquidity
    ) {
        unlockedLiquidity = _unlockedLiquidity(tokenId);
        claimedLiquidity = _positionVests[tokenId].totalLiquidity - _positions[tokenId].liquidity;
    }

    /// @inheritdoc ILOVest
    function _claimableLiquidity(uint256 tokenId) internal view override returns (uint128) {
        uint128 liquidityClaimed = _positionVests[tokenId].totalLiquidity - _positions[tokenId].liquidity;
        uint128 liquidityUnlocked = _unlockedLiquidity(tokenId);
        return liquidityClaimed < liquidityUnlocked ? liquidityUnlocked - liquidityClaimed : 0;
    }

    modifier onlyProjectAdmin() override {
        IILOManager.Project memory _project = IILOManager(MANAGER).project(_cachedUniV3PoolAddress);
        require(msg.sender == _project.admin, "UA");
        _;
    }

}


// File: ILOPoolImmutableState.sol
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import '../interfaces/IILOPoolImmutableState.sol';
import '../libraries/PoolAddress.sol';

/// @title Immutable state
/// @notice Immutable state used by periphery contracts
abstract contract ILOPoolImmutableState is IILOPoolImmutableState {
    /// @inheritdoc IILOPoolImmutableState
    address public override WETH9;

    uint16 constant BPS = 10000;
    address public override MANAGER;
    address public override RAISE_TOKEN;
    address public override SALE_TOKEN;
    int24 public override TICK_LOWER;
    int24 public override TICK_UPPER;
    uint160 public override SQRT_RATIO_X96;
    uint160 internal SQRT_RATIO_LOWER_X96;
    uint160 internal SQRT_RATIO_UPPER_X96;

    PoolAddress.PoolKey internal _cachedPoolKey;
    address internal _cachedUniV3PoolAddress;
}


// File: ILOVest.sol
// SPDX-License-Identifier: BUSL-1.1 

pragma solidity =0.7.6;

import '../interfaces/IILOVest.sol';

abstract contract ILOVest is IILOVest {
    mapping(uint256=>PositionVest) _positionVests;

    /// @notice calculate amount of liquidity unlocked for claim
    /// @param tokenId nft token id of position
    /// @return liquidityUnlocked amount of unlocked liquidity
    function _unlockedLiquidity(uint256 tokenId) internal view virtual returns (uint128 liquidityUnlocked);

    function _claimableLiquidity(uint256 tokenId) internal view virtual returns (uint128 claimableLiquidity);

    function _validateSharesAndVests(uint64 launchTime, VestingConfig[] memory vestingConfigs) internal pure {
        uint16 totalShares;
        uint16 BPS = 10000;
        for (uint256 i = 0; i < vestingConfigs.length; i++) {
            if (i == 0) {
                require (vestingConfigs[i].recipient == address(0), "VR");
            } else {
                require(vestingConfigs[i].recipient != address(0), "VR");
            }
            // we need to subtract fist in order to avoid int overflow
            require(BPS - totalShares >= vestingConfigs[i].shares, "TS");
            _validateVestSchedule(launchTime, vestingConfigs[i].schedule);
            totalShares += vestingConfigs[i].shares;
        }
        // total shares should be exactly equal BPS
        require(totalShares == BPS, "TS");
    }

    function _validateVestSchedule(uint64 launchTime, LinearVest[] memory schedule) internal pure {
        require(schedule[0].start >= launchTime, "VT");
        uint16 BPS = 10000;
        uint16 totalShares;
        uint64 lastEnd;
        uint256 scheduleLength = schedule.length;
        for (uint256 i = 0; i < scheduleLength; i++) {
            // vesting schedule must not overlap
            require(schedule[i].start >= lastEnd, "VT");
            lastEnd = schedule[i].end;
            // we need to subtract fist in order to avoid int overflow
            require(BPS - totalShares >= schedule[i].shares, "VS");
            totalShares += schedule[i].shares;
        }
        // total shares should be exactly equal BPS
        require(totalShares == BPS, "VS");
    }
}


// File: ILOWhitelist.sol
// SPDX-License-Identifier: BUSL-1.1 

pragma solidity =0.7.6;

import '@openzeppelin/contracts/utils/EnumerableSet.sol';
import '../interfaces/IILOWhitelist.sol';

abstract contract ILOWhitelist is IILOWhitelist {
    bool private _openToAll;

    /// @inheritdoc IILOWhitelist
    function setOpenToAll(bool openToAll) external override onlyProjectAdmin{
        _setOpenToAll(openToAll);
    }

    /// @inheritdoc IILOWhitelist
    function isOpenToAll() external override view returns(bool) {
        return _openToAll;
    }

    /// @inheritdoc IILOWhitelist
    function isWhitelisted(address user) external override view returns (bool) {
        return _isWhitelisted(user);
    }

    /// @inheritdoc IILOWhitelist
    function batchWhitelist(address[] calldata users) external override onlyProjectAdmin{
        for (uint256 i = 0; i < users.length; i++) {
            _setWhitelist(users[i]);
        }
    }

    /// @inheritdoc IILOWhitelist
    function batchRemoveWhitelist(address[] calldata users) external override onlyProjectAdmin{
        for (uint256 i = 0; i < users.length; i++) {
            _removeWhitelist(users[i]);
        }
    }

    EnumerableSet.AddressSet private _whitelisted;

    function _setOpenToAll(bool openToAll) internal {
        _openToAll = openToAll;
        emit SetOpenToAll(openToAll);
    }

    function _removeWhitelist(address user) internal {
        EnumerableSet.remove(_whitelisted, user);
        emit SetWhitelist(user, false);
    }

    function _setWhitelist(address user) internal {
        EnumerableSet.add(_whitelisted, user);
        emit SetWhitelist(user, true);
    }

    function _isWhitelisted(address user) internal view returns(bool) {
        return _openToAll || EnumerableSet.contains(_whitelisted, user);
    }
}


// File: LiquidityManagement.sol
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';

import '../libraries/PoolAddress.sol';
import '../libraries/LiquidityAmounts.sol';

import './PeripheryPayments.sol';
import './ILOPoolImmutableState.sol';

/// @title Liquidity management functions
/// @notice Internal functions for safely managing liquidity in Uniswap V3
abstract contract LiquidityManagement is IUniswapV3MintCallback, ILOPoolImmutableState, PeripheryPayments {
    /// @inheritdoc IUniswapV3MintCallback
    /// @dev as we modified nfpm, user dont need to pay at this step. so data is empty
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        require(msg.sender == _cachedUniV3PoolAddress);

        if (amount0Owed > 0) pay(_cachedPoolKey.token0, address(this), msg.sender, amount0Owed);
        if (amount1Owed > 0) pay(_cachedPoolKey.token1, address(this), msg.sender, amount1Owed);
    }

    struct AddLiquidityParams {
        IUniswapV3Pool pool;
        uint128 liquidity;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    /// @notice Add liquidity to an initialized pool
    function addLiquidity(AddLiquidityParams memory params)
        internal
        returns (
            uint256 amount0,
            uint256 amount1
        )
    {
        (amount0, amount1) = params.pool.mint(
            address(this),
            TICK_LOWER,
            TICK_UPPER,
            params.liquidity,
            ""
        );

        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, 'Price slippage check');
    }
}


// File: Initializable.sol
// SPDX-License-Identifier: BUSL-1.1 

pragma solidity =0.7.6;

abstract contract Initializable {
    bool private _initialized;
    function _disableInitialize() internal {
        _initialized = true;
    }
    modifier whenNotInitialized() {
        require(!_initialized);
        _;
        _initialized = true;
    }
    modifier afterInitialize() {
        require(_initialized);
        _;
    }
}

// File: Multicall.sol
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '../interfaces/IMulticall.sol';

/// @title Multicall
/// @notice Enables calling multiple methods in a single call to the contract
abstract contract Multicall is IMulticall {
    /// @inheritdoc IMulticall
    function multicall(bytes[] calldata data) public payable override returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }
}


// File: PeripheryPayments.sol
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '../interfaces/external/IWETH9.sol';

import '../libraries/TransferHelper.sol';

import './ILOPoolImmutableState.sol';

abstract contract PeripheryPayments is ILOPoolImmutableState {
    receive() external payable {
        require(msg.sender == WETH9, 'Not WETH9');
    }

    /// @param token The token to pay
    /// @param payer The entity that must pay
    /// @param recipient The entity that will receive payment
    /// @param value The amount to pay
    function pay(
        address token,
        address payer,
        address recipient,
        uint256 value
    ) internal {
        if (token == WETH9 && address(this).balance >= value) {
            // pay with WETH9
            IWETH9(WETH9).deposit{value: value}(); // wrap only what is needed to pay
            IWETH9(WETH9).transfer(recipient, value);
        } else if (payer == address(this)) {
            // pay with tokens already in the contract (for the exact input multihop case)
            TransferHelper.safeTransfer(token, recipient, value);
        } else {
            // pull payment
            TransferHelper.safeTransferFrom(token, payer, recipient, value);
        }
    }
}


// File: ChainId.sol
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.0;

/// @title Function for getting the current chain ID
library ChainId {
    /// @dev Gets the current chain ID
    /// @return chainId The current chain ID
    function get() internal pure returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }
}


// File: LiquidityAmounts.sol
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import '@uniswap/v3-core/contracts/libraries/FullMath.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol';
import '@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol';

/// @title Liquidity amount functions
/// @notice Provides functions for computing liquidity amounts from token amounts and prices
library LiquidityAmounts {
    /// @notice Downcasts uint256 to uint128
    /// @param x The uint258 to be downcasted
    /// @return y The passed value, downcasted to uint128
    function toUint128(uint256 x) private pure returns (uint128 y) {
        require((y = uint128(x)) == x);
    }

    /// @notice Computes the amount of liquidity received for a given amount of token0 and price range
    /// @dev Calculates amount0 * (sqrt(upper) * sqrt(lower)) / (sqrt(upper) - sqrt(lower))
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param amount0 The amount0 being sent in
    /// @return liquidity The amount of returned liquidity
    function getLiquidityForAmount0(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        uint256 intermediate = FullMath.mulDiv(sqrtRatioAX96, sqrtRatioBX96, FixedPoint96.Q96);
        return toUint128(FullMath.mulDiv(amount0, intermediate, sqrtRatioBX96 - sqrtRatioAX96));
    }

    /// @notice Computes the amount of liquidity received for a given amount of token1 and price range
    /// @dev Calculates amount1 / (sqrt(upper) - sqrt(lower)).
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param amount1 The amount1 being sent in
    /// @return liquidity The amount of returned liquidity
    function getLiquidityForAmount1(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        return toUint128(FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtRatioBX96 - sqrtRatioAX96));
    }

    /// @notice Computes the amount of token0 for a given amount of liquidity and a price range
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param liquidity The liquidity being valued
    /// @return amount0 The amount of token0
    function getAmount0ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return
            FullMath.mulDiv(
                uint256(liquidity) << FixedPoint96.RESOLUTION,
                sqrtRatioBX96 - sqrtRatioAX96,
                sqrtRatioBX96
            ) / sqrtRatioAX96;
    }

    /// @notice Computes the amount of token1 for a given amount of liquidity and a price range
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param liquidity The liquidity being valued
    /// @return amount1 The amount of token1
    function getAmount1ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
    }
}


// File: PoolAddress.sol
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Provides functions for deriving a pool address from the factory, tokens, and the fee
library PoolAddress {
    bytes32 internal constant POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    /// @notice The identifying key of the pool
    struct PoolKey {
        address token0;
        address token1;
        uint24 fee;
    }

    /// @notice Returns PoolKey: the ordered tokens with the matched fee levels
    /// @param tokenA The first token of a pool, unsorted
    /// @param tokenB The second token of a pool, unsorted
    /// @param fee The fee level of the pool
    /// @return Poolkey The pool details with ordered token0 and token1 assignments
    function getPoolKey(
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal pure returns (PoolKey memory) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey({token0: tokenA, token1: tokenB, fee: fee});
    }

    /// @notice Deterministically computes the pool address given the factory and PoolKey
    /// @param factory The Uniswap V3 factory contract address
    /// @param key The PoolKey
    /// @return pool The contract address of the V3 pool
    function computeAddress(address factory, PoolKey memory key) internal pure returns (address pool) {
        require(key.token0 < key.token1);
        pool = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex'ff',
                        factory,
                        keccak256(abi.encode(key.token0, key.token1, key.fee)),
                        POOL_INIT_CODE_HASH
                    )
                )
            )
        );
    }
}


// File: PositionKey.sol
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

library PositionKey {
    /// @dev Returns the key of the position in the core library
    function compute(
        address owner,
        int24 tickLower,
        int24 tickUpper
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, tickLower, tickUpper));
    }
}


// File: SqrtPriceMathPartial.sol
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import '@uniswap/v3-core/contracts/libraries/FullMath.sol';
import '@uniswap/v3-core/contracts/libraries/UnsafeMath.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol';

/// @title Functions based on Q64.96 sqrt price and liquidity
/// @notice Exposes two functions from @uniswap/v3-core SqrtPriceMath
/// that use square root of price as a Q64.96 and liquidity to compute deltas
library SqrtPriceMathPartial {
    /// @notice Gets the amount0 delta between two prices
    /// @dev Calculates liquidity / sqrt(lower) - liquidity / sqrt(upper),
    /// i.e. liquidity * (sqrt(upper) - sqrt(lower)) / (sqrt(upper) * sqrt(lower))
    /// @param sqrtRatioAX96 A sqrt price
    /// @param sqrtRatioBX96 Another sqrt price
    /// @param liquidity The amount of usable liquidity
    /// @param roundUp Whether to round the amount up or down
    /// @return amount0 Amount of token0 required to cover a position of size liquidity between the two passed prices
    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;
        uint256 numerator2 = sqrtRatioBX96 - sqrtRatioAX96;

        require(sqrtRatioAX96 > 0);

        return
            roundUp
                ? UnsafeMath.divRoundingUp(
                    FullMath.mulDivRoundingUp(numerator1, numerator2, sqrtRatioBX96),
                    sqrtRatioAX96
                )
                : FullMath.mulDiv(numerator1, numerator2, sqrtRatioBX96) / sqrtRatioAX96;
    }

    /// @notice Gets the amount1 delta between two prices
    /// @dev Calculates liquidity * (sqrt(upper) - sqrt(lower))
    /// @param sqrtRatioAX96 A sqrt price
    /// @param sqrtRatioBX96 Another sqrt price
    /// @param liquidity The amount of usable liquidity
    /// @param roundUp Whether to round the amount up, or down
    /// @return amount1 Amount of token1 required to cover a position of size liquidity between the two passed prices
    function getAmount1Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return
            roundUp
                ? FullMath.mulDivRoundingUp(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96)
                : FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
    }
}


// File: TransferHelper.sol
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

library TransferHelper {
    /// @notice Transfers tokens from the targeted address to the given destination
    /// @notice Errors with 'STF' if transfer fails
    /// @param token The contract address of the token to be transferred
    /// @param from The originating address from which the tokens will be transferred
    /// @param to The destination address of the transfer
    /// @param value The amount to be transferred
    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'STF');
    }

    /// @notice Transfers tokens from msg.sender to a recipient
    /// @dev Errors with ST if transfer fails
    /// @param token The contract address of the token which will be transferred
    /// @param to The recipient of the transfer
    /// @param value The value of the transfer
    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'ST');
    }

    /// @notice Approves the stipulated contract to spend the given allowance in the given token
    /// @dev Errors with 'SA' if transfer fails
    /// @param token The contract address of the token to be approved
    /// @param to The target of the approval
    /// @param value The amount of the given token the target will be allowed to spend
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'SA');
    }

    /// @notice Transfers ETH to the recipient address
    /// @dev Fails with `STE`
    /// @param to The destination of the transfer
    /// @param value The value to be transferred
    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'STE');
    }
}
```