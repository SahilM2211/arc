// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title PayPerUse
 * @dev Solves the real-world problem of micropayments for digital goods.
 * This contract allows a service provider (owner) to charge users
 * a small, per-use fee from their deposited balance.
 *
 * This is only economically viable on a low-fee L2 like Base.
 */
contract PayPerUse is Ownable, ReentrancyGuard {

    // --- State Variables ---
    uint256 public pricePerUse; // The price (in wei) for a single use of the service
    mapping(address => uint256) public userBalances; // Tracks each user's deposit
    uint256 public totalEarned; // Total fees collected by the provider

    // --- Events ---
    event PriceSet(uint256 newPrice);
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Charged(address indexed user, uint256 amount);
    event EarningsWithdrawn(address indexed owner, uint256 amount);

    /**
     * @dev Easy to deploy constructor.
     * The deployer becomes the owner. The owner must set the price after.
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Sets the price for a single use of the service (owner only).
     */
    function setPrice(uint256 _newPrice) public onlyOwner {
        require(_newPrice > 0, "Price must be greater than 0");
        pricePerUse = _newPrice;
        emit PriceSet(_newPrice);
    }

    /**
     * @dev Allows a user to deposit funds into the contract.
     */
    function deposit() public payable {
        require(msg.value > 0, "Deposit must be greater than 0");
        userBalances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @dev Allows the service provider (owner) to charge a user for one use.
     * This is the core logic.
     */
    function chargeUser(address _user) public onlyOwner {
        require(pricePerUse > 0, "Price has not been set");
        
        uint256 userBalance = userBalances[_user];
        require(userBalance >= pricePerUse, "User has insufficient balance");

        userBalances[_user] = userBalance - pricePerUse;
        totalEarned += pricePerUse;

        emit Charged(_user, pricePerUse);
    }

    /**
     * @dev Allows a user to withdraw their unspent balance.
     */
    function withdraw(uint256 _amount) public nonReentrant {
        uint256 userBalance = userBalances[msg.sender];
        require(_amount > 0, "Amount must be > 0");
        require(_amount <= userBalance, "Insufficient balance");

        userBalances[msg.sender] = userBalance - _amount;

        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Withdrawal failed");

        emit Withdrawn(msg.sender, _amount);
    }

    /**
     * @dev Allows the service provider (owner) to withdraw their earnings.
     */
    function providerWithdraw() public onlyOwner nonReentrant {
        uint256 amount = totalEarned;
        require(amount > 0, "No earnings to withdraw");

        totalEarned = 0;

        (bool success, ) = owner().call{value: amount}("");
        require(success, "Withdrawal failed");

        emit EarningsWithdrawn(owner(), amount);
    }

    // --- View Functions ---
    function getBalance(address _user) public view returns (uint256) {
        return userBalances[_user];
    }
}