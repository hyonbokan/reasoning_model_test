// File: Authorization.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "./AuthorizationBase.sol";

contract Authorization is AuthorizationBase {
    IRoleManager internal immutable __roleManager;

    constructor(IRoleManager roleManager) {
        __roleManager = roleManager;
    }

    function _roleManager() internal view override returns (IRoleManager) {
        return __roleManager;
    }
}


// File: RoleManager.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../../interfaces/IAddressProvider.sol";
import "../../interfaces/IRoleManager.sol";

import "../../libraries/Roles.sol";
import "../../libraries/Errors.sol";
import "../../libraries/AddressProviderKeys.sol";
import "../../libraries/UncheckedMath.sol";

contract RoleManager is IRoleManager {
    using UncheckedMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct RoleData {
        mapping(address => bool) members;
        bytes32 adminRole;
    }
    mapping(bytes32 => RoleData) private _roles;
    mapping(bytes32 => EnumerableSet.AddressSet) private _roleMembers;

    IAddressProvider public immutable addressProvider;

    modifier onlyGovernance() {
        require(hasRole(Roles.GOVERNANCE, msg.sender), Error.UNAUTHORIZED_ACCESS);
        _;
    }

    constructor(IAddressProvider _addressProvider) {
        addressProvider = _addressProvider;
        _grantRole(Roles.GOVERNANCE, msg.sender);
    }

    function grantRole(bytes32 role, address account) external override onlyGovernance {
        _grantRole(role, account);
    }

    function addGovernor(address newGovernor) external override onlyGovernance {
        _grantRole(Roles.GOVERNANCE, newGovernor);
    }

    function renounceGovernance() external override onlyGovernance {
        require(getRoleMemberCount(Roles.GOVERNANCE) > 1, Error.CANNOT_REVOKE_ROLE);
        _revokeRole(Roles.GOVERNANCE, msg.sender);
    }

    function addGaugeZap(address zap) external override onlyGovernance {
        _grantRole(Roles.GAUGE_ZAP, zap);
    }

    function removeGaugeZap(address zap) external override onlyGovernance {
        revokeRole(Roles.GAUGE_ZAP, zap);
    }

    function hasAnyRole(
        bytes32 role1,
        bytes32 role2,
        address account
    ) external view returns (bool) {
        return hasRole(role1, account) || hasRole(role2, account);
    }

    function hasAnyRole(
        bytes32 role1,
        bytes32 role2,
        bytes32 role3,
        address account
    ) external view returns (bool) {
        return hasRole(role1, account) || hasRole(role2, account) || hasRole(role3, account);
    }

    function hasAnyRole(bytes32[] calldata roles, address account)
        external
        view
        virtual
        override
        returns (bool)
    {
        for (uint256 i; i < roles.length; i = i.uncheckedInc()) {
            if (hasRole(roles[i], account)) {
                return true;
            }
        }
        return false;
    }

    function getRoleMember(bytes32 role, uint256 index)
        external
        view
        virtual
        override
        returns (address)
    {
        if (role == Roles.ADDRESS_PROVIDER && index == 0) {
            return address(addressProvider);
        } else if (role == Roles.POOL_FACTORY && index == 0) {
            return addressProvider.getAddress(AddressProviderKeys._POOL_FACTORY_KEY);
        } else if (role == Roles.CONTROLLER && index == 0) {
            return addressProvider.getAddress(AddressProviderKeys._CONTROLLER_KEY);
        } else if (role == Roles.POOL) {
            return addressProvider.getPoolAtIndex(index);
        } else if (role == Roles.VAULT) {
            return addressProvider.getVaultAtIndex(index);
        }
        return _roleMembers[role].at(index);
    }

    function revokeRole(bytes32 role, address account) public onlyGovernance {
        require(role != Roles.GOVERNANCE, Error.CANNOT_REVOKE_ROLE);
        require(hasRole(role, account), Error.INVALID_ARGUMENT);
        _revokeRole(role, account);
    }

    function getRoleMemberCount(bytes32 role) public view virtual override returns (uint256) {
        if (
            role == Roles.ADDRESS_PROVIDER || role == Roles.POOL_FACTORY || role == Roles.CONTROLLER
        ) {
            return 1;
        }
        if (role == Roles.POOL) {
            return addressProvider.poolsCount();
        }
        if (role == Roles.VAULT) {
            return addressProvider.vaultsCount();
        }
        return _roleMembers[role].length();
    }

    function hasRole(bytes32 role, address account) public view virtual override returns (bool) {
        if (role == Roles.ADDRESS_PROVIDER) {
            return account == address(addressProvider);
        } else if (role == Roles.POOL_FACTORY) {
            return
                account == addressProvider.getAddress(AddressProviderKeys._POOL_FACTORY_KEY, false);
        } else if (role == Roles.CONTROLLER) {
            return
                account == addressProvider.getAddress(AddressProviderKeys._CONTROLLER_KEY, false);
        } else if (role == Roles.MAINTENANCE) {
            return _roles[role].members[account] || _roles[Roles.GOVERNANCE].members[account];
        } else if (role == Roles.POOL) {
            return addressProvider.isPool(account);
        } else if (role == Roles.VAULT) {
            return addressProvider.isVault(account);
        }
        return _roles[role].members[account];
    }

    function _grantRole(bytes32 role, address account) internal {
        _roles[role].members[account] = true;
        _roleMembers[role].add(account);
        emit RoleGranted(role, account, msg.sender);
    }

    function _revokeRole(bytes32 role, address account) internal {
        _roles[role].members[account] = false;
        _roleMembers[role].remove(account);
        emit RoleRevoked(role, account, msg.sender);
    }
}


// File: AddressProvider.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IGasBank.sol";
import "../interfaces/IAddressProvider.sol";
import "../interfaces/IStakerVault.sol";
import "../interfaces/oracles/IOracleProvider.sol";

import "../libraries/EnumerableExtensions.sol";
import "../libraries/EnumerableMapping.sol";
import "../libraries/AddressProviderKeys.sol";
import "../libraries/AddressProviderMeta.sol";
import "../libraries/Roles.sol";

import "./access/AuthorizationBase.sol";
import "./utils/Preparable.sol";

// solhint-disable ordering

contract AddressProvider is IAddressProvider, AuthorizationBase, Initializable, Preparable {
    using EnumerableMapping for EnumerableMapping.AddressToAddressMap;
    using EnumerableMapping for EnumerableMapping.Bytes32ToUIntMap;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableExtensions for EnumerableSet.AddressSet;
    using EnumerableExtensions for EnumerableSet.Bytes32Set;
    using EnumerableExtensions for EnumerableMapping.AddressToAddressMap;
    using EnumerableExtensions for EnumerableMapping.Bytes32ToUIntMap;
    using AddressProviderMeta for AddressProviderMeta.Meta;

    // LpToken -> stakerVault
    EnumerableMapping.AddressToAddressMap internal _stakerVaults;

    EnumerableSet.AddressSet internal _whiteListedFeeHandlers;

    // value is encoded as (bool freezable, bool frozen)
    EnumerableMapping.Bytes32ToUIntMap internal _addressKeyMetas;

    EnumerableSet.AddressSet internal _actions; // list of all actions ever registered

    EnumerableSet.AddressSet internal _vaults; // list of all active vaults

    EnumerableMapping.AddressToAddressMap internal _tokenToPools;

    constructor(address treasury) {
        AddressProviderMeta.Meta memory meta = AddressProviderMeta.Meta(true, false);
        _addressKeyMetas.set(AddressProviderKeys._TREASURY_KEY, meta.toUInt());
        _setConfig(AddressProviderKeys._TREASURY_KEY, treasury);
    }

    function initialize(address roleManager) external initializer {
        AddressProviderMeta.Meta memory meta = AddressProviderMeta.Meta(true, true);
        _addressKeyMetas.set(AddressProviderKeys._ROLE_MANAGER_KEY, meta.toUInt());
        _setConfig(AddressProviderKeys._ROLE_MANAGER_KEY, roleManager);
    }

    function getKnownAddressKeys() external view override returns (bytes32[] memory) {
        return _addressKeyMetas.keysArray();
    }

    function addFeeHandler(address feeHandler) external override onlyGovernance returns (bool) {
        require(!_whiteListedFeeHandlers.contains(feeHandler), Error.ADDRESS_WHITELISTED);
        _whiteListedFeeHandlers.add(feeHandler);
        emit FeeHandlerAdded(feeHandler);
        return true;
    }

    function removeFeeHandler(address feeHandler) external override onlyGovernance returns (bool) {
        require(_whiteListedFeeHandlers.contains(feeHandler), Error.ADDRESS_NOT_WHITELISTED);
        _whiteListedFeeHandlers.remove(feeHandler);
        emit FeeHandlerRemoved(feeHandler);
        return true;
    }

    /**
     * @notice Adds action.
     * @param action Address of action to add.
     */
    function addAction(address action) external override onlyGovernance returns (bool) {
        bool result = _actions.add(action);
        if (result) {
            emit ActionListed(action);
        }
        return result;
    }

    /**
     * @notice Adds pool.
     * @param pool Address of pool to add.
     */
    function addPool(address pool)
        external
        override
        onlyRoles2(Roles.POOL_FACTORY, Roles.GOVERNANCE)
    {
        require(pool != address(0), Error.ZERO_ADDRESS_NOT_ALLOWED);

        ILiquidityPool ipool = ILiquidityPool(pool);
        address poolToken = ipool.getLpToken();
        require(poolToken != address(0), Error.ZERO_ADDRESS_NOT_ALLOWED);
        if (_tokenToPools.set(poolToken, pool)) {
            address vault = address(ipool.getVault());
            if (vault != address(0)) {
                _vaults.add(vault);
            }
            emit PoolListed(pool);
        }
    }

    /**
     * @notice Delists pool.
     * @param pool Address of pool to delist.
     * @return `true` if successful.
     */
    function removePool(address pool) external override onlyRole(Roles.CONTROLLER) returns (bool) {
        address lpToken = ILiquidityPool(pool).getLpToken();
        bool removed = _tokenToPools.remove(lpToken);
        if (removed) {
            address vault = address(ILiquidityPool(pool).getVault());
            if (vault != address(0)) {
                _vaults.remove(vault);
            }
            emit PoolDelisted(pool);
        }

        return removed;
    }

    /** Vault functions  */

    /**
     * @notice returns all the registered vaults
     */
    function allVaults() external view override returns (address[] memory) {
        return _vaults.toArray();
    }

    /**
     * @notice returns the vault at the given index
     */
    function getVaultAtIndex(uint256 index) external view override returns (address) {
        return _vaults.at(index);
    }

    /**
     * @notice returns the number of vaults
     */
    function vaultsCount() external view override returns (uint256) {
        return _vaults.length();
    }

    function isVault(address vault) external view override returns (bool) {
        return _vaults.contains(vault);
    }

    function updateVault(address previousVault, address newVault)
        external
        override
        onlyRole(Roles.POOL)
    {
        if (previousVault != address(0)) {
            _vaults.remove(previousVault);
        }
        if (newVault != address(0)) {
            _vaults.add(newVault);
        }
        emit VaultUpdated(previousVault, newVault);
    }

    /**
     * @notice Returns the address for the given key
     */
    function getAddress(bytes32 key) public view override returns (address) {
        require(_addressKeyMetas.contains(key), Error.ADDRESS_DOES_NOT_EXIST);
        return currentAddresses[key];
    }

    /**
     * @notice Returns the address for the given key
     * @dev if `checkExists` is true, it will fail if the key does not exist
     */
    function getAddress(bytes32 key, bool checkExists) public view override returns (address) {
        require(!checkExists || _addressKeyMetas.contains(key), Error.ADDRESS_DOES_NOT_EXIST);
        return currentAddresses[key];
    }

    /**
     * @notice returns the address metadata for the given key
     */
    function getAddressMeta(bytes32 key)
        public
        view
        override
        returns (AddressProviderMeta.Meta memory)
    {
        (bool exists, uint256 metadata) = _addressKeyMetas.tryGet(key);
        require(exists, Error.ADDRESS_DOES_NOT_EXIST);
        return AddressProviderMeta.fromUInt(metadata);
    }

    function initializeAddress(bytes32 key, address initialAddress) external override {
        initializeAddress(key, initialAddress, false);
    }

    /**
     * @notice Initializes an address
     * @param key Key to initialize
     * @param initialAddress Address for `key`
     */
    function initializeAddress(
        bytes32 key,
        address initialAddress,
        bool freezable
    ) public override onlyGovernance {
        AddressProviderMeta.Meta memory meta = AddressProviderMeta.Meta(freezable, false);
        _initializeAddress(key, initialAddress, meta);
    }

    /**
     * @notice Initializes and freezes address
     * @param key Key to initialize
     * @param initialAddress Address for `key`
     */
    function initializeAndFreezeAddress(bytes32 key, address initialAddress)
        external
        override
        onlyGovernance
    {
        AddressProviderMeta.Meta memory meta = AddressProviderMeta.Meta(true, true);
        _initializeAddress(key, initialAddress, meta);
    }

    /**
     * @notice Freezes a configuration key, making it immutable
     * @param key Key to feeze
     */
    function freezeAddress(bytes32 key) external override onlyGovernance {
        AddressProviderMeta.Meta memory meta = getAddressMeta(key);
        require(!meta.frozen, Error.ADDRESS_FROZEN);
        require(meta.freezable, Error.INVALID_ARGUMENT);
        meta.frozen = true;
        _addressKeyMetas.set(key, meta.toUInt());
    }

    /**
     * @notice Prepare update of an address
     * @param key Key to update
     * @param newAddress New address for `key`
     * @return `true` if successful.
     */
    function prepareAddress(bytes32 key, address newAddress)
        external
        override
        onlyGovernance
        returns (bool)
    {
        AddressProviderMeta.Meta memory meta = getAddressMeta(key);
        require(!meta.frozen, Error.ADDRESS_FROZEN);
        return _prepare(key, newAddress);
    }

    /**
     * @notice Execute update of `key`
     * @return New address.
     */
    function executeAddress(bytes32 key) external override returns (address) {
        AddressProviderMeta.Meta memory meta = getAddressMeta(key);
        require(!meta.frozen, Error.ADDRESS_FROZEN);
        return _executeAddress(key);
    }

    /**
     * @notice Reset `key`
     * @return true if it was reset
     */
    function resetAddress(bytes32 key) external override onlyGovernance returns (bool) {
        return _resetAddressConfig(key);
    }

    /**
     * @notice Add a new staker vault.
     * @dev This fails if the token of the staker vault is the token of an existing staker vault.
     * @param stakerVault Vault to add.
     * @return `true` if successful.
     */
    function addStakerVault(address stakerVault)
        external
        override
        onlyRole(Roles.CONTROLLER)
        returns (bool)
    {
        address token = IStakerVault(stakerVault).getToken();
        require(token != address(0), Error.ZERO_ADDRESS_NOT_ALLOWED);
        require(!_stakerVaults.contains(token), Error.STAKER_VAULT_EXISTS);
        _stakerVaults.set(token, stakerVault);
        emit StakerVaultListed(stakerVault);
        return true;
    }

    function isWhiteListedFeeHandler(address feeHandler) external view override returns (bool) {
        return _whiteListedFeeHandlers.contains(feeHandler);
    }

    /**
     * @notice Get the liquidity pool for a given token
     * @dev Does not revert if the pool does not exist
     * @param token Token for which to get the pool.
     * @return Pool address.
     */
    function safeGetPoolForToken(address token) external view override returns (address) {
        (, address poolAddress) = _tokenToPools.tryGet(token);
        return poolAddress;
    }

    /**
     * @notice Get the liquidity pool for a given token
     * @dev Reverts if the pool does not exist
     * @param token Token for which to get the pool.
     * @return Pool address.
     */
    function getPoolForToken(address token) external view override returns (ILiquidityPool) {
        (bool exists, address poolAddress) = _tokenToPools.tryGet(token);
        require(exists, Error.ADDRESS_NOT_FOUND);
        return ILiquidityPool(poolAddress);
    }

    /**
     * @notice Get list of all action addresses.
     * @return Array with action addresses.
     */
    function allActions() external view override returns (address[] memory) {
        return _actions.toArray();
    }

    /**
     * @notice Check whether an address is an action.
     * @param action Address to check whether it is action.
     * @return True if address is an action.
     */
    function isAction(address action) external view override returns (bool) {
        return _actions.contains(action);
    }

    /**
     * @notice Check whether an address is a pool.
     * @param pool Address to check whether it is a pool.
     * @return True if address is a pool.
     */
    function isPool(address pool) external view override returns (bool) {
        address lpToken = ILiquidityPool(pool).getLpToken();
        (bool exists, address poolAddress) = _tokenToPools.tryGet(lpToken);
        return exists && pool == poolAddress;
    }

    /**
     * @notice Get list of all pool addresses.
     * @return Array with pool addresses.
     */
    function allPools() external view override returns (address[] memory) {
        return _tokenToPools.valuesArray();
    }

    /**
     * @notice returns the pool at the given index
     */
    function getPoolAtIndex(uint256 index) external view override returns (address) {
        return _tokenToPools.valueAt(index);
    }

    /**
     * @notice returns the number of pools
     */
    function poolsCount() external view override returns (uint256) {
        return _tokenToPools.length();
    }

    /**
     * @notice Returns all the staker vaults.
     */
    function allStakerVaults() external view override returns (address[] memory) {
        return _stakerVaults.valuesArray();
    }

    /**
     * @notice Get the staker vault for a given token
     * @dev There can only exist one staker vault per unique token.
     * @param token Token for which to get the vault.
     * @return Vault address.
     */
    function getStakerVault(address token) external view override returns (address) {
        return _stakerVaults.get(token);
    }

    /**
     * @notice Tries to get the staker vault for a given token but does not throw if it does not exist
     * @return A boolean set to true if the vault exists and the vault address.
     */
    function tryGetStakerVault(address token) external view override returns (bool, address) {
        return _stakerVaults.tryGet(token);
    }

    /**
     * @notice Check if a vault is registered (exists).
     * @param stakerVault Address of staker vault to check.
     * @return `true` if registered, `false` if not.
     */
    function isStakerVaultRegistered(address stakerVault) external view override returns (bool) {
        address token = IStakerVault(stakerVault).getToken();
        return isStakerVault(stakerVault, token);
    }

    function isStakerVault(address stakerVault, address token) public view override returns (bool) {
        (bool exists, address vault) = _stakerVaults.tryGet(token);
        return exists && vault == stakerVault;
    }

    function _roleManager() internal view override returns (IRoleManager) {
        return IRoleManager(getAddress(AddressProviderKeys._ROLE_MANAGER_KEY));
    }

    function _initializeAddress(
        bytes32 key,
        address initialAddress,
        AddressProviderMeta.Meta memory meta
    ) internal {
        require(!_addressKeyMetas.contains(key), Error.INVALID_ARGUMENT);
        _addKnownAddressKey(key, meta);
        _setConfig(key, initialAddress);
    }

    function _addKnownAddressKey(bytes32 key, AddressProviderMeta.Meta memory meta) internal {
        require(_addressKeyMetas.set(key, meta.toUInt()), Error.INVALID_ARGUMENT);
        emit KnownAddressKeyAdded(key);
    }
}


