// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title BaseStream Protocol
 * @dev Enterprise continuous payroll and payment streaming.
 * Funds are locked and unlocked mathematically second-by-second.
 * Solves freelance trust issues and traditional payday friction.
 */
contract BaseStream is ReentrancyGuard {

    struct Stream {
        uint256 id;
        address sender;      // Employer / Client
        address recipient;   // Employee / Freelancer
        uint256 deposit;     // Total amount locked (in Wei)
        uint256 ratePerSecond; // How much Wei unlocks every second
        uint256 startTime;
        uint256 stopTime;
        uint256 remainingBalance; // Tracks what is left to withdraw
    }

    uint256 public nextStreamId;
    mapping(uint256 => Stream) public streams;

    event StreamCreated(uint256 indexed id, address indexed sender, address indexed recipient, uint256 deposit, uint256 stopTime);
    event WithdrawnFromStream(uint256 indexed id, address indexed recipient, uint256 amount);
    event StreamCancelled(uint256 indexed id, address indexed sender, address indexed recipient, uint256 senderBalance, uint256 recipientBalance);

    /**
     * @dev 1. Employer creates a payment stream.
     * @param _recipient The employee receiving the funds.
     * @param _durationInSeconds Total duration of the contract/pay period.
     */
    function createStream(address _recipient, uint256 _durationInSeconds) public payable nonReentrant {
        require(_recipient != address(0), "Invalid recipient");
        require(_recipient != msg.sender, "Cannot stream to yourself");
        require(_durationInSeconds > 0, "Duration must be > 0");
        require(msg.value >= _durationInSeconds, "Deposit too small (must be > duration for math)");

        uint256 ratePerSecond = msg.value / _durationInSeconds;
        uint256 id = nextStreamId++;

        streams[id] = Stream({
            id: id,
            sender: msg.sender,
            recipient: _recipient,
            deposit: msg.value,
            ratePerSecond: ratePerSecond,
            startTime: block.timestamp,
            stopTime: block.timestamp + _durationInSeconds,
            remainingBalance: msg.value
        });

        emit StreamCreated(id, msg.sender, _recipient, msg.value, streams[id].stopTime);
    }

    /**
     * @dev Calculates the exact amount earned by the recipient up to this exact block timestamp.
     */
    function balanceEarned(uint256 _streamId) public view returns (uint256) {
        Stream memory stream = streams[_streamId];
        if (block.timestamp <= stream.startTime) return 0;

        // If the stream has finished, the total earned is simply the remaining balance
        if (block.timestamp >= stream.stopTime) return stream.remainingBalance;

        // Math: (Seconds Passed * Rate) - What has already been withdrawn
        uint256 timePassed = block.timestamp - stream.startTime;
        uint256 totalEarnedSoFar = timePassed * stream.ratePerSecond;
        uint256 alreadyWithdrawn = stream.deposit - stream.remainingBalance;

        return totalEarnedSoFar - alreadyWithdrawn;
    }

    /**
     * @dev 2. Employee withdraws their unlocked pay. Can be called at any time.
     */
    function withdraw(uint256 _streamId, uint256 _amount) public nonReentrant {
        Stream storage stream = streams[_streamId];
        require(stream.remainingBalance > 0, "Stream depleted or cancelled");
        require(msg.sender == stream.recipient, "Only recipient can withdraw");
        
        uint256 available = balanceEarned(_streamId);
        require(available >= _amount, "Amount exceeds unlocked balance");
        require(_amount > 0, "Amount must be > 0");

        stream.remainingBalance -= _amount;

        (bool success, ) = stream.recipient.call{value: _amount}("");
        require(success, "Transfer failed");

        emit WithdrawnFromStream(_streamId, stream.recipient, _amount);
    }

    /**
     * @dev 3. Either party can cancel. The employee instantly gets what they earned up to this second.
     * The employer gets the rest. No HR math required.
     */
    function cancelStream(uint256 _streamId) public nonReentrant {
        Stream storage stream = streams[_streamId];
        require(msg.sender == stream.sender || msg.sender == stream.recipient, "Unauthorized to cancel");
        require(stream.remainingBalance > 0, "Stream already depleted or cancelled");

        uint256 earnedAmount = balanceEarned(_streamId);
        uint256 unearnedAmount = stream.remainingBalance - earnedAmount;

        // Mark stream as depleted
        stream.remainingBalance = 0;

        // Route earned funds to Employee
        if (earnedAmount > 0) {
            (bool success1, ) = stream.recipient.call{value: earnedAmount}("");
            require(success1, "Recipient transfer failed");
        }

        // Route unearned funds back to Employer
        if (unearnedAmount > 0) {
            (bool success2, ) = stream.sender.call{value: unearnedAmount}("");
            require(success2, "Sender transfer failed");
        }

        emit StreamCancelled(_streamId, stream.sender, stream.recipient, unearnedAmount, earnedAmount);
    }

    // --- View Helpers ---
    function getStream(uint256 _streamId) public view returns (Stream memory) {
        return streams[_streamId];
    }
}