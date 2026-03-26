
// File: @openzeppelin/contracts/security/ReentrancyGuard.sol


// OpenZeppelin Contracts (last updated v4.9.0) (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }
}

// File: arc_testnet/Decentralized Will Contract.sol


pragma solidity ^0.8.20;

/**
 * @title BaseWill Protocol
 * @dev Enterprise-grade Decentralized Estate Planning.
 * Uses a "Dead Man's Switch" to automatically pass assets to heirs 
 * if the owner fails to provide "Proof of Life" within a specified timeframe.
 *
 * Math: Uses Basis Points (BPS) for exact percentages. 10000 BPS = 100.00%.
 */
contract BaseWill is ReentrancyGuard {

    struct Heir {
        address wallet;
        uint256 shareBPS; // e.g., 5000 = 50%
    }

    struct Vault {
        bool exists;
        uint256 balance;
        uint256 lastPing;
        uint256 pingInterval; // Time in seconds before presumed incapacitated
        Heir[] heirs;
    }

    // Maps a user's address to their personal inheritance vault
    mapping(address => Vault) public vaults;

    // --- Events ---
    event VaultCreated(address indexed owner, uint256 pingIntervalDays);
    event ProofOfLife(address indexed owner, uint256 timestamp);
    event VaultFunded(address indexed owner, uint256 amount);
    event InheritanceClaimed(address indexed owner, address indexed executor, uint256 totalDistributed);
    event VaultRevoked(address indexed owner, uint256 amountReturned);

    /**
     * @dev 1. Create your inheritance vault and set your beneficiaries.
     * @param _heirs Array of wallet addresses to receive funds.
     * @param _sharesBPS Array of percentages (in Basis Points) for each heir. Must sum to 10000.
     * @param _pingIntervalDays How many days you have to ping the contract before it unlocks.
     */
    function createVault(
        address[] memory _heirs,
        uint256[] memory _sharesBPS,
        uint256 _pingIntervalDays
    ) public payable {
        require(!vaults[msg.sender].exists, "Vault already exists. Revoke it first.");
        require(_heirs.length == _sharesBPS.length, "Arrays must match");
        require(_heirs.length > 0 && _heirs.length <= 10, "1 to 10 heirs allowed");
        require(_pingIntervalDays >= 30, "Minimum 30 days interval for safety");

        uint256 totalShares = 0;
        for (uint256 i = 0; i < _sharesBPS.length; i++) {
            require(_heirs[i] != address(0), "Invalid heir address");
            totalShares += _sharesBPS[i];
        }
        require(totalShares == 10000, "Total shares must exactly equal 100% (10000 BPS)");

        Vault storage vault = vaults[msg.sender];
        vault.exists = true;
        vault.balance = msg.value;
        vault.lastPing = block.timestamp;
        vault.pingInterval = _pingIntervalDays * 1 days;

        for (uint256 i = 0; i < _heirs.length; i++) {
            vault.heirs.push(Heir({
                wallet: _heirs[i],
                shareBPS: _sharesBPS[i]
            }));
        }

        emit VaultCreated(msg.sender, _pingIntervalDays);
        if (msg.value > 0) {
            emit VaultFunded(msg.sender, msg.value);
        }
    }

    /**
     * @dev 2. Fund the vault with ETH. Can be done anytime.
     */
    function fundVault() public payable {
        require(vaults[msg.sender].exists, "No vault found");
        require(msg.value > 0, "Must send ETH");

        vaults[msg.sender].balance += msg.value;
        
        // Auto-ping on fund to save a transaction
        vaults[msg.sender].lastPing = block.timestamp;

        emit VaultFunded(msg.sender, msg.value);
    }

    /**
     * @dev 3. Proof of Life. Resets the countdown timer.
     */
    function ping() public {
        require(vaults[msg.sender].exists, "No vault found");
        vaults[msg.sender].lastPing = block.timestamp;
        emit ProofOfLife(msg.sender, block.timestamp);
    }

    /**
     * @dev 4. Execute the Will. Anyone can call this IF the timer has expired.
     * Funds are instantly routed to the heirs according to the exact mathematical shares.
     * @param _vaultOwner The address of the person who created the vault.
     */
    function executeWill(address _vaultOwner) public nonReentrant {
        Vault storage vault = vaults[_vaultOwner];
        require(vault.exists, "Vault does not exist");
        require(vault.balance > 0, "Vault is empty");
        
        uint256 timeSinceLastPing = block.timestamp - vault.lastPing;
        require(timeSinceLastPing > vault.pingInterval, "Owner is still alive / Timer not expired");

        uint256 totalToDistribute = vault.balance;
        vault.balance = 0; // Prevent reentrancy

        // Distribute to heirs
        for (uint256 i = 0; i < vault.heirs.length; i++) {
            uint256 amountForHeir = (totalToDistribute * vault.heirs[i].shareBPS) / 10000;
            
            if (amountForHeir > 0) {
                (bool success, ) = vault.heirs[i].wallet.call{value: amountForHeir}("");
                require(success, "Transfer to heir failed");
            }
        }

        // Vault is practically closed, but we leave `exists` true so history remains.
        // It cannot be re-executed because balance is 0.
        emit InheritanceClaimed(_vaultOwner, msg.sender, totalToDistribute);
    }

    /**
     * @dev 5. Owner can cancel the will and withdraw all funds at any time while alive.
     */
    function revokeVault() public nonReentrant {
        Vault storage vault = vaults[msg.sender];
        require(vault.exists, "No vault found");

        uint256 amountToReturn = vault.balance;
        
        // Delete the vault entirely to reset state
        delete vaults[msg.sender];

        if (amountToReturn > 0) {
            (bool success, ) = msg.sender.call{value: amountToReturn}("");
            require(success, "Refund transfer failed");
        }

        emit VaultRevoked(msg.sender, amountToReturn);
    }

    // --- View Helpers ---

    function getHeirs(address _owner) public view returns (Heir[] memory) {
        return vaults[_owner].heirs;
    }

    function getTimeUntilUnlock(address _owner) public view returns (uint256) {
        Vault memory vault = vaults[_owner];
        if (!vault.exists) return 0;
        
        uint256 timePassed = block.timestamp - vault.lastPing;
        if (timePassed >= vault.pingInterval) {
            return 0; // Already unlocked
        }
        return vault.pingInterval - timePassed;
    }
}