// File: BkdLocker.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/ScaledMath.sol";
import "../libraries/Errors.sol";
import "../libraries/EnumerableExtensions.sol";
import "../libraries/UncheckedMath.sol";
import "../interfaces/IBkdLocker.sol";
import "../interfaces/tokenomics/IMigrationContract.sol";
import "./utils/Preparable.sol";
import "./access/Authorization.sol";

contract BkdLocker is IBkdLocker, Authorization, Preparable {
    using ScaledMath for uint256;
    using UncheckedMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableMapping for EnumerableMapping.AddressToUintMap;
    using EnumerableExtensions for EnumerableMapping.AddressToUintMap;

    bytes32 internal constant _START_BOOST = "startBoost";
    bytes32 internal constant _MAX_BOOST = "maxBoost";
    bytes32 internal constant _INCREASE_PERIOD = "increasePeriod";
    bytes32 internal constant _WITHDRAW_DELAY = "withdrawDelay";

    // User-specific data
    mapping(address => uint256) public balances;
    mapping(address => uint256) public boostFactors;
    mapping(address => uint256) public lastUpdated;
    mapping(address => WithdrawStash[]) public stashedGovTokens;
    mapping(address => uint256) public totalStashed;

    // Global data
    uint256 public totalLocked;
    uint256 public totalLockedBoosted;
    uint256 public lastMigrationEvent;
    EnumerableMapping.AddressToUintMap private _replacedRewardTokens;

    // Reward token data
    mapping(address => RewardTokenData) public rewardTokenData;
    address public override rewardToken;
    IERC20 public immutable govToken;

    constructor(
        address _rewardToken,
        address _govToken,
        IRoleManager roleManager
    ) Authorization(roleManager) {
        rewardToken = _rewardToken;
        govToken = IERC20(_govToken);
    }

    function initialize(
        uint256 startBoost,
        uint256 maxBoost,
        uint256 increasePeriod,
        uint256 withdrawDelay
    ) external override onlyGovernance {
        require(currentUInts256[_START_BOOST] == 0, Error.CONTRACT_INITIALIZED);
        _setConfig(_START_BOOST, startBoost);
        _setConfig(_MAX_BOOST, maxBoost);
        _setConfig(_INCREASE_PERIOD, increasePeriod);
        _setConfig(_WITHDRAW_DELAY, withdrawDelay);
    }

    /**
     * @notice Sets a new token to be the rewardToken. Fees are then accumulated in this token.
     * @dev Previously used rewardTokens can be set again here.
     */
    function migrate(address newRewardToken) external override onlyGovernance {
        _replacedRewardTokens.remove(newRewardToken);
        _replacedRewardTokens.set(rewardToken, block.timestamp);
        lastMigrationEvent = block.timestamp;
        rewardToken = newRewardToken;
    }

    /**
     * @notice Lock gov. tokens.
     * @dev The amount needs to be approved in advance.
     */
    function lock(uint256 amount) external override {
        return lockFor(msg.sender, amount);
    }

    /**
     * @notice Deposit fees (in the rewardToken) to be distributed to lockers of gov. tokens.
     * @dev `deposit` or `depositFor` needs to be called at least once before this function can be called
     * @param amount Amount of rewardToken to deposit.
     */
    function depositFees(uint256 amount) external override {
        require(amount > 0, Error.INVALID_AMOUNT);
        require(totalLockedBoosted > 0, Error.NOT_ENOUGH_FUNDS);
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);

        RewardTokenData storage curRewardTokenData = rewardTokenData[rewardToken];

        curRewardTokenData.feeIntegral += amount.scaledDiv(totalLockedBoosted);
        curRewardTokenData.feeBalance += amount;
        emit FeesDeposited(amount);
    }

    function claimFees() external override {
        claimFees(rewardToken);
    }

    /**
     * @notice Checkpoint function to update user data, in particular the boost factor.
     */
    function userCheckpoint(address user) external override {
        _userCheckpoint(user, 0, balances[user]);
    }

    /**
     * @notice Prepare unlocking of locked gov. tokens.
     * @dev A delay is enforced and unlocking can only be executed after that.
     * @param amount Amount of gov. tokens to prepare for unlocking.
     */
    function prepareUnlock(uint256 amount) external override {
        require(
            totalStashed[msg.sender] + amount <= balances[msg.sender],
            "Amount exceeds locked balance"
        );
        totalStashed[msg.sender] += amount;
        stashedGovTokens[msg.sender].push(
            WithdrawStash(block.timestamp + currentUInts256[_WITHDRAW_DELAY], amount)
        );
        emit WithdrawPrepared(msg.sender, amount);
    }

    /**
     * @notice Execute all prepared gov. token withdrawals.
     */
    function executeUnlocks() external override {
        uint256 totalAvailableToWithdraw;
        WithdrawStash[] storage stashedWithdraws = stashedGovTokens[msg.sender];
        uint256 length = stashedWithdraws.length;
        require(length > 0, "No entries");
        uint256 i = length;
        while (i > 0) {
            i = i - 1;
            if (stashedWithdraws[i].releaseTime <= block.timestamp) {
                totalAvailableToWithdraw += stashedWithdraws[i].amount;

                stashedWithdraws[i] = stashedWithdraws[stashedWithdraws.length - 1];

                stashedWithdraws.pop();
            }
        }
        totalStashed[msg.sender] -= totalAvailableToWithdraw;
        uint256 newTotal = balances[msg.sender] - totalAvailableToWithdraw;
        _userCheckpoint(msg.sender, 0, newTotal);
        totalLocked -= totalAvailableToWithdraw;
        govToken.safeTransfer(msg.sender, totalAvailableToWithdraw);
        emit WithdrawExecuted(msg.sender, totalAvailableToWithdraw);
    }

    function getUserShare(address user) external view override returns (uint256) {
        return getUserShare(user, rewardToken);
    }

    /**
     * @notice Get the boosted locked balance for a user.
     * @dev This includes the gov. tokens queued for withdrawal.
     * @param user Address to get the boosted balance for.
     * @return boosted balance for user.
     */
    function boostedBalance(address user) external view override returns (uint256) {
        return balances[user].scaledMul(boostFactors[user]);
    }

    /**
     * @notice Get the vote weight for a user.
     * @dev This does not invlude the gov. tokens queued for withdrawal.
     * @param user Address to get the vote weight for.
     * @return vote weight for user.
     */
    function balanceOf(address user) external view override returns (uint256) {
        return (balances[user] - totalStashed[user]).scaledMul(boostFactors[user]);
    }

    /**
     * @notice Get the share of the total boosted locked balance for a user.
     * @dev This includes the gov. tokens queued for withdrawal.
     * @param user Address to get the share of the total boosted balance for.
     * @return share of the total boosted balance for user.
     */
    function getShareOfTotalBoostedBalance(address user) external view override returns (uint256) {
        return balances[user].scaledMul(boostFactors[user]).scaledDiv(totalLockedBoosted);
    }

    function getStashedGovTokens(address user)
        external
        view
        override
        returns (WithdrawStash[] memory)
    {
        return stashedGovTokens[user];
    }

    function claimableFees(address user) external view override returns (uint256) {
        return claimableFees(user, rewardToken);
    }

    /**
     * @notice Claim fees accumulated in the Locker.
     */
    function claimFees(address _rewardToken) public override {
        require(
            _rewardToken == rewardToken || _replacedRewardTokens.contains(_rewardToken),
            Error.INVALID_ARGUMENT
        );
        _userCheckpoint(msg.sender, 0, balances[msg.sender]);
        RewardTokenData storage curRewardTokenData = rewardTokenData[_rewardToken];
        uint256 claimable = curRewardTokenData.userShares[msg.sender];
        curRewardTokenData.userShares[msg.sender] = 0;
        curRewardTokenData.feeBalance -= claimable;
        IERC20(_rewardToken).safeTransfer(msg.sender, claimable);
        emit RewardsClaimed(msg.sender, _rewardToken, claimable);
    }

    /**
     * @notice Lock gov. tokens on behalf of another user.
     * @dev The amount needs to be approved in advance.
     * @param user Address of user to lock on behalf of.
     * @param amount Amount of gov. tokens to lock.
     */
    function lockFor(address user, uint256 amount) public override {
        govToken.safeTransferFrom(msg.sender, address(this), amount);
        _userCheckpoint(user, amount, balances[user] + amount);
        totalLocked += amount;
        emit Locked(user, amount);
    }

    function getUserShare(address user, address _rewardToken)
        public
        view
        override
        returns (uint256)
    {
        return rewardTokenData[_rewardToken].userShares[user];
    }

    function claimableFees(address user, address _rewardToken)
        public
        view
        override
        returns (uint256)
    {
        uint256 currentShare;
        uint256 userBalance = balances[user];
        RewardTokenData storage curRewardTokenData = rewardTokenData[_rewardToken];

        // Compute the share earned by the user since they last updated
        if (userBalance > 0) {
            currentShare += (curRewardTokenData.feeIntegral -
                curRewardTokenData.userFeeIntegrals[user]).scaledMul(
                    userBalance.scaledMul(boostFactors[user])
                );
        }
        return curRewardTokenData.userShares[user] + currentShare;
    }

    function computeNewBoost(
        address user,
        uint256 amountAdded,
        uint256 newTotal
    ) public view override returns (uint256) {
        uint256 newBoost;
        uint256 balance = balances[user];
        uint256 startBoost = currentUInts256[_START_BOOST];
        if (balance == 0 || newTotal == 0) {
            newBoost = startBoost;
        } else {
            uint256 maxBoost = currentUInts256[_MAX_BOOST];
            newBoost = boostFactors[user];
            newBoost += (block.timestamp - lastUpdated[user])
                .scaledDiv(currentUInts256[_INCREASE_PERIOD])
                .scaledMul(maxBoost - startBoost);
            if (newBoost > maxBoost) {
                newBoost = maxBoost;
            }
            if (newTotal <= balance) {
                return newBoost;
            }
            newBoost =
                newBoost.scaledMul(balance.scaledDiv(newTotal)) +
                startBoost.scaledMul(amountAdded.scaledDiv(newTotal));
        }
        return newBoost;
    }

    function _userCheckpoint(
        address user,
        uint256 amountAdded,
        uint256 newTotal
    ) internal {
        RewardTokenData storage curRewardTokenData = rewardTokenData[rewardToken];

        // Compute the share earned by the user since they last updated
        uint256 userBalance = balances[user];
        if (userBalance > 0) {
            curRewardTokenData.userShares[user] += (curRewardTokenData.feeIntegral -
                curRewardTokenData.userFeeIntegrals[user]).scaledMul(
                    userBalance.scaledMul(boostFactors[user])
                );

            // Update values for previous rewardTokens
            if (lastUpdated[user] < lastMigrationEvent) {
                uint256 length = _replacedRewardTokens.length();
                for (uint256 i; i < length; i = i.uncheckedInc()) {
                    (address token, uint256 replacedAt) = _replacedRewardTokens.at(i);
                    if (lastUpdated[user] < replacedAt) {
                        RewardTokenData storage prevRewardTokenData = rewardTokenData[token];
                        prevRewardTokenData.userShares[user] += (prevRewardTokenData.feeIntegral -
                            prevRewardTokenData.userFeeIntegrals[user]).scaledMul(
                                userBalance.scaledMul(boostFactors[user])
                            );
                        prevRewardTokenData.userFeeIntegrals[user] = prevRewardTokenData
                            .feeIntegral;
                    }
                }
            }
        }

        uint256 newBoost = computeNewBoost(user, amountAdded, newTotal);
        totalLockedBoosted =
            totalLockedBoosted +
            newTotal.scaledMul(newBoost) -
            balances[user].scaledMul(boostFactors[user]);

        // Update user values
        curRewardTokenData.userFeeIntegrals[user] = curRewardTokenData.feeIntegral;
        lastUpdated[user] = block.timestamp;
        boostFactors[user] = newBoost;
        balances[user] = newTotal;
    }
}


