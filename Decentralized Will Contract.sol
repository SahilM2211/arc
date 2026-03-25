// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

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