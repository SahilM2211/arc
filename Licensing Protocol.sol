// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import ".deps/npm/@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BaseLicense Protocol
 * @dev Enterprise-grade decentralized SaaS and API licensing.
 * Replaces Stripe and centralized databases for software access.
 * Users buy time-bound cryptographic licenses. Backend servers verify access instantly.
 */
contract BaseLicense is ReentrancyGuard, Ownable {

    struct Tier {
        uint256 id;
        string name;
        uint256 price;       // Price per time block (in Wei)
        uint256 duration;    // Time block duration (in seconds, e.g., 30 days)
        bool active;         // Is this tier available for purchase?
    }

    uint256 public tierCount;
    mapping(uint256 => Tier) public tiers;

    // Mapping: Tier ID => User Wallet Address => Expiration Timestamp
    mapping(uint256 => mapping(address => uint256)) public licenseExpiration;

    // --- Events ---
    event TierCreated(uint256 indexed tierId, string name, uint256 price, uint256 duration);
    event LicensePurchased(uint256 indexed tierId, address indexed user, uint256 newExpiration);
    event LicenseTransferred(uint256 indexed tierId, address indexed from, address indexed to, uint256 timeTransferred);
    event RevenueWithdrawn(address indexed owner, uint256 amount);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev 1. Admin creates an access tier (e.g., "Pro API Access", 0.05 ETH, 30 Days).
     */
    function createTier(string memory _name, uint256 _priceWei, uint256 _durationSeconds) public onlyOwner {
        require(_priceWei > 0, "Price must be greater than 0");
        require(_durationSeconds > 0, "Duration must be greater than 0");

        uint256 id = tierCount++;
        tiers[id] = Tier({
            id: id,
            name: _name,
            price: _priceWei,
            duration: _durationSeconds,
            active: true
        });

        emit TierCreated(id, _name, _priceWei, _durationSeconds);
    }

    /**
     * @dev Admin can toggle tiers on and off (e.g., retiring a legacy pricing plan).
     */
    function toggleTier(uint256 _tierId, bool _status) public onlyOwner {
        require(_tierId < tierCount, "Invalid Tier ID");
        tiers[_tierId].active = _status;
    }

    /**
     * @dev 2. User purchases or renews their license.
     * @param _tierId The ID of the software tier.
     * @param _multiplier How many time blocks to buy (e.g., 3 = 90 days).
     */
    function buyLicense(uint256 _tierId, uint256 _multiplier) public payable nonReentrant {
        require(_tierId < tierCount, "Invalid Tier ID");
        Tier memory tier = tiers[_tierId];
        require(tier.active, "This tier is no longer available");
        require(_multiplier > 0, "Must buy at least 1 time block");
        
        uint256 totalCost = tier.price * _multiplier;
        require(msg.value == totalCost, "Incorrect ETH amount sent");

        uint256 timeToAdd = tier.duration * _multiplier;
        uint256 currentExp = licenseExpiration[_tierId][msg.sender];

        // If license is already active, stack the time. Otherwise, start from now.
        if (currentExp > block.timestamp) {
            licenseExpiration[_tierId][msg.sender] = currentExp + timeToAdd;
        } else {
            licenseExpiration[_tierId][msg.sender] = block.timestamp + timeToAdd;
        }

        emit LicensePurchased(_tierId, msg.sender, licenseExpiration[_tierId][msg.sender]);
    }

    /**
     * @dev 3. User transfers their remaining time to another wallet.
     * Prevents sharing passwords; one license = one wallet.
     */
    function transferLicense(uint256 _tierId, address _to) public {
        require(_to != address(0), "Cannot transfer to zero address");
        require(_to != msg.sender, "Cannot transfer to yourself");
        
        uint256 currentExp = licenseExpiration[_tierId][msg.sender];
        require(currentExp > block.timestamp, "License is expired or does not exist");

        uint256 remainingTime = currentExp - block.timestamp;
        
        // Strip the sender of their access
        licenseExpiration[_tierId][msg.sender] = 0;

        // Add remaining time to the receiver
        uint256 receiverExp = licenseExpiration[_tierId][_to];
        if (receiverExp > block.timestamp) {
            licenseExpiration[_tierId][_to] = receiverExp + remainingTime;
        } else {
            licenseExpiration[_tierId][_to] = block.timestamp + remainingTime;
        }

        emit LicenseTransferred(_tierId, msg.sender, _to, remainingTime);
    }

    /**
     * @dev 4. The Developer's Backend calls this free View function to check access.
     * e.g., if (contract.isValid(1, "0xUser...")) { serveData(); } else { throw 403; }
     */
    function isValid(uint256 _tierId, address _user) public view returns (bool) {
        return licenseExpiration[_tierId][_user] > block.timestamp;
    }

    /**
     * @dev View function to get exact expiration time.
     */
    function getExpiration(uint256 _tierId, address _user) public view returns (uint256) {
        return licenseExpiration[_tierId][_user];
    }

    /**
     * @dev 5. Admin withdraws SaaS revenue securely.
     */
    function withdrawRevenue() public onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No revenue to withdraw");

        (bool success, ) = owner().call{value: balance}("");
        require(success, "Transfer failed");

        emit RevenueWithdrawn(owner(), balance);
    }
}