// File: Controller.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "../interfaces/actions/IAction.sol";
import "../interfaces/IAddressProvider.sol";
import "../interfaces/IController.sol";
import "../interfaces/IStakerVault.sol";
import "../interfaces/pool/ILiquidityPool.sol";
import "../interfaces/tokenomics/IInflationManager.sol";

import "../libraries/AddressProviderHelpers.sol";
import "../libraries/UncheckedMath.sol";

import "./utils/Preparable.sol";
import "./access/Authorization.sol";

contract Controller is IController, Authorization, Preparable {
    using UncheckedMath for uint256;
    using AddressProviderHelpers for IAddressProvider;

    IAddressProvider public immutable override addressProvider;

    IInflationManager public inflationManager;

    bytes32 internal constant _KEEPER_REQUIRED_STAKED_BKD = "KEEPER_REQUIRED_STAKED_BKD";

    constructor(IAddressProvider _addressProvider)
        Authorization(_addressProvider.getRoleManager())
    {
        addressProvider = _addressProvider;
    }

    function setInflationManager(address _inflationManager) external onlyGovernance {
        require(address(inflationManager) == address(0), Error.ADDRESS_ALREADY_SET);
        require(_inflationManager != address(0), Error.INVALID_ARGUMENT);
        inflationManager = IInflationManager(_inflationManager);
    }

    function addStakerVault(address stakerVault)
        external
        override
        onlyRoles2(Roles.GOVERNANCE, Roles.POOL_FACTORY)
        returns (bool)
    {
        if (!addressProvider.addStakerVault(stakerVault)) {
            return false;
        }
        if (address(inflationManager) != address(0)) {
            address lpGauge = IStakerVault(stakerVault).getLpGauge();
            if (lpGauge != address(0)) {
                inflationManager.whitelistGauge(lpGauge);
            }
        }
        return true;
    }

    /**
     * @notice Delists pool.
     * @param pool Address of pool to delist.
     * @return `true` if successful.
     */
    function removePool(address pool) external override onlyGovernance returns (bool) {
        if (!addressProvider.removePool(pool)) {
            return false;
        }
        address lpToken = ILiquidityPool(pool).getLpToken();

        if (address(inflationManager) != address(0)) {
            (bool exists, address stakerVault) = addressProvider.tryGetStakerVault(lpToken);
            if (exists) {
                inflationManager.removeStakerVaultFromInflation(stakerVault, lpToken);
            }
        }

        return true;
    }

    /**
     * @notice Prepares the minimum amount of staked BKD required by a keeper
     */
    function prepareKeeperRequiredStakedBKD(uint256 amount) external override onlyGovernance {
        require(addressProvider.getBKDLocker() != address(0), Error.ZERO_ADDRESS_NOT_ALLOWED);
        _prepare(_KEEPER_REQUIRED_STAKED_BKD, amount);
    }

    /**
     * @notice Resets the minimum amount of staked BKD required by a keeper
     */
    function resetKeeperRequiredStakedBKD() external override onlyGovernance {
        _resetUInt256Config(_KEEPER_REQUIRED_STAKED_BKD);
    }

    /**
     * @notice Sets the minimum amount of staked BKD required by a keeper to the prepared value
     */
    function executeKeeperRequiredStakedBKD() external override {
        _executeUInt256(_KEEPER_REQUIRED_STAKED_BKD);
    }

    /**
     * @notice Returns true if the given keeper has enough staked BKD to execute actions
     */
    function canKeeperExecuteAction(address keeper) external view override returns (bool) {
        uint256 requiredBKD = getKeeperRequiredStakedBKD();
        return
            requiredBKD == 0 ||
            IERC20(addressProvider.getBKDLocker()).balanceOf(keeper) >= requiredBKD;
    }

    /**
     * @return Returns the minimum amount of staked BKD required by a keeper
     */
    function getKeeperRequiredStakedBKD() public view override returns (uint256) {
        return currentUInts256[_KEEPER_REQUIRED_STAKED_BKD];
    }

    /**
     * @return the total amount of ETH require by `payer` to cover the fees for
     * positions registered in all actions
     */
    function getTotalEthRequiredForGas(address payer) external view override returns (uint256) {
        // solhint-disable-previous-line ordering
        uint256 totalEthRequired;
        address[] memory actions = addressProvider.allActions();
        uint256 numActions = actions.length;
        for (uint256 i; i < numActions; i = i.uncheckedInc()) {
            totalEthRequired += IAction(actions[i]).getEthRequiredForGas(payer);
        }
        return totalEthRequired;
    }
}


// File: RewardHandler.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IFeeBurner.sol";
import "../interfaces/IBkdLocker.sol";
import "../interfaces/IController.sol";
import "../interfaces/IAddressProvider.sol";
import "../interfaces/IRewardHandler.sol";
import "./utils/Preparable.sol";
import "./access/Authorization.sol";
import "../libraries/AddressProviderHelpers.sol";
import "../libraries/UncheckedMath.sol";

contract RewardHandler is IRewardHandler, Preparable, Authorization {
    using UncheckedMath for uint256;
    using SafeERC20 for IERC20;
    using AddressProviderHelpers for IAddressProvider;

    IController public immutable controller;
    IAddressProvider public immutable addressProvider;

    constructor(IController _controller)
        Authorization(_controller.addressProvider().getRoleManager())
    {
        controller = _controller;
        addressProvider = IAddressProvider(controller.addressProvider());
    }

    receive() external payable {}

    /**
     * @notice Burns all accumulated fees and pays these out to the BKD locker.
     */
    function burnFees() external override {
        IBkdLocker bkdLocker = IBkdLocker(addressProvider.getBKDLocker());
        IFeeBurner feeBurner = addressProvider.getFeeBurner();
        address targetLpToken = bkdLocker.rewardToken();
        address[] memory pools = addressProvider.allPools();
        uint256 ethBalance = address(this).balance;
        address[] memory tokens = new address[](pools.length);
        for (uint256 i; i < pools.length; i = i.uncheckedInc()) {
            ILiquidityPool pool = ILiquidityPool(pools[i]);
            address underlying = pool.getUnderlying();
            if (underlying != address(0)) {
                _approve(underlying, address(feeBurner));
            }
            tokens[i] = underlying;
        }
        feeBurner.burnToTarget{value: ethBalance}(tokens, targetLpToken);
        uint256 burnedAmount = IERC20(targetLpToken).balanceOf(address(this));
        IERC20(targetLpToken).safeApprove(address(bkdLocker), burnedAmount);
        bkdLocker.depositFees(burnedAmount);
        emit Burned(targetLpToken, burnedAmount);
    }

    /**
     * @dev Approves infinite spending for the given spender.
     * @param token The token to approve for.
     * @param spender The spender to approve.
     */
    function _approve(address token, address spender) internal {
        if (IERC20(token).allowance(address(this), spender) > 0) return;
        IERC20(token).safeApprove(spender, type(uint256).max);
    }
}


// File: StakerVault.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../libraries/ScaledMath.sol";
import "../libraries/Errors.sol";
import "../libraries/AddressProviderHelpers.sol";
import "../libraries/UncheckedMath.sol";

import "../interfaces/IStakerVault.sol";
import "../interfaces/IAddressProvider.sol";
import "../interfaces/IVault.sol";
import "../interfaces/tokenomics/IRewardsGauge.sol";
import "../interfaces/tokenomics/IInflationManager.sol";
import "../interfaces/pool/ILiquidityPool.sol";
import "../interfaces/tokenomics/ILpGauge.sol";
import "../interfaces/IERC20Full.sol";

import "./utils/Preparable.sol";
import "./Controller.sol";
import "./pool/LiquidityPool.sol";
import "./access/Authorization.sol";
import "./utils/Pausable.sol";

/**
 * @notice This contract handles staked tokens from Backd pools
 * However, note that this is NOT an ERC-20 compliant contract and these
 * tokens should never be integrated with any protocol assuming ERC-20 compliant
 * tokens
 * @dev When paused, allows only withdraw/unstake
 */
contract StakerVault is IStakerVault, Authorization, Pausable, Initializable, Preparable {
    using AddressProviderHelpers for IAddressProvider;
    using SafeERC20 for IERC20;
    using ScaledMath for uint256;
    using UncheckedMath for uint256;

    bytes32 internal constant _LP_GAUGE = "lpGauge";

    IController public immutable controller;

    IInflationManager public immutable inflationManager;
    IAddressProvider public immutable addressProvider;

    address public token;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public actionLockedBalances;

    mapping(address => mapping(address => uint256)) internal _allowances;

    // All the data fields required for the staking tracking
    uint256 private _poolTotalStaked;

    mapping(address => bool) public strategies;
    uint256 public strategiesTotalStaked;

    constructor(IController _controller)
        Authorization(_controller.addressProvider().getRoleManager())
    {
        controller = _controller;
        IInflationManager inflationManager_ = controller.inflationManager();
        require(address(inflationManager_) != address(0), Error.ZERO_ADDRESS_NOT_ALLOWED);
        inflationManager = inflationManager_;
        addressProvider = _controller.addressProvider();
    }

    function initialize(address _token) external override initializer {
        token = _token;
    }

    function initializeLpGauge(address _lpGauge) external override onlyGovernance returns (bool) {
        require(currentAddresses[_LP_GAUGE] == address(0), Error.ROLE_EXISTS);
        _setConfig(_LP_GAUGE, _lpGauge);
        inflationManager.addGaugeForVault(token);
        return true;
    }

    function prepareLpGauge(address _lpGauge) external override onlyGovernance returns (bool) {
        _prepare(_LP_GAUGE, _lpGauge);
        return true;
    }

    function executeLpGauge() external override onlyGovernance returns (bool) {
        _executeAddress(_LP_GAUGE);
        inflationManager.addGaugeForVault(token);
        return true;
    }

    /**
     * @notice Registers an address as a strategy to be excluded from token accumulation.
     * @dev This should be used if a strategy deposits into a stakerVault and should not get gov. tokens.
     * @return `true` if success.
     */
    function addStrategy(address strategy) external override returns (bool) {
        require(msg.sender == address(inflationManager), Error.UNAUTHORIZED_ACCESS);
        strategies[strategy] = true;
        return true;
    }

    /**
     * @notice Transfer staked tokens to an account.
     * @dev This is not an ERC20 transfer, as tokens are still owned by this contract, but fees get updated in the LP pool.
     * @param account Address to transfer to.
     * @param amount Amount to transfer.
     * @return `true` if success.
     */
    function transfer(address account, uint256 amount) external override notPaused returns (bool) {
        require(msg.sender != account, Error.SELF_TRANSFER_NOT_ALLOWED);
        require(balances[msg.sender] >= amount, Error.INSUFFICIENT_BALANCE);

        ILiquidityPool pool = addressProvider.getPoolForToken(token);
        pool.handleLpTokenTransfer(msg.sender, account, amount);

        address lpGauge = currentAddresses[_LP_GAUGE];
        if (lpGauge != address(0)) {
            ILpGauge(lpGauge).userCheckpoint(msg.sender);
            ILpGauge(lpGauge).userCheckpoint(account);
        }

        balances[msg.sender] -= amount;
        balances[account] += amount;

        emit Transfer(msg.sender, account, amount);
        return true;
    }

    /**
     * @notice Transfer staked tokens from src to dst.
     * @dev This is not an ERC20 transfer, as tokens are still owned by this contract, but fees get updated in the LP pool.
     * @param src Address to transfer from.
     * @param dst Address to transfer to.
     * @param amount Amount to transfer.
     * @return `true` if success.
     */
    function transferFrom(
        address src,
        address dst,
        uint256 amount
    ) external override notPaused returns (bool) {
        /* Do not allow self transfers */
        require(src != dst, Error.SAME_ADDRESS_NOT_ALLOWED);

        /* Get the allowance, infinite for the account owner */
        uint256 startingAllowance;
        if (msg.sender == src) {
            startingAllowance = type(uint256).max;
        } else {
            startingAllowance = _allowances[src][msg.sender];
        }
        require(startingAllowance >= amount, Error.INSUFFICIENT_ALLOWANCE);

        uint256 srcTokens = balances[src];
        require(srcTokens >= amount, Error.INSUFFICIENT_BALANCE);

        address lpGauge = currentAddresses[_LP_GAUGE];
        if (lpGauge != address(0)) {
            ILpGauge(lpGauge).userCheckpoint(src);
            ILpGauge(lpGauge).userCheckpoint(dst);
        }
        ILiquidityPool pool = addressProvider.getPoolForToken(token);
        pool.handleLpTokenTransfer(src, dst, amount);

        /* Update token balances */
        balances[src] = srcTokens.uncheckedSub(amount);
        balances[dst] = balances[dst] + amount;

        /* Update allowance if necessary */
        if (startingAllowance != type(uint256).max) {
            _allowances[src][msg.sender] = startingAllowance.uncheckedSub(amount);
        }
        emit Transfer(src, dst, amount);
        return true;
    }

    /**
     * @notice Approve staked tokens for spender.
     * @param spender Address to approve tokens for.
     * @param amount Amount to approve.
     * @return `true` if success.
     */
    function approve(address spender, uint256 amount) external override notPaused returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice If an action is registered and stakes funds, this updates the actionLockedBalances for the user.
     * @param account Address that registered the action.
     * @param amount Amount staked by the action.
     * @return `true` if success.
     */
    function increaseActionLockedBalance(address account, uint256 amount)
        external
        override
        returns (bool)
    {
        require(addressProvider.isAction(msg.sender), Error.UNAUTHORIZED_ACCESS);

        address lpGauge = currentAddresses[_LP_GAUGE];
        if (lpGauge != address(0)) {
            ILpGauge(lpGauge).userCheckpoint(account);
        }
        actionLockedBalances[account] += amount;
        return true;
    }

    /**
     * @notice If an action is executed/reset, this updates the actionLockedBalances for the user.
     * @param account Address that registered the action.
     * @param amount Amount executed/reset by the action.
     * @return `true` if success.
     */
    function decreaseActionLockedBalance(address account, uint256 amount)
        external
        override
        returns (bool)
    {
        require(addressProvider.isAction(msg.sender), Error.UNAUTHORIZED_ACCESS);

        address lpGauge = currentAddresses[_LP_GAUGE];
        if (lpGauge != address(0)) {
            ILpGauge(lpGauge).userCheckpoint(account);
        }
        if (actionLockedBalances[account] > amount) {
            actionLockedBalances[account] = actionLockedBalances[account].uncheckedSub(amount);
        } else {
            actionLockedBalances[account] = 0;
        }
        return true;
    }

    function poolCheckpoint() external override returns (bool) {
        if (currentAddresses[_LP_GAUGE] != address(0)) {
            return ILpGauge(currentAddresses[_LP_GAUGE]).poolCheckpoint();
        }
        return false;
    }

    function getLpGauge() external view override returns (address) {
        return currentAddresses[_LP_GAUGE];
    }

    function isStrategy(address user) external view override returns (bool) {
        return strategies[user];
    }

    /**
     * @notice Get the total amount of tokens that are staked by actions
     * @return Total amount staked by actions
     */
    function getStakedByActions() external view override returns (uint256) {
        address[] memory actions = addressProvider.allActions();
        uint256 total;
        for (uint256 i; i < actions.length; i = i.uncheckedInc()) {
            total += balances[actions[i]];
        }
        return total;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function balanceOf(address account) external view override returns (uint256) {
        return balances[account];
    }

    function getPoolTotalStaked() external view override returns (uint256) {
        return _poolTotalStaked;
    }

    /**
     * @notice Returns the total balance in the staker vault, including that locked in positions.
     * @param account Account to query balance for.
     * @return Total balance in staker vault for account.
     */
    function stakedAndActionLockedBalanceOf(address account)
        external
        view
        override
        returns (uint256)
    {
        return balances[account] + actionLockedBalances[account];
    }

    function actionLockedBalanceOf(address account) external view override returns (uint256) {
        return actionLockedBalances[account];
    }

    function decimals() external view override returns (uint8) {
        return IERC20Full(token).decimals();
    }

    function getToken() external view override returns (address) {
        return token;
    }

    function unstake(uint256 amount) public override returns (bool) {
        return unstakeFor(msg.sender, msg.sender, amount);
    }

    /**
     * @notice Stake an amount of vault tokens.
     * @param amount Amount of token to stake.
     * @return `true` if success.
     */
    function stake(uint256 amount) public override returns (bool) {
        return stakeFor(msg.sender, amount);
    }

    /**
     * @notice Stake amount of vault token on behalf of another account.
     * @param account Account for which tokens will be staked.
     * @param amount Amount of token to stake.
     * @return `true` if success.
     */
    function stakeFor(address account, uint256 amount) public override notPaused returns (bool) {
        require(IERC20(token).balanceOf(msg.sender) >= amount, Error.INSUFFICIENT_BALANCE);

        address lpGauge = currentAddresses[_LP_GAUGE];
        if (lpGauge != address(0)) {
            ILpGauge(lpGauge).userCheckpoint(account);
        }

        uint256 oldBal = IERC20(token).balanceOf(address(this));

        if (msg.sender != account) {
            ILiquidityPool pool = addressProvider.getPoolForToken(token);
            pool.handleLpTokenTransfer(msg.sender, account, amount);
        }

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 staked = IERC20(token).balanceOf(address(this)) - oldBal;
        require(staked == amount, Error.INVALID_AMOUNT);
        balances[account] += staked;

        if (strategies[account]) {
            strategiesTotalStaked += staked;
        } else {
            _poolTotalStaked += staked;
        }
        emit Staked(account, amount);
        return true;
    }

    /**
     * @notice Unstake tokens on behalf of another account.
     * @dev Needs to be approved.
     * @param src Account for which tokens will be unstaked.
     * @param dst Account receiving the tokens.
     * @param amount Amount of token to unstake/receive.
     * @return `true` if success.
     */
    function unstakeFor(
        address src,
        address dst,
        uint256 amount
    ) public override returns (bool) {
        ILiquidityPool pool = addressProvider.getPoolForToken(token);
        uint256 allowance_ = _allowances[src][msg.sender];
        require(
            src == msg.sender || allowance_ >= amount || address(pool) == msg.sender,
            Error.UNAUTHORIZED_ACCESS
        );
        require(balances[src] >= amount, Error.INSUFFICIENT_BALANCE);
        address lpGauge = currentAddresses[_LP_GAUGE];
        if (lpGauge != address(0)) {
            ILpGauge(lpGauge).userCheckpoint(src);
        }
        uint256 oldBal = IERC20(token).balanceOf(address(this));

        if (src != dst) {
            pool.handleLpTokenTransfer(src, dst, amount);
        }

        IERC20(token).safeTransfer(dst, amount);

        uint256 unstaked = oldBal.uncheckedSub(IERC20(token).balanceOf(address(this)));

        if (src != msg.sender && allowance_ != type(uint256).max && address(pool) != msg.sender) {
            // update allowance
            _allowances[src][msg.sender] -= unstaked;
        }
        balances[src] -= unstaked;

        if (strategies[src]) {
            strategiesTotalStaked -= unstaked;
        } else {
            _poolTotalStaked -= unstaked;
        }
        emit Unstaked(src, amount);
        return true;
    }

    function _isAuthorizedToPause(address account) internal view override returns (bool) {
        return _roleManager().hasRole(Roles.GOVERNANCE, account);
    }
}


// File: AmmGauge.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/IController.sol";
import "../../interfaces/tokenomics/IAmmGauge.sol";

import "../../libraries/ScaledMath.sol";
import "../../libraries/Errors.sol";
import "../../libraries/AddressProviderHelpers.sol";

import "../access/Authorization.sol";

contract AmmGauge is Authorization, IAmmGauge {
    using AddressProviderHelpers for IAddressProvider;
    using ScaledMath for uint256;
    using SafeERC20 for IERC20;

    IController public immutable controller;

    mapping(address => uint256) public balances;

    // All the data fields required for the staking tracking
    uint256 public ammStakedIntegral;
    uint256 public totalStaked;
    mapping(address => uint256) public perUserStakedIntegral;
    mapping(address => uint256) public perUserShare;

    address public immutable ammToken;
    bool public killed;
    uint48 public ammLastUpdated;

    event RewardClaimed(address indexed account, uint256 amount);

    constructor(IController _controller, address _ammToken)
        Authorization(_controller.addressProvider().getRoleManager())
    {
        ammToken = _ammToken;
        controller = _controller;
        ammLastUpdated = uint48(block.timestamp);
    }

    /**
     * @notice Shut down the gauge.
     * @dev Accrued inflation can still be claimed from the gauge after shutdown.
     * @return `true` if successful.
     */
    function kill() external override returns (bool) {
        require(msg.sender == address(controller.inflationManager()), Error.UNAUTHORIZED_ACCESS);
        poolCheckpoint();
        killed = true;
        return true;
    }

    function claimRewards(address beneficiary) external virtual override returns (uint256) {
        require(
            msg.sender == beneficiary || _roleManager().hasRole(Roles.GAUGE_ZAP, msg.sender),
            Error.UNAUTHORIZED_ACCESS
        );
        _userCheckpoint(beneficiary);
        uint256 amount = perUserShare[beneficiary];
        if (amount <= 0) return 0;
        perUserShare[beneficiary] = 0;
        controller.inflationManager().mintRewards(beneficiary, amount);
        emit RewardClaimed(beneficiary, amount);
        return amount;
    }

    function stake(uint256 amount) external virtual override returns (bool) {
        return stakeFor(msg.sender, amount);
    }

    function unstake(uint256 amount) external virtual override returns (bool) {
        return unstakeFor(msg.sender, amount);
    }

    function getAmmToken() external view override returns (address) {
        return ammToken;
    }

    function isAmmToken(address token) external view override returns (bool) {
        return token == ammToken;
    }

    function claimableRewards(address user) external view virtual override returns (uint256) {
        uint256 ammStakedIntegral_ = ammStakedIntegral;
        if (!killed && totalStaked > 0) {
            ammStakedIntegral_ += (controller.inflationManager().getAmmRateForToken(ammToken) *
                (block.timestamp - uint256(ammLastUpdated))).scaledDiv(totalStaked);
        }
        return
            perUserShare[user] +
            balances[user].scaledMul(ammStakedIntegral_ - perUserStakedIntegral[user]);
    }

    /**
     * @notice Stake amount of AMM token on behalf of another account.
     * @param account Account for which tokens will be staked.
     * @param amount Amount of token to stake.
     * @return `true` if success.
     */
    function stakeFor(address account, uint256 amount) public virtual override returns (bool) {
        require(amount > 0, Error.INVALID_AMOUNT);

        _userCheckpoint(account);

        uint256 oldBal = IERC20(ammToken).balanceOf(address(this));
        IERC20(ammToken).safeTransferFrom(msg.sender, address(this), amount);
        uint256 newBal = IERC20(ammToken).balanceOf(address(this));
        uint256 staked = newBal - oldBal;
        balances[account] += staked;
        totalStaked += staked;
        emit AmmStaked(account, ammToken, amount);
        return true;
    }

    /**
     * @notice Unstake amount of AMM token and send to another account.
     * @param dst Account to which unstaked AMM tokens will be sent.
     * @param amount Amount of token to unstake.
     * @return `true` if success.
     */
    function unstakeFor(address dst, uint256 amount) public virtual override returns (bool) {
        require(amount > 0, Error.INVALID_AMOUNT);
        require(balances[msg.sender] >= amount, Error.INSUFFICIENT_BALANCE);

        _userCheckpoint(msg.sender);

        uint256 oldBal = IERC20(ammToken).balanceOf(address(this));
        IERC20(ammToken).safeTransfer(dst, amount);
        uint256 newBal = IERC20(ammToken).balanceOf(address(this));
        uint256 unstaked = oldBal - newBal;
        balances[msg.sender] -= unstaked;
        totalStaked -= unstaked;
        emit AmmUnstaked(msg.sender, ammToken, amount);
        return true;
    }

    function poolCheckpoint() public virtual override returns (bool) {
        if (killed) {
            return false;
        }
        uint256 currentRate = controller.inflationManager().getAmmRateForToken(ammToken);
        // Update the integral of total token supply for the pool
        uint256 timeElapsed = block.timestamp - uint256(ammLastUpdated);
        if (totalStaked > 0) {
            ammStakedIntegral += (currentRate * timeElapsed).scaledDiv(totalStaked);
        }
        ammLastUpdated = uint48(block.timestamp);
        return true;
    }

    function _userCheckpoint(address user) internal virtual returns (bool) {
        poolCheckpoint();
        perUserShare[user] += balances[user].scaledMul(
            ammStakedIntegral - perUserStakedIntegral[user]
        );
        perUserStakedIntegral[user] = ammStakedIntegral;
        return true;
    }
}


// File: BkdToken.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../interfaces/tokenomics/IBkdToken.sol";

import "../../libraries/ScaledMath.sol";
import "../../libraries/Errors.sol";

contract BkdToken is IBkdToken, ERC20 {
    using ScaledMath for uint256;

    address public immutable minter;

    constructor(
        string memory name_,
        string memory symbol_,
        address _minter
    ) ERC20(name_, symbol_) {
        minter = _minter;
    }

    /**
     * @notice Mints tokens for a given address.
     * @dev Fails if msg.sender is not the minter.
     * @param account Account for which tokens should be minted.
     * @param amount Amount of tokens to mint.
     */
    function mint(address account, uint256 amount) external override {
        require(msg.sender == minter, Error.UNAUTHORIZED_ACCESS);
        _mint(account, amount);
    }
}


// File: FeeBurner.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../libraries/AddressProviderHelpers.sol";
import "../../libraries/Errors.sol";
import "../../libraries/UncheckedMath.sol";
import "../../interfaces/pool/ILiquidityPool.sol";
import "../../interfaces/IFeeBurner.sol";
import "../../interfaces/ISwapperRouter.sol";
import "../../interfaces/IAddressProvider.sol";

/**
 * The Fee Burner converts all of the callers Backd LP Tokens to a single target Backd LP Token.
 * It first burns the Pool LP Tokens for the Pool underlying.
 * Then it swaps all the underlyings for the target Pool underlying.
 * Finally it deposits the Pool underlying into the target Pool to get the target LP Token.
 */
contract FeeBurner is IFeeBurner {
    using SafeERC20 for IERC20;
    using UncheckedMath for uint256;
    using AddressProviderHelpers for IAddressProvider;

    address private constant _WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH

    IAddressProvider private immutable _addressProvider; // Address Provider, used for getting pools and swapper router

    event Burned(address targetLpToken, uint256 amountBurned); // Emmited after a successfull burn to target lp token

    constructor(address addressProvider_) {
        _addressProvider = IAddressProvider(addressProvider_);
    }

    receive() external payable {} // Recieve function for withdrawing from Backd ETH Pool

    /**
     * @notice Converts callers Tokens to target Backd LP Token for the given tokens_.
     * @param tokens_ The Tokens to convert to the targetLpToken_.
     * @param targetLpToken_ The LP Token that should be received.
     * @return received The amount of the target LP Token received.
     */
    function burnToTarget(address[] memory tokens_, address targetLpToken_)
        public
        payable
        override
        returns (uint256 received)
    {
        require(tokens_.length != 0, "No tokens to burn");

        // Swapping tokens for WETH
        ILiquidityPool targetPool_ = _addressProvider.getPoolForToken(targetLpToken_);
        address targetUnderlying_ = targetPool_.getUnderlying();
        ISwapperRouter swapperRouter_ = _swapperRouter();
        bool burningEth_;
        for (uint256 i; i < tokens_.length; i = i.uncheckedInc()) {
            IERC20 token_ = IERC20(tokens_[i]);

            // Handling ETH
            if (address(token_) == address(0)) {
                if (msg.value == 0) continue;
                burningEth_ = true;
                swapperRouter_.swapAll{value: msg.value}(address(token_), _WETH);
                continue;
            }

            // Handling ERC20
            uint256 tokenBalance_ = token_.balanceOf(msg.sender);
            if (tokenBalance_ == 0) continue;
            token_.safeTransferFrom(msg.sender, address(this), tokenBalance_);
            if (address(token_) == targetUnderlying_) continue;
            _approve(address(token_), address(swapperRouter_));
            swapperRouter_.swap(address(token_), _WETH, tokenBalance_);
        }
        require(burningEth_ || msg.value == 0, Error.INVALID_VALUE);

        // Swapping WETH for target underlying
        _approve(_WETH, address(swapperRouter_));
        swapperRouter_.swapAll(_WETH, targetUnderlying_);

        // Depositing target underlying into target pool
        uint256 targetLpTokenBalance_ = _depositInPool(targetUnderlying_, targetPool_);

        // Transfering LP tokens back to sender
        IERC20(targetLpToken_).safeTransfer(msg.sender, targetLpTokenBalance_);
        emit Burned(targetLpToken_, targetLpTokenBalance_);
        return targetLpTokenBalance_;
    }

    /**
     * @dev Deposits underlying into pool to receive LP Tokens.
     * @param underlying_ The underlying of the pool.
     * @param pool_ The pool to deposit into.
     * @return received The amount of LP Tokens received.
     */
    function _depositInPool(address underlying_, ILiquidityPool pool_)
        internal
        returns (uint256 received)
    {
        // Handling ETH deposits
        if (underlying_ == address(0)) {
            uint256 ethBalance_ = address(this).balance;
            return pool_.deposit{value: ethBalance_}(ethBalance_);
        }

        // Handling ERC20 deposits
        _approve(underlying_, address(pool_));
        return pool_.deposit(IERC20(underlying_).balanceOf(address(this)));
    }

    /**
     * @dev Approves infinite spending for the given spender.
     * @param token_ The token to approve for.
     * @param spender_ The spender to approve.
     */
    function _approve(address token_, address spender_) internal {
        if (IERC20(token_).allowance(address(this), spender_) > 0) return;
        IERC20(token_).safeApprove(spender_, type(uint256).max);
    }

    /**
     * @dev Gets the swapper router.
     * @return The swapper router.
     */
    function _swapperRouter() internal view returns (ISwapperRouter) {
        return _addressProvider.getSwapperRouter();
    }
}


// File: InflationManager.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "../../interfaces/IStakerVault.sol";
import "../../interfaces/tokenomics/IInflationManager.sol";
import "../../interfaces/tokenomics/IKeeperGauge.sol";
import "../../interfaces/tokenomics/IAmmGauge.sol";

import "../../libraries/EnumerableMapping.sol";
import "../../libraries/EnumerableExtensions.sol";
import "../../libraries/AddressProviderHelpers.sol";
import "../../libraries/UncheckedMath.sol";

import "./Minter.sol";
import "../utils/Preparable.sol";
import "../access/Authorization.sol";

contract InflationManager is Authorization, IInflationManager, Preparable {
    using UncheckedMath for uint256;
    using EnumerableMapping for EnumerableMapping.AddressToAddressMap;
    using EnumerableExtensions for EnumerableMapping.AddressToAddressMap;
    using AddressProviderHelpers for IAddressProvider;

    IAddressProvider public immutable addressProvider;

    bytes32 internal constant _KEEPER_WEIGHT_KEY = "keeperWeight";
    bytes32 internal constant _AMM_WEIGHT_KEY = "ammWeight";
    bytes32 internal constant _LP_WEIGHT_KEY = "lpWeight";

    address public minter;
    bool public weightBasedKeeperDistributionDeactivated;
    uint256 public totalKeeperPoolWeight;
    uint256 public totalLpPoolWeight;
    uint256 public totalAmmTokenWeight;

    // Pool -> keeperGauge
    EnumerableMapping.AddressToAddressMap private _keeperGauges;
    // AMM token -> ammGauge
    EnumerableMapping.AddressToAddressMap private _ammGauges;

    mapping(address => bool) public gauges;

    event NewKeeperWeight(address indexed pool, uint256 newWeight);
    event NewLpWeight(address indexed pool, uint256 newWeight);
    event NewAmmTokenWeight(address indexed token, uint256 newWeight);

    modifier onlyGauge() {
        require(gauges[msg.sender], Error.UNAUTHORIZED_ACCESS);
        _;
    }

    constructor(IAddressProvider _addressProvider)
        Authorization(_addressProvider.getRoleManager())
    {
        addressProvider = _addressProvider;
    }

    function setMinter(address _minter) external override onlyGovernance returns (bool) {
        require(minter == address(0), Error.ADDRESS_ALREADY_SET);
        require(_minter != address(0), Error.INVALID_MINTER);
        minter = _minter;
        return true;
    }

    /**
     * @notice Advance the keeper gauge for a pool by on epoch.
     * @param pool Pool for which the keeper gauge is advanced.
     * @return `true` if successful.
     */
    function advanceKeeperGaugeEpoch(address pool) external override onlyGovernance returns (bool) {
        IKeeperGauge(_keeperGauges.get(pool)).advanceEpoch();
        return true;
    }

    /**
     * @notice Mints BKD tokens.
     * @param beneficiary Address to receive the tokens.
     * @param amount Amount of tokens to mint.
     */
    function mintRewards(address beneficiary, uint256 amount) external override onlyGauge {
        Minter(minter).mint(beneficiary, amount);
    }

    /**
     * @notice Deactivates the weight-based distribution of keeper inflation.
     * @dev This can only be done once, when the keeper inflation mechanism is altered.
     * @return `true` if successful.
     */
    function deactivateWeightBasedKeeperDistribution()
        external
        override
        onlyGovernance
        returns (bool)
    {
        require(!weightBasedKeeperDistributionDeactivated, "Weight-based dist. deactivated.");
        address[] memory liquidityPools = addressProvider.allPools();
        uint256 length = liquidityPools.length;
        for (uint256 i; i < length; i = i.uncheckedInc()) {
            _removeKeeperGauge(address(liquidityPools[i]));
        }
        weightBasedKeeperDistributionDeactivated = true;
        return true;
    }

    /**
     * @notice Checkpoints all gauges.
     * @dev This is mostly used upon inflation rate updates.
     * @return `true` if successful.
     */
    function checkpointAllGauges() external override returns (bool) {
        uint256 length = _keeperGauges.length();
        for (uint256 i; i < length; i = i.uncheckedInc()) {
            IKeeperGauge(_keeperGauges.valueAt(i)).poolCheckpoint();
        }
        address[] memory stakerVaults = addressProvider.allStakerVaults();
        for (uint256 i; i < stakerVaults.length; i = i.uncheckedInc()) {
            IStakerVault(stakerVaults[i]).poolCheckpoint();
        }

        length = _ammGauges.length();
        for (uint256 i; i < length; i = i.uncheckedInc()) {
            IAmmGauge(_ammGauges.valueAt(i)).poolCheckpoint();
        }
        return true;
    }

    /**
     * @notice Prepare update of a keeper pool weight (with time delay enforced).
     * @param pool Pool to update the keeper weight for.
     * @param newPoolWeight New weight for the keeper inflation for the pool.
     * @return `true` if successful.
     */
    function prepareKeeperPoolWeight(address pool, uint256 newPoolWeight)
        external
        override
        onlyGovernance
        returns (bool)
    {
        require(_keeperGauges.contains(pool), Error.INVALID_ARGUMENT);
        bytes32 key = _getKeeperGaugeKey(pool);
        _prepare(key, newPoolWeight);
        return true;
    }

    /**
     * @notice Execute update of keeper pool weight (with time delay enforced).
     * @param pool Pool to execute the keeper weight update for.
     * @dev Needs to be called after the update was prepared. Fails if called before time delay is met.
     * @return New keeper pool weight.
     */
    function executeKeeperPoolWeight(address pool) external override returns (uint256) {
        bytes32 key = _getKeeperGaugeKey(pool);
        _executeKeeperPoolWeight(key, pool, isInflationWeightManager(msg.sender));
        return currentUInts256[key];
    }

    /**
     * @notice Prepare update of a batch of keeperGauge weights (with time delay enforced).
     * @dev Each entry in the pools array corresponds to an entry in the weights array.
     * @param pools Pools to update the keeper weight for.
     * @param weights New weights for the keeper inflation for the pools.
     * @return `true` if successful.
     */
    function batchPrepareKeeperPoolWeights(address[] calldata pools, uint256[] calldata weights)
        external
        override
        onlyGovernance
        returns (bool)
    {
        uint256 length = pools.length;
        require(length == weights.length, Error.INVALID_ARGUMENT);
        bytes32 key;
        for (uint256 i; i < length; i = i.uncheckedInc()) {
            require(_keeperGauges.contains(pools[i]), Error.INVALID_ARGUMENT);
            key = _getKeeperGaugeKey(pools[i]);
            _prepare(key, weights[i]);
        }
        return true;
    }

    function whitelistGauge(address gauge) external override onlyRole(Roles.CONTROLLER) {
        gauges[gauge] = true;
    }

    /**
     * @notice Execute weight updates for a batch of _keeperGauges.
     * @param pools Pools to execute the keeper weight updates for.
     * @return `true` if successful.
     */
    function batchExecuteKeeperPoolWeights(address[] calldata pools)
        external
        override
        onlyRoles2(Roles.GOVERNANCE, Roles.INFLATION_MANAGER)
        returns (bool)
    {
        uint256 length = pools.length;
        bytes32 key;
        for (uint256 i; i < length; i = i.uncheckedInc()) {
            key = _getKeeperGaugeKey(pools[i]);
            _executeKeeperPoolWeight(key, pools[i], isInflationWeightManager(msg.sender));
        }
        return true;
    }

    function removeStakerVaultFromInflation(address stakerVault, address lpToken)
        external
        override
        onlyRole(Roles.CONTROLLER)
    {
        bytes32 key = _getLpStakerVaultKey(stakerVault);
        _prepare(key, 0);
        _executeLpPoolWeight(key, lpToken, stakerVault, true);
    }

    /**
     * @notice Prepare update of a lp pool weight (with time delay enforced).
     * @param lpToken LP token to update the weight for.
     * @param newPoolWeight New LP inflation weight.
     * @return `true` if successful.
     */
    function prepareLpPoolWeight(address lpToken, uint256 newPoolWeight)
        external
        override
        onlyRoles2(Roles.GOVERNANCE, Roles.INFLATION_MANAGER)
        returns (bool)
    {
        address stakerVault = addressProvider.getStakerVault(lpToken);
        // Require both that gauge is registered and that pool is still in action
        require(gauges[IStakerVault(stakerVault).getLpGauge()], Error.GAUGE_DOES_NOT_EXIST);
        _ensurePoolExists(lpToken);
        bytes32 key = _getLpStakerVaultKey(stakerVault);
        _prepare(key, newPoolWeight);
        return true;
    }

    /**
     * @notice Execute update of lp pool weight (with time delay enforced).
     * @dev Needs to be called after the update was prepared. Fails if called before time delay is met.
     * @return New lp pool weight.
     */
    function executeLpPoolWeight(address lpToken) external override returns (uint256) {
        address stakerVault = addressProvider.getStakerVault(lpToken);
        // Require both that gauge is registered and that pool is still in action
        require(IStakerVault(stakerVault).getLpGauge() != address(0), Error.ADDRESS_NOT_FOUND);
        _ensurePoolExists(lpToken);
        bytes32 key = _getLpStakerVaultKey(stakerVault);
        _executeLpPoolWeight(key, lpToken, stakerVault, isInflationWeightManager(msg.sender));
        return currentUInts256[key];
    }

    /**
     * @notice Prepare update of a batch of LP token weights (with time delay enforced).
     * @dev Each entry in the lpTokens array corresponds to an entry in the weights array.
     * @param lpTokens LpTokens to update the inflation weight for.
     * @param weights New weights for the inflation for the LpTokens.
     * @return `true` if successful.
     */
    function batchPrepareLpPoolWeights(address[] calldata lpTokens, uint256[] calldata weights)
        external
        override
        onlyRoles2(Roles.GOVERNANCE, Roles.INFLATION_MANAGER)
        returns (bool)
    {
        uint256 length = lpTokens.length;
        require(length == weights.length, "Invalid length of arguments");
        bytes32 key;
        for (uint256 i; i < length; i = i.uncheckedInc()) {
            address stakerVault = addressProvider.getStakerVault(lpTokens[i]);
            // Require both that gauge is registered and that pool is still in action
            require(IStakerVault(stakerVault).getLpGauge() != address(0), Error.ADDRESS_NOT_FOUND);
            _ensurePoolExists(lpTokens[i]);
            key = _getLpStakerVaultKey(stakerVault);
            _prepare(key, weights[i]);
        }
        return true;
    }

    /**
     * @notice Execute weight updates for a batch of LpTokens.
     * @dev If this is called by the INFLATION_MANAGER role address, no time delay is enforced.
     * @param lpTokens LpTokens to execute the weight updates for.
     * @return `true` if successful.
     */
    function batchExecuteLpPoolWeights(address[] calldata lpTokens)
        external
        override
        onlyRoles2(Roles.GOVERNANCE, Roles.INFLATION_MANAGER)
        returns (bool)
    {
        uint256 length = lpTokens.length;
        for (uint256 i; i < length; i = i.uncheckedInc()) {
            address lpToken = lpTokens[i];
            address stakerVault = addressProvider.getStakerVault(lpToken);
            // Require both that gauge is registered and that pool is still in action
            require(IStakerVault(stakerVault).getLpGauge() != address(0), Error.ADDRESS_NOT_FOUND);
            _ensurePoolExists(lpToken);
            bytes32 key = _getLpStakerVaultKey(stakerVault);
            _executeLpPoolWeight(key, lpToken, stakerVault, isInflationWeightManager(msg.sender));
        }
        return true;
    }

    /**
     * @notice Prepare an inflation weight update for an AMM token (with time delay enforced).
     * @param token AMM token to update the weight for.
     * @param newTokenWeight New AMM token inflation weight.
     * @return `true` if successful.
     */
    function prepareAmmTokenWeight(address token, uint256 newTokenWeight)
        external
        override
        onlyRoles2(Roles.GOVERNANCE, Roles.INFLATION_MANAGER)
        returns (bool)
    {
        require(_ammGauges.contains(token), "amm gauge not found");
        bytes32 key = _getAmmGaugeKey(token);
        _prepare(key, newTokenWeight);
        return true;
    }

    /**
     * @notice Execute update of lp pool weight (with time delay enforced).
     * @dev Needs to be called after the update was prepared. Fails if called before time delay is met.
     * @return New lp pool weight.
     */
    function executeAmmTokenWeight(address token) external override returns (uint256) {
        bytes32 key = _getAmmGaugeKey(token);
        _executeAmmTokenWeight(token, key, isInflationWeightManager(msg.sender));
        return currentUInts256[key];
    }

    /**
     * @notice Registers a pool's strategy with the stakerVault of the pool where the strategy deposits.
     * @dev This simply avoids the strategy accumulating tokens in the deposit pool.
     * @param depositStakerVault StakerVault of the pool where the strategy deposits.
     * @param strategyPool The pool of the strategy to register (avoids blacklisting other addresses).
     * @return `true` if successful.
     */
    function addStrategyToDepositStakerVault(address depositStakerVault, address strategyPool)
        external
        override
        onlyGovernance
        returns (bool)
    {
        IVault _vault = ILiquidityPool(strategyPool).getVault();
        IStakerVault(depositStakerVault).addStrategy(address(_vault.getStrategy()));
        return true;
    }

    /**
     * @notice Prepare update of a batch of AMM token weights (with time delay enforced).
     * @dev Each entry in the tokens array corresponds to an entry in the weights array.
     * @param tokens AMM tokens to update the inflation weight for.
     * @param weights New weights for the inflation for the AMM tokens.
     * @return `true` if successful.
     */
    function batchPrepareAmmTokenWeights(address[] calldata tokens, uint256[] calldata weights)
        external
        override
        onlyRoles2(Roles.GOVERNANCE, Roles.INFLATION_MANAGER)
        returns (bool)
    {
        uint256 length = tokens.length;
        bytes32 key;
        require(length == weights.length, "Invalid length of arguments");
        for (uint256 i; i < length; i = i.uncheckedInc()) {
            require(_ammGauges.contains(tokens[i]), "amm gauge not found");
            key = _getAmmGaugeKey(tokens[i]);
            _prepare(key, weights[i]);
        }
        return true;
    }

    /**
     * @notice Execute weight updates for a batch of AMM tokens.
     * @dev If this is called by the INFLATION_MANAGER role address, no time delay is enforced.
     * @param tokens AMM tokens to execute the weight updates for.
     * @return `true` if successful.
     */
    function batchExecuteAmmTokenWeights(address[] calldata tokens)
        external
        override
        onlyRoles2(Roles.GOVERNANCE, Roles.INFLATION_MANAGER)
        returns (bool)
    {
        uint256 length = tokens.length;
        bool isWeightManager = isInflationWeightManager(msg.sender);
        bytes32 key;
        address token;
        for (uint256 i; i < length; i = i.uncheckedInc()) {
            token = tokens[i];
            key = _getAmmGaugeKey(token);
            _executeAmmTokenWeight(token, key, isWeightManager);
        }
        return true;
    }

    /**
     * @notice Sets the KeeperGauge for a pool.
     * @dev Multiple pools can have the same KeeperGauge.
     * @param pool Address of pool to set the KeeperGauge for.
     * @param _keeperGauge Address of KeeperGauge.
     * @return `true` if successful.
     */
    function setKeeperGauge(address pool, address _keeperGauge)
        external
        override
        onlyGovernance
        returns (bool)
    {
        uint256 length = _keeperGauges.length();
        bool keeperGaugeExists = false;
        for (uint256 i; i < length; i = i.uncheckedInc()) {
            if (address(_keeperGauges.valueAt(i)) == _keeperGauge) {
                keeperGaugeExists = true;
                break;
            }
        }
        // Check to make sure that once weight-based dist is deactivated, only one gauge can exist
        if (!keeperGaugeExists && weightBasedKeeperDistributionDeactivated && length >= 1) {
            return false;
        }
        (bool exists, address keeperGauge) = _keeperGauges.tryGet(pool);
        require(!exists || keeperGauge != _keeperGauge, Error.INVALID_ARGUMENT);

        if (exists && !IKeeperGauge(keeperGauge).killed()) {
            IKeeperGauge(keeperGauge).poolCheckpoint();
            IKeeperGauge(keeperGauge).kill();
        }
        _keeperGauges.set(pool, _keeperGauge);
        gauges[_keeperGauge] = true;
        return true;
    }

    function removeKeeperGauge(address pool) external onlyGovernance returns (bool) {
        _removeKeeperGauge(pool);
        return true;
    }

    /**
     * @notice Sets the AmmGauge for a particular AMM token.
     * @param token Address of the amm token.
     * @param _ammGauge Address of AmmGauge.
     * @return `true` if successful.
     */
    function setAmmGauge(address token, address _ammGauge)
        external
        override
        onlyGovernance
        returns (bool)
    {
        require(IAmmGauge(_ammGauge).isAmmToken(token), Error.ADDRESS_NOT_WHITELISTED);
        uint256 length = _ammGauges.length();
        for (uint256 i; i < length; i = i.uncheckedInc()) {
            if (address(_ammGauges.valueAt(i)) == _ammGauge) {
                return false;
            }
        }
        if (_ammGauges.contains(token)) {
            address ammGauge = _ammGauges.get(token);
            IAmmGauge(ammGauge).poolCheckpoint();
            IAmmGauge(ammGauge).kill();
        }
        _ammGauges.set(token, _ammGauge);
        gauges[_ammGauge] = true;
        return true;
    }

    function removeAmmGauge(address token) external override onlyGovernance returns (bool) {
        if (!_ammGauges.contains(token)) return false;
        address ammGauge = _ammGauges.get(token);
        bytes32 key = _getAmmGaugeKey(token);
        _prepare(key, 0);
        _executeAmmTokenWeight(token, key, true);
        IAmmGauge(ammGauge).kill();
        _ammGauges.remove(token);
        // Do not delete from the gauges map to allow claiming of remaining balances
        emit AmmGaugeDelisted(token, ammGauge);
        return true;
    }

    function addGaugeForVault(address lpToken) external override returns (bool) {
        IStakerVault _stakerVault = IStakerVault(msg.sender);
        require(addressProvider.isStakerVault(msg.sender, lpToken), Error.UNAUTHORIZED_ACCESS);
        address lpGauge = _stakerVault.getLpGauge();
        require(lpGauge != address(0), Error.GAUGE_DOES_NOT_EXIST);
        gauges[lpGauge] = true;
        return true;
    }

    function getAllAmmGauges() external view override returns (address[] memory) {
        return _ammGauges.valuesArray();
    }

    function getLpRateForStakerVault(address stakerVault) external view override returns (uint256) {
        if (minter == address(0) || totalLpPoolWeight == 0) {
            return 0;
        }

        bytes32 key = _getLpStakerVaultKey(stakerVault);
        uint256 lpInflationRate = Minter(minter).getLpInflationRate();
        uint256 poolInflationRate = (currentUInts256[key] * lpInflationRate) / totalLpPoolWeight;

        return poolInflationRate;
    }

    function getKeeperRateForPool(address pool) external view override returns (uint256) {
        if (minter == address(0)) {
            return 0;
        }
        uint256 keeperInflationRate = Minter(minter).getKeeperInflationRate();
        // After deactivation of weight based dist, KeeperGauge handles the splitting
        if (weightBasedKeeperDistributionDeactivated) return keeperInflationRate;
        if (totalKeeperPoolWeight == 0) return 0;
        bytes32 key = _getKeeperGaugeKey(pool);
        uint256 poolInflationRate = (currentUInts256[key] * keeperInflationRate) /
            totalKeeperPoolWeight;
        return poolInflationRate;
    }

    function getAmmRateForToken(address token) external view override returns (uint256) {
        if (minter == address(0) || totalAmmTokenWeight == 0) {
            return 0;
        }
        bytes32 key = _getAmmGaugeKey(token);
        uint256 ammInflationRate = Minter(minter).getAmmInflationRate();
        uint256 ammTokenInflationRate = (currentUInts256[key] * ammInflationRate) /
            totalAmmTokenWeight;
        return ammTokenInflationRate;
    }

    //TOOD: See if this is still needed somewhere
    function getKeeperWeightForPool(address pool) external view override returns (uint256) {
        bytes32 key = _getKeeperGaugeKey(pool);
        return currentUInts256[key];
    }

    function getAmmWeightForToken(address token) external view override returns (uint256) {
        bytes32 key = _getAmmGaugeKey(token);
        return currentUInts256[key];
    }

    function getLpPoolWeight(address lpToken) external view override returns (uint256) {
        address stakerVault = addressProvider.getStakerVault(lpToken);
        bytes32 key = _getLpStakerVaultKey(stakerVault);
        return currentUInts256[key];
    }

    function getKeeperGaugeForPool(address pool) external view override returns (address) {
        (, address keeperGauge) = _keeperGauges.tryGet(pool);
        return keeperGauge;
    }

    function getAmmGaugeForToken(address token) external view override returns (address) {
        (, address ammGauge) = _ammGauges.tryGet(token);
        return ammGauge;
    }

    /**
     * @notice Check if an account is governance proxy.
     * @param account Address to check.
     * @return `true` if account is governance proxy.
     */
    function isInflationWeightManager(address account) public view override returns (bool) {
        return _roleManager().hasRole(Roles.INFLATION_MANAGER, account);
    }

    function _executeKeeperPoolWeight(
        bytes32 key,
        address pool,
        bool isWeightManager
    ) internal returns (bool) {
        IKeeperGauge(_keeperGauges.get(pool)).poolCheckpoint();
        totalKeeperPoolWeight = totalKeeperPoolWeight - currentUInts256[key] + pendingUInts256[key];
        totalKeeperPoolWeight = totalKeeperPoolWeight > 0 ? totalKeeperPoolWeight : 0;
        isWeightManager ? _setConfig(key, pendingUInts256[key]) : _executeUInt256(key);
        emit NewKeeperWeight(pool, currentUInts256[key]);
        return true;
    }

    function _executeLpPoolWeight(
        bytes32 key,
        address lpToken,
        address stakerVault,
        bool isWeightManager
    ) internal returns (bool) {
        IStakerVault(stakerVault).poolCheckpoint();
        totalLpPoolWeight = totalLpPoolWeight - currentUInts256[key] + pendingUInts256[key];
        totalLpPoolWeight = totalLpPoolWeight > 0 ? totalLpPoolWeight : 0;
        isWeightManager ? _setConfig(key, pendingUInts256[key]) : _executeUInt256(key);
        emit NewLpWeight(lpToken, currentUInts256[key]);
        return true;
    }

    function _executeAmmTokenWeight(
        address token,
        bytes32 key,
        bool isWeightManager
    ) internal returns (bool) {
        IAmmGauge(_ammGauges.get(token)).poolCheckpoint();
        totalAmmTokenWeight = totalAmmTokenWeight - currentUInts256[key] + pendingUInts256[key];
        totalAmmTokenWeight = totalAmmTokenWeight > 0 ? totalAmmTokenWeight : 0;
        isWeightManager ? _setConfig(key, pendingUInts256[key]) : _executeUInt256(key);
        // Do pool checkpoint to update the pool integrals
        emit NewAmmTokenWeight(token, currentUInts256[key]);
        return true;
    }

    function _removeKeeperGauge(address pool) internal {
        address keeperGauge = _keeperGauges.get(pool);
        bytes32 key = _getKeeperGaugeKey(pool);
        _prepare(key, 0);
        _executeKeeperPoolWeight(key, pool, true);
        _keeperGauges.remove(pool);
        IKeeperGauge(keeperGauge).kill();
        // Do not delete from the gauges map to allow claiming of remaining balances
        emit KeeperGaugeDelisted(pool, keeperGauge);
    }

    function _ensurePoolExists(address lpToken) internal view {
        require(
            address(addressProvider.safeGetPoolForToken(lpToken)) != address(0),
            Error.ADDRESS_NOT_FOUND
        );
    }

    function _getKeeperGaugeKey(address pool) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_KEEPER_WEIGHT_KEY, pool));
    }

    function _getAmmGaugeKey(address token) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_AMM_WEIGHT_KEY, token));
    }

    function _getLpStakerVaultKey(address vault) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_LP_WEIGHT_KEY, vault));
    }
}


// File: KeeperGauge.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/IController.sol";
import "../../interfaces/tokenomics/IKeeperGauge.sol";

import "../../libraries/ScaledMath.sol";
import "../../libraries/Errors.sol";
import "../../libraries/AddressProviderHelpers.sol";
import "../../libraries/UncheckedMath.sol";

import "../access/Authorization.sol";

contract KeeperGauge is IKeeperGauge, Authorization {
    using AddressProviderHelpers for IAddressProvider;
    using ScaledMath for uint256;
    using UncheckedMath for uint256;

    struct KeeperRecord {
        mapping(uint256 => uint256) feesInPeriod;
        uint256 nextEpochToClaim;
        bool firstEpochSet;
    }

    mapping(address => KeeperRecord) public keeperRecords;
    mapping(uint256 => uint256) public perPeriodTotalFees;

    IController public immutable controller;
    address public immutable pool;
    uint256 public epoch;

    uint48 public lastUpdated;
    mapping(uint256 => uint256) public perPeriodTotalInflation;

    bool public override killed;

    modifier onlyInflationManager() {
        require(msg.sender == address(controller.inflationManager()), Error.UNAUTHORIZED_ACCESS);
        _;
    }

    constructor(IController _controller, address _pool)
        Authorization(_controller.addressProvider().getRoleManager())
    {
        controller = _controller;
        pool = _pool;
        lastUpdated = uint48(block.timestamp);
    }

    /**
     * @notice Shut down the gauge.
     * @dev Accrued inflation can still be claimed from the gauge after shutdown.
     * @return `true` if successful.
     */
    function kill() external override onlyInflationManager returns (bool) {
        poolCheckpoint();
        epoch++;
        killed = true;
        return true;
    }

    /**
     * @notice Report fees generated by a keeper (this is the basis for inflation accrual).
     * @dev lpTokenAddress is included for forward compatibility with a single gauge solution.
     * @param beneficiary Address of the keeper who earned the fees.
     * @param amount Amount of fees (in lp tokens) earned.
     * @param lpTokenAddress Address of the lpToken in which the fees are paid.
     * @return `true` if successful.
     */
    function reportFees(
        address beneficiary,
        uint256 amount,
        address lpTokenAddress
    ) external override returns (bool) {
        lpTokenAddress; // silencing compiler warning
        require(
            IController(controller).addressProvider().isWhiteListedFeeHandler(msg.sender),
            Error.ADDRESS_NOT_WHITELISTED
        );
        require(!killed, Error.CONTRACT_PAUSED);
        if (!keeperRecords[beneficiary].firstEpochSet) {
            keeperRecords[beneficiary].firstEpochSet = true;
            keeperRecords[beneficiary].nextEpochToClaim = epoch;
        }
        keeperRecords[beneficiary].feesInPeriod[epoch] += amount;
        perPeriodTotalFees[epoch] += amount;
        return true;
    }

    /**
     * @notice Advance the inflation accrual epoch.
     * @return `true` if successful.
     */
    function advanceEpoch() external virtual override onlyInflationManager returns (bool) {
        poolCheckpoint();
        epoch++;
        return true;
    }

    function claimRewards(address beneficiary) external override returns (uint256) {
        return claimRewards(beneficiary, epoch);
    }

    function claimableRewards(address beneficiary) external view override returns (uint256) {
        return _calcTotalClaimable(beneficiary, keeperRecords[beneficiary].nextEpochToClaim, epoch);
    }

    function poolCheckpoint() public override returns (bool) {
        if (killed) return false;
        uint256 timeElapsed = block.timestamp - uint256(lastUpdated);
        uint256 currentRate = IController(controller).inflationManager().getKeeperRateForPool(pool);
        perPeriodTotalInflation[epoch] += currentRate * timeElapsed;
        lastUpdated = uint48(block.timestamp);
        return true;
    }

    /**
     * @notice Claim rewards with an epoch up to which they should be claimed specified.
     * @param beneficiary Address to claim rewards for.
     * @param endEpoch Epoch up to which to claim rewards.
     * @return The amount of rewards claimed.
     */
    function claimRewards(address beneficiary, uint256 endEpoch) public override returns (uint256) {
        require(
            msg.sender == beneficiary || _roleManager().hasRole(Roles.GAUGE_ZAP, msg.sender),
            Error.UNAUTHORIZED_ACCESS
        );
        if (endEpoch > epoch) {
            endEpoch = epoch;
        }

        uint256 totalClaimable = _calcTotalClaimable(
            beneficiary,
            keeperRecords[beneficiary].nextEpochToClaim,
            endEpoch
        );
        keeperRecords[beneficiary].nextEpochToClaim = endEpoch;
        require(totalClaimable > 0, Error.ZERO_TRANSFER_NOT_ALLOWED);
        _mintRewards(beneficiary, totalClaimable);

        return totalClaimable;
    }

    function _mintRewards(address beneficiary, uint256 amount) internal returns (bool) {
        IController(controller).inflationManager().mintRewards(beneficiary, amount);
        return true;
    }

    function _calcTotalClaimable(
        address beneficiary,
        uint256 startEpoch,
        uint256 endEpoch
    ) internal view returns (uint256) {
        uint256 totalClaimable;
        for (uint256 i = startEpoch; i < endEpoch; i = i.uncheckedInc()) {
            totalClaimable += (
                keeperRecords[beneficiary].feesInPeriod[i].scaledDiv(perPeriodTotalFees[i])
            ).scaledMul(perPeriodTotalInflation[i]);
        }
        return totalClaimable;
    }
}


// File: LpGauge.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "../../interfaces/IStakerVault.sol";
import "../../interfaces/IController.sol";
import "../../interfaces/tokenomics/ILpGauge.sol";
import "../../interfaces/tokenomics/IRewardsGauge.sol";

import "../../libraries/ScaledMath.sol";
import "../../libraries/Errors.sol";
import "../../libraries/AddressProviderHelpers.sol";

import "../access/Authorization.sol";

contract LpGauge is ILpGauge, IRewardsGauge, Authorization {
    using AddressProviderHelpers for IAddressProvider;
    using ScaledMath for uint256;

    IController public immutable controller;
    IStakerVault public immutable stakerVault;
    IInflationManager public immutable inflationManager;

    uint256 public poolStakedIntegral;
    uint256 public poolLastUpdate;
    mapping(address => uint256) public perUserStakedIntegral;
    mapping(address => uint256) public perUserShare;

    constructor(IController _controller, address _stakerVault)
        Authorization(_controller.addressProvider().getRoleManager())
    {
        require(_stakerVault != address(0), Error.ZERO_ADDRESS_NOT_ALLOWED);
        controller = IController(_controller);
        stakerVault = IStakerVault(_stakerVault);
        IInflationManager _inflationManager = IController(_controller).inflationManager();
        require(address(_inflationManager) != address(0), Error.ZERO_ADDRESS_NOT_ALLOWED);
        inflationManager = _inflationManager;
    }

    /**
     * @notice Checkpoint function for the pool statistics.
     * @return `true` if successful.
     */
    function poolCheckpoint() external override returns (bool) {
        return _poolCheckpoint();
    }

    /**
     * @notice Calculates the token rewards a user should receive and mints these.
     * @param beneficiary Address to claim rewards for.
     * @return `true` if success.
     */
    function claimRewards(address beneficiary) external override returns (uint256) {
        require(
            msg.sender == beneficiary || _roleManager().hasRole(Roles.GAUGE_ZAP, msg.sender),
            Error.UNAUTHORIZED_ACCESS
        );
        userCheckpoint(beneficiary);
        uint256 amount = perUserShare[beneficiary];
        if (amount <= 0) return 0;
        perUserShare[beneficiary] = 0;
        _mintRewards(beneficiary, amount);
        return amount;
    }

    function claimableRewards(address beneficiary) external view override returns (uint256) {
        uint256 poolTotalStaked = stakerVault.getPoolTotalStaked();
        uint256 poolStakedIntegral_ = poolStakedIntegral;
        if (poolTotalStaked > 0) {
            poolStakedIntegral_ += (inflationManager.getLpRateForStakerVault(address(stakerVault)) *
                (block.timestamp - poolLastUpdate)).scaledDiv(poolTotalStaked);
        }

        return
            perUserShare[beneficiary] +
            stakerVault.stakedAndActionLockedBalanceOf(beneficiary).scaledMul(
                poolStakedIntegral_ - perUserStakedIntegral[beneficiary]
            );
    }

    /**
     * @notice Checkpoint function for the statistics for a particular user.
     * @param user Address of the user to checkpoint.
     * @return `true` if successful.
     */
    function userCheckpoint(address user) public override returns (bool) {
        _poolCheckpoint();

        // No checkpoint for the actions and strategies, since this does not accumulate tokens
        if (
            IController(controller).addressProvider().isAction(user) || stakerVault.isStrategy(user)
        ) {
            return false;
        }
        uint256 poolStakedIntegral_ = poolStakedIntegral;
        perUserShare[user] += (
            (stakerVault.stakedAndActionLockedBalanceOf(user)).scaledMul(
                (poolStakedIntegral_ - perUserStakedIntegral[user])
            )
        );

        perUserStakedIntegral[user] = poolStakedIntegral_;

        return true;
    }

    function _mintRewards(address beneficiary, uint256 amount) internal {
        inflationManager.mintRewards(beneficiary, amount);
    }

    function _poolCheckpoint() internal returns (bool) {
        uint256 currentRate = inflationManager.getLpRateForStakerVault(address(stakerVault));
        // Update the integral of total token supply for the pool
        uint256 poolTotalStaked = stakerVault.getPoolTotalStaked();
        if (poolTotalStaked > 0) {
            poolStakedIntegral += (currentRate * (block.timestamp - poolLastUpdate)).scaledDiv(
                poolTotalStaked
            );
        }
        poolLastUpdate = block.timestamp;
        return true;
    }
}


// File: Minter.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../../interfaces/IController.sol";
import "../../interfaces/tokenomics/IBkdToken.sol";
import "../../interfaces/tokenomics/IMinter.sol";

import "../../libraries/Errors.sol";
import "../../libraries/ScaledMath.sol";
import "../../libraries/AddressProviderHelpers.sol";

import "./BkdToken.sol";
import "../access/Authorization.sol";

contract Minter is IMinter, Authorization, ReentrancyGuard {
    using ScaledMath for uint256;
    using AddressProviderHelpers for IAddressProvider;

    uint256 private constant _INFLATION_DECAY_PERIOD = 365 days;

    // Lp Rates
    uint256 public immutable initialAnnualInflationRateLp;
    uint256 public immutable annualInflationDecayLp;
    uint256 public currentInflationAmountLp;

    // Keeper Rates
    uint256 public immutable initialPeriodKeeperInflation;
    uint256 public immutable initialAnnualInflationRateKeeper;
    uint256 public immutable annualInflationDecayKeeper;
    uint256 public currentInflationAmountKeeper;

    // AMM Rates
    uint256 public immutable initialPeriodAmmInflation;
    uint256 public immutable initialAnnualInflationRateAmm;
    uint256 public immutable annualInflationDecayAmm;
    uint256 public currentInflationAmountAmm;

    bool public initialPeriodEnded;

    // Non-inflation rates
    uint256 public immutable nonInflationDistribution;
    uint256 public issuedNonInflationSupply;

    uint256 public lastInflationDecay;
    uint256 public currentTotalInflation;

    // Used for final safety check to ensure inflation is not exceeded
    uint256 public totalAvailableToNow;
    uint256 public totalMintedToNow;
    uint256 public lastEvent;

    IController public immutable controller;
    BkdToken public token;

    event TokensMinted(address beneficiary, uint256 amount);

    constructor(
        uint256 _annualInflationRateLp,
        uint256 _annualInflationRateKeeper,
        uint256 _annualInflationRateAmm,
        uint256 _annualInflationDecayLp,
        uint256 _annualInflationDecayKeeper,
        uint256 _annualInflationDecayAmm,
        uint256 _initialPeriodKeeperInflation,
        uint256 _initialPeriodAmmInflation,
        uint256 _nonInflationDistribution,
        IController _controller
    ) Authorization(_controller.addressProvider().getRoleManager()) {
        require(_annualInflationDecayLp < ScaledMath.ONE, Error.INVALID_PARAMETER_VALUE);
        require(_annualInflationDecayKeeper < ScaledMath.ONE, Error.INVALID_PARAMETER_VALUE);
        require(_annualInflationDecayAmm < ScaledMath.ONE, Error.INVALID_PARAMETER_VALUE);
        initialAnnualInflationRateLp = _annualInflationRateLp;
        initialAnnualInflationRateKeeper = _annualInflationRateKeeper;
        initialAnnualInflationRateAmm = _annualInflationRateAmm;

        annualInflationDecayLp = _annualInflationDecayLp;
        annualInflationDecayKeeper = _annualInflationDecayKeeper;
        annualInflationDecayAmm = _annualInflationDecayAmm;

        initialPeriodKeeperInflation = _initialPeriodKeeperInflation;
        initialPeriodAmmInflation = _initialPeriodAmmInflation;

        currentInflationAmountLp = _annualInflationRateLp / _INFLATION_DECAY_PERIOD;
        currentInflationAmountKeeper = _initialPeriodKeeperInflation / _INFLATION_DECAY_PERIOD;
        currentInflationAmountAmm = _initialPeriodAmmInflation / _INFLATION_DECAY_PERIOD;

        currentTotalInflation =
            currentInflationAmountLp +
            currentInflationAmountKeeper +
            currentInflationAmountAmm;

        nonInflationDistribution = _nonInflationDistribution;
        controller = _controller;
    }

    function setToken(address _token) external override onlyGovernance {
        require(address(token) == address(0), "Token already set!");
        token = BkdToken(_token);
    }

    function startInflation() external override onlyGovernance {
        require(lastEvent == 0, "Inflation has already started.");
        lastEvent = block.timestamp;
        lastInflationDecay = block.timestamp;
    }

    /**
     * @notice Update the inflation rate according to the piecewise linear schedule.
     * @dev This updates the inflation rate to the next linear segment in the inflations schedule.
     * @return `true` if successful.
     */
    function executeInflationRateUpdate() external override returns (bool) {
        return _executeInflationRateUpdate();
    }

    /**
     * @notice Mints BKD tokens to a specified address.
     * @dev Can only be called by the controller.
     * @param beneficiary Address to mint tokens for.
     * @param amount Amount of tokens to mint.
     * @return `true` if successful.
     */
    function mint(address beneficiary, uint256 amount)
        external
        override
        nonReentrant
        returns (bool)
    {
        require(msg.sender == address(controller.inflationManager()), Error.UNAUTHORIZED_ACCESS);
        if (lastEvent == 0) return false;
        return _mint(beneficiary, amount);
    }

    /**
     * @notice Mint tokens that are not part of the inflation schedule.
     * @dev The amount of tokens that can be minted in total is subject to a pre-set upper limit.
     * @param beneficiary Address to mint tokens for.
     * @param amount Amount of tokens to mint.
     * @return `true` if successful.
     */
    function mintNonInflationTokens(address beneficiary, uint256 amount)
        external
        override
        onlyGovernance
        returns (bool)
    {
        require(
            issuedNonInflationSupply + amount <= nonInflationDistribution,
            "Maximum non-inflation amount exceeded."
        );
        issuedNonInflationSupply += amount;
        token.mint(beneficiary, amount);
        emit TokensMinted(beneficiary, amount);
        return true;
    }

    /**
     * @notice Supplies the inflation rate for LPs per unit of time (seconds).
     * @return LP inflation rate.
     */
    function getLpInflationRate() external view override returns (uint256) {
        if (lastEvent == 0) return 0;
        return currentInflationAmountLp;
    }

    /**
     * @notice Supplies the inflation rate for keepers per unit of time (seconds).
     * @return keeper inflation rate.
     */
    function getKeeperInflationRate() external view override returns (uint256) {
        if (lastEvent == 0) return 0;
        return currentInflationAmountKeeper;
    }

    /**
     * @notice Supplies the inflation rate for LPs on AMMs per unit of time (seconds).
     * @return AMM inflation rate.
     */
    function getAmmInflationRate() external view override returns (uint256) {
        if (lastEvent == 0) return 0;
        return currentInflationAmountAmm;
    }

    function _executeInflationRateUpdate() internal returns (bool) {
        totalAvailableToNow += (currentTotalInflation * (block.timestamp - lastEvent));
        lastEvent = block.timestamp;
        if (block.timestamp >= lastInflationDecay + _INFLATION_DECAY_PERIOD) {
            currentInflationAmountLp = currentInflationAmountLp.scaledMul(annualInflationDecayLp);
            if (initialPeriodEnded) {
                currentInflationAmountKeeper = currentInflationAmountKeeper.scaledMul(
                    annualInflationDecayKeeper
                );
                currentInflationAmountAmm = currentInflationAmountAmm.scaledMul(
                    annualInflationDecayAmm
                );
            } else {
                currentInflationAmountKeeper =
                    initialAnnualInflationRateKeeper /
                    _INFLATION_DECAY_PERIOD;

                currentInflationAmountAmm = initialAnnualInflationRateAmm / _INFLATION_DECAY_PERIOD;
                initialPeriodEnded = true;
            }
            currentTotalInflation =
                currentInflationAmountLp +
                currentInflationAmountKeeper +
                currentInflationAmountAmm;
            controller.inflationManager().checkpointAllGauges();
            lastInflationDecay = block.timestamp;
        }
        return true;
    }

    function _mint(address beneficiary, uint256 amount) internal returns (bool) {
        totalAvailableToNow += ((block.timestamp - lastEvent) * currentTotalInflation);
        uint256 newTotalMintedToNow = totalMintedToNow + amount;
        require(newTotalMintedToNow <= totalAvailableToNow, "Mintable amount exceeded");
        totalMintedToNow = newTotalMintedToNow;
        lastEvent = block.timestamp;
        token.mint(beneficiary, amount);
        _executeInflationRateUpdate();
        emit TokensMinted(beneficiary, amount);
        return true;
    }
}


// File: VestedEscrow.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

/*
Rewrite of Convex Finance's Vested Escrow
found at https://github.com/convex-eth/platform/blob/main/contracts/contracts/VestedEscrow.sol
Changes:
- remove safe math (default from Solidity >=0.8)
- remove claim and stake logic
- remove safeTransferFrom logic and add support for "airdropped" reward token
*/

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../../interfaces/tokenomics/IVestedEscrow.sol";

import "../../libraries/Errors.sol";
import "../../libraries/UncheckedMath.sol";

contract EscrowTokenHolder {
    constructor(address rewardToken_) {
        IERC20(rewardToken_).approve(msg.sender, type(uint256).max);
    }
}

contract VestedEscrow is IVestedEscrow, ReentrancyGuard {
    using UncheckedMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public immutable rewardToken;
    address public admin;
    address public fundAdmin;

    uint256 public immutable startTime;
    uint256 public immutable endTime;
    uint256 public totalTime;
    uint256 public initialLockedSupply;
    uint256 public unallocatedSupply;
    bool public initializedSupply;

    mapping(address => uint256) public initialLocked;
    mapping(address => uint256) public totalClaimed;
    mapping(address => address) public holdingContract;

    event Fund(address indexed recipient, uint256 reward);
    event Claim(address indexed user, uint256 amount);

    constructor(
        address rewardToken_,
        uint256 starttime_,
        uint256 endtime_,
        address fundAdmin_
    ) {
        require(starttime_ >= block.timestamp, "start must be future");
        require(endtime_ > starttime_, "end must be greater");

        rewardToken = IERC20(rewardToken_);
        startTime = starttime_;
        endTime = endtime_;
        totalTime = endtime_ - starttime_;
        admin = msg.sender;
        fundAdmin = fundAdmin_;
    }

    function setAdmin(address _admin) external override {
        require(_admin != address(0), Error.ZERO_ADDRESS_NOT_ALLOWED);
        require(msg.sender == admin, Error.UNAUTHORIZED_ACCESS);
        admin = _admin;
    }

    function setFundAdmin(address _fundadmin) external override {
        require(_fundadmin != address(0), Error.ZERO_ADDRESS_NOT_ALLOWED);
        require(msg.sender == admin, Error.UNAUTHORIZED_ACCESS);
        fundAdmin = _fundadmin;
    }

    function initializeUnallocatedSupply() external override returns (bool) {
        require(msg.sender == admin, Error.UNAUTHORIZED_ACCESS);
        require(!initializedSupply, "Supply already initialized once");
        unallocatedSupply = rewardToken.balanceOf(address(this));
        require(unallocatedSupply > 0, "No reward tokens in contract");
        initializedSupply = true;
        return true;
    }

    function fund(FundingAmount[] calldata amounts) external override nonReentrant returns (bool) {
        require(msg.sender == fundAdmin || msg.sender == admin, Error.UNAUTHORIZED_ACCESS);
        require(initializedSupply, "Supply must be initialized");

        uint256 totalAmount;
        for (uint256 i; i < amounts.length; i = i.uncheckedInc()) {
            uint256 amount = amounts[i].amount;
            address recipient_ = amounts[i].recipient;
            address holdingAddress = holdingContract[recipient_];
            if (holdingAddress == address(0)) {
                holdingAddress = address(new EscrowTokenHolder(address(rewardToken)));
                holdingContract[recipient_] = holdingAddress;
            }
            rewardToken.safeTransfer(holdingAddress, amount);
            initialLocked[recipient_] = initialLocked[recipient_] + amount;
            totalAmount = totalAmount + amount;
            emit Fund(recipient_, amount);
        }

        initialLockedSupply = initialLockedSupply + totalAmount;
        unallocatedSupply = unallocatedSupply - totalAmount;
        return true;
    }

    function claim() external virtual override {
        _claimUntil(msg.sender, block.timestamp);
    }

    function vestedSupply() external view override returns (uint256) {
        return _totalVested();
    }

    function lockedSupply() external view override returns (uint256) {
        return initialLockedSupply - _totalVested();
    }

    function vestedOf(address _recipient) external view virtual override returns (uint256) {
        return _totalVestedOf(_recipient, block.timestamp);
    }

    function balanceOf(address _recipient) external view virtual override returns (uint256) {
        return _balanceOf(_recipient, block.timestamp);
    }

    function lockedOf(address _recipient) external view virtual override returns (uint256) {
        uint256 vested = _totalVestedOf(_recipient, block.timestamp);
        return initialLocked[_recipient] - vested;
    }

    function claim(address _recipient) public virtual override nonReentrant {
        _claimUntil(_recipient, block.timestamp);
    }

    function _claimUntil(address _recipient, uint256 _time) internal {
        uint256 claimable = _balanceOf(msg.sender, _time);
        if (claimable == 0) return;
        totalClaimed[msg.sender] = totalClaimed[msg.sender] + claimable;
        rewardToken.safeTransferFrom(holdingContract[msg.sender], _recipient, claimable);

        emit Claim(msg.sender, claimable);
    }

    function _computeVestedAmount(uint256 locked, uint256 _time) internal view returns (uint256) {
        if (_time < startTime) {
            return 0;
        }
        uint256 elapsed = _time - startTime;
        return Math.min((locked * elapsed) / totalTime, locked);
    }

    function _totalVestedOf(address _recipient, uint256 _time) internal view returns (uint256) {
        return _computeVestedAmount(initialLocked[_recipient], _time);
    }

    function _totalVested() internal view returns (uint256) {
        return _computeVestedAmount(initialLockedSupply, block.timestamp);
    }

    function _balanceOf(address _recipient, uint256 _time) internal view returns (uint256) {
        uint256 vested = _totalVestedOf(_recipient, _time);
        return vested - totalClaimed[_recipient];
    }
}


// File: VestedEscrowRevocable.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

/*
Rewrite of Convex Finance's Vested Escrow
found at https://github.com/convex-eth/platform/blob/main/contracts/contracts/VestedEscrow.sol
Changes:
- remove safe math (default from Solidity >=0.8)
- remove claim and stake logic
- remove safeTransferFrom logic and add support for "airdropped" reward token
- add revoke logic to allow admin to stop vesting for a recipient
*/

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../../interfaces/tokenomics/IVestedEscrowRevocable.sol";

import "../../libraries/Errors.sol";

import "./VestedEscrow.sol";

contract VestedEscrowRevocable is IVestedEscrowRevocable, VestedEscrow {
    using SafeERC20 for IERC20;

    address public immutable treasury;

    uint256 private _vestedBefore;

    mapping(address => uint256) public revokedTime;

    event Revoked(address indexed user, uint256 revokedAmount);

    constructor(
        address rewardToken_,
        uint256 starttime_,
        uint256 endtime_,
        address fundAdmin_,
        address treasury_
    ) VestedEscrow(rewardToken_, starttime_, endtime_, fundAdmin_) {
        treasury = treasury_;
        holdingContract[treasury_] = address(new EscrowTokenHolder(rewardToken_));
    }

    function claim() external override {
        claim(msg.sender);
    }

    function revoke(address _recipient) external returns (bool) {
        require(msg.sender == admin, Error.UNAUTHORIZED_ACCESS);
        require(revokedTime[_recipient] == 0, "Recipient already revoked");
        require(_recipient != treasury, "Treasury cannot be revoked!");
        revokedTime[_recipient] = block.timestamp;
        uint256 vested = _totalVestedOf(_recipient, block.timestamp);

        uint256 initialAmount = initialLocked[_recipient];
        uint256 revokedAmount = initialAmount - vested;
        rewardToken.safeTransferFrom(
            holdingContract[_recipient],
            holdingContract[treasury],
            revokedAmount
        );
        initialLocked[treasury] += initialAmount;
        totalClaimed[treasury] += vested;
        _vestedBefore += vested;
        emit Revoked(_recipient, revokedAmount);
        return true;
    }

    function vestedOf(address _recipient) external view override returns (uint256) {
        if (_recipient == treasury) {
            return _totalVestedOf(_recipient, block.timestamp) - _vestedBefore;
        }

        uint256 timeRevoked = revokedTime[_recipient];
        if (timeRevoked != 0) {
            return _totalVestedOf(_recipient, timeRevoked);
        }
        return _totalVestedOf(_recipient, block.timestamp);
    }

    function balanceOf(address _recipient) external view override returns (uint256) {
        uint256 timestamp = block.timestamp;
        uint256 timeRevoked = revokedTime[_recipient];
        if (timeRevoked != 0) {
            timestamp = timeRevoked;
        }
        return _balanceOf(_recipient, timestamp);
    }

    function lockedOf(address _recipient) external view override returns (uint256) {
        if (revokedTime[_recipient] != 0) {
            return 0;
        }
        uint256 vested = _totalVestedOf(_recipient, block.timestamp);
        return initialLocked[_recipient] - vested;
    }

    function claim(address _recipient) public override nonReentrant {
        uint256 timestamp = block.timestamp;
        if (revokedTime[msg.sender] != 0) {
            timestamp = revokedTime[msg.sender];
        }
        _claimUntil(_recipient, timestamp);
    }
}


// File: CvxMintAmount.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../libraries/UncheckedMath.sol";

abstract contract CvxMintAmount {
    using UncheckedMath for uint256;

    uint256 private constant _CLIFF_SIZE = 100000 * 1e18; //new cliff every 100,000 tokens
    uint256 private constant _CLIFF_COUNT = 1000; // 1,000 cliffs
    uint256 private constant _MAX_SUPPLY = 100000000 * 1e18; //100 mil max supply
    IERC20 private constant _CVX_TOKEN =
        IERC20(address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B)); // CVX Token

    function getCvxMintAmount(uint256 crvEarned) public view returns (uint256) {
        //first get total supply
        uint256 cvxTotalSupply = _CVX_TOKEN.totalSupply();

        //get current cliff
        uint256 currentCliff = cvxTotalSupply / _CLIFF_SIZE;

        //if current cliff is under the max
        if (currentCliff >= _CLIFF_COUNT) return 0;

        //get remaining cliffs
        uint256 remaining = _CLIFF_COUNT.uncheckedSub(currentCliff);

        //multiply ratio of remaining cliffs to total cliffs against amount CRV received
        uint256 cvxEarned = (crvEarned * remaining) / _CLIFF_COUNT;

        //double check we have not gone over the max supply
        uint256 amountTillMax = _MAX_SUPPLY - cvxTotalSupply;
        if (cvxEarned > amountTillMax) cvxEarned = amountTillMax;
        return cvxEarned;
    }
}


// File: Preparable.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "../../interfaces/IPreparable.sol";
import "../../libraries/Errors.sol";

/**
 * @notice Implements the base logic for a two-phase commit
 * @dev This does not implements any access-control so publicly exposed
 * callers should make sure to have the proper checks in place
 */
contract Preparable is IPreparable {
    uint256 private constant _MIN_DELAY = 3 days;

    mapping(bytes32 => address) public pendingAddresses;
    mapping(bytes32 => uint256) public pendingUInts256;

    mapping(bytes32 => address) public currentAddresses;
    mapping(bytes32 => uint256) public currentUInts256;

    /**
     * @dev Deadlines shares the same namespace regardless of the type
     * of the pending variable so this needs to be enforced in the caller
     */
    mapping(bytes32 => uint256) public deadlines;

    function _prepareDeadline(bytes32 key, uint256 delay) internal {
        require(deadlines[key] == 0, Error.DEADLINE_NOT_ZERO);
        require(delay >= _MIN_DELAY, Error.DELAY_TOO_SHORT);
        deadlines[key] = block.timestamp + delay;
    }

    /**
     * @notice Prepares an uint256 that should be committed to the contract
     * after `_MIN_DELAY` elapsed
     * @param value The value to prepare
     * @return `true` if success.
     */
    function _prepare(
        bytes32 key,
        uint256 value,
        uint256 delay
    ) internal returns (bool) {
        _prepareDeadline(key, delay);
        pendingUInts256[key] = value;
        emit ConfigPreparedNumber(key, value, delay);
        return true;
    }

    /**
     * @notice Same as `_prepare(bytes32,uint256,uint256)` but uses a default delay
     */
    function _prepare(bytes32 key, uint256 value) internal returns (bool) {
        return _prepare(key, value, _MIN_DELAY);
    }

    /**
     * @notice Prepares an address that should be committed to the contract
     * after `_MIN_DELAY` elapsed
     * @param value The value to prepare
     * @return `true` if success.
     */
    function _prepare(
        bytes32 key,
        address value,
        uint256 delay
    ) internal returns (bool) {
        _prepareDeadline(key, delay);
        pendingAddresses[key] = value;
        emit ConfigPreparedAddress(key, value, delay);
        return true;
    }

    /**
     * @notice Same as `_prepare(bytes32,address,uint256)` but uses a default delay
     */
    function _prepare(bytes32 key, address value) internal returns (bool) {
        return _prepare(key, value, _MIN_DELAY);
    }

    /**
     * @notice Reset a uint256 key
     * @return `true` if success.
     */
    function _resetUInt256Config(bytes32 key) internal returns (bool) {
        require(deadlines[key] != 0, Error.NOTHING_PENDING);
        deadlines[key] = 0;
        pendingUInts256[key] = 0;
        emit ConfigReset(key);
        return true;
    }

    /**
     * @notice Reset an address key
     * @return `true` if success.
     */
    function _resetAddressConfig(bytes32 key) internal returns (bool) {
        require(deadlines[key] != 0, Error.NOTHING_PENDING);
        deadlines[key] = 0;
        pendingAddresses[key] = address(0);
        emit ConfigReset(key);
        return true;
    }

    /**
     * @dev Checks the deadline of the key and reset it
     */
    function _executeDeadline(bytes32 key) internal {
        uint256 deadline = deadlines[key];
        require(block.timestamp >= deadline, Error.DEADLINE_NOT_REACHED);
        require(deadline != 0, Error.DEADLINE_NOT_SET);
        deadlines[key] = 0;
    }

    /**
     * @notice Execute uint256 config update (with time delay enforced).
     * @dev Needs to be called after the update was prepared. Fails if called before time delay is met.
     * @return New value.
     */
    function _executeUInt256(bytes32 key) internal returns (uint256) {
        _executeDeadline(key);
        uint256 newValue = pendingUInts256[key];
        _setConfig(key, newValue);
        return newValue;
    }

    /**
     * @notice Execute address config update (with time delay enforced).
     * @dev Needs to be called after the update was prepared. Fails if called before time delay is met.
     * @return New value.
     */
    function _executeAddress(bytes32 key) internal returns (address) {
        _executeDeadline(key);
        address newValue = pendingAddresses[key];
        _setConfig(key, newValue);
        return newValue;
    }

    function _setConfig(bytes32 key, address value) internal returns (address) {
        emit ConfigUpdatedAddress(key, currentAddresses[key], value);
        currentAddresses[key] = value;
        pendingAddresses[key] = address(0);
        deadlines[key] = 0;
        return value;
    }

    function _setConfig(bytes32 key, uint256 value) internal returns (uint256) {
        uint256 oldValue = currentUInts256[key];
        currentUInts256[key] = value;
        pendingUInts256[key] = 0;
        deadlines[key] = 0;
        emit ConfigUpdatedNumber(key, oldValue, value);
        return value;
    }
}


// File: PoolMigrationZap.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/zaps/IPoolMigrationZap.sol";
import "../../interfaces/IAddressProvider.sol";
import "../../interfaces/pool/ILiquidityPool.sol";

/**
 * This is a Zap contract to assist in the migration from the V1 Backd Pools to the new Backd Pools.
 */
contract PoolMigrationZap is IPoolMigrationZap {
    using SafeERC20 for IERC20;

    mapping(address => ILiquidityPool) internal _underlyingNewPools; // A mapping from underlyings to new pools

    event Migrated(address user, address oldPool, address newPool, uint256 lpTokenAmount); // Emitted when a migration is completed

    constructor(address newAddressProviderAddress_) {
        address[] memory newPools_ = IAddressProvider(newAddressProviderAddress_).allPools();
        for (uint256 i; i < newPools_.length; ++i) {
            ILiquidityPool newPool_ = ILiquidityPool(newPools_[i]);
            address underlying_ = newPool_.getUnderlying();
            _underlyingNewPools[underlying_] = newPool_;
            if (underlying_ == address(0)) continue;
            IERC20(underlying_).safeApprove(address(newPool_), type(uint256).max);
        }
    }

    receive() external payable {}

    /**
     * @notice Migrates all of a users balance from the old pools to the new pools.
     * @dev The user must have balance in all pools given, otherwise transaction will revert.
     * @param oldPoolAddresses_ The list of old pools to migrate for the user.
     */
    function migrateAll(address[] calldata oldPoolAddresses_) external override {
        for (uint256 i; i < oldPoolAddresses_.length; ) {
            migrate(oldPoolAddresses_[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Migrates a users balance from an old pool to a new pool.
     * @dev The user must have balance in the pool given, otherwise transaction will revert.
     * @param oldPoolAddress_ The old pool to migrate for the user.
     */
    function migrate(address oldPoolAddress_) public override {
        ILiquidityPool oldPool_ = ILiquidityPool(oldPoolAddress_);
        IERC20 lpToken_ = IERC20(oldPool_.getLpToken());
        uint256 lpTokenAmount_ = lpToken_.balanceOf(msg.sender);
        require(lpTokenAmount_ != 0, "No LP Tokens");
        require(oldPool_.getWithdrawalFee(msg.sender, lpTokenAmount_) == 0, "withdrawal fee not 0");
        lpToken_.safeTransferFrom(msg.sender, address(this), lpTokenAmount_);
        uint256 underlyingAmount_ = oldPool_.redeem(lpTokenAmount_);
        address underlying_ = oldPool_.getUnderlying();
        ILiquidityPool newPool_ = _underlyingNewPools[underlying_];
        uint256 ethValue_ = underlying_ == address(0) ? underlyingAmount_ : 0;
        newPool_.depositFor{value: ethValue_}(msg.sender, underlyingAmount_);
        emit Migrated(msg.sender, address(oldPool_), address(newPool_), lpTokenAmount_);
    }
}


// File: ICurveSwap.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface ICurveSwap {
    function get_virtual_price() external view returns (uint256);

    function add_liquidity(uint256[3] calldata amounts, uint256 min_mint_amount) external;

    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount) external;

    function remove_liquidity_imbalance(uint256[3] calldata amounts, uint256 max_burn_amount)
        external;

    function remove_liquidity_imbalance(uint256[2] calldata amounts, uint256 max_burn_amount)
        external;

    function remove_liquidity(uint256 _amount, uint256[3] calldata min_amounts) external;

    function exchange(
        int128 from,
        int128 to,
        uint256 _from_amount,
        uint256 _min_to_amount
    ) external;

    function coins(uint256 i) external view returns (address);

    function get_dy(
        int128 i,
        int128 j,
        uint256 _dx
    ) external view returns (uint256);

    function calc_token_amount(uint256[4] calldata amounts, bool deposit)
        external
        view
        returns (uint256);

    function calc_token_amount(uint256[3] calldata amounts, bool deposit)
        external
        view
        returns (uint256);

    function calc_token_amount(uint256[2] calldata amounts, bool deposit)
        external
        view
        returns (uint256);

    function calc_withdraw_one_coin(uint256 _token_amount, int128 i)
        external
        view
        returns (uint256);

    function remove_liquidity_one_coin(
        uint256 _token_amount,
        int128 i,
        uint256 min_amount
    ) external;
}


// File: ICvxLocker.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface ICvxLocker {
    function getReward(address _account, bool _stake) external;

    function balanceOf(address _user) external view returns (uint256);

    function rewardData(address _token)
        external
        view
        returns (
            bool useBoost,
            uint40 periodFinish,
            uint208 rewardRate,
            uint40 lastUpdateTime,
            uint208 rewardPerTokenStored
        );

    function lock(
        address _account,
        uint256 _amount,
        uint256 _spendRatio
    ) external;

    function processExpiredLocks(bool _relock) external;

    function withdrawExpiredLocksTo(address _withdrawTo) external;

    function maximumBoostPayment() external returns (uint256);

    function setBoost(
        uint256 _max,
        uint256 _rate,
        address _receivingAddress
    ) external;

    function lockedBalanceOf(address _user) external view returns (uint256 amount);

    function checkpointEpoch() external;

    event RewardAdded(address indexed _token, uint256 _reward);
    event Staked(
        address indexed _user,
        uint256 indexed _epoch,
        uint256 _paidAmount,
        uint256 _lockedAmount,
        uint256 _boostedAmount
    );

    event Withdrawn(address indexed _user, uint256 _amount, bool _relocked);
    event KickReward(address indexed _user, address indexed _kicked, uint256 _reward);
    event RewardPaid(address indexed _user, address indexed _rewardsToken, uint256 _reward);
    event Recovered(address _token, uint256 _amount);
}


// File: UncheckedMath.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

library UncheckedMath {
    function uncheckedInc(uint256 a) internal pure returns (uint256) {
        unchecked {
            return a + 1;
        }
    }

    function uncheckedAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return a + b;
        }
    }

    function uncheckedSub(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return a - b;
        }
    }
}