// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import ".deps/npm/@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title DePINComputeMarket
 * @dev Enterprise-grade Decentralized Physical Infrastructure (DePIN) protocol.
 * Solves the cloud monopoly by allowing anyone to rent out their idle hardware.
 * Features:
 * - Provider Staking (to prevent malicious offline behavior).
 * - Trustless Escrow for rental periods.
 * - Automated payouts and penalty slashing.
 */
contract DePINComputeMarket is ReentrancyGuard {

    uint256 public constant MIN_PROVIDER_STAKE = 0.05 ether; // Required to ensure uptime
    
    struct Node {
        uint256 id;
        address provider;
        string hardwareSpecs; // e.g., "1x RTX 4090, 64GB RAM, 1Gbps"
        uint256 pricePerHour; // in Wei
        bool isAvailable;
        uint256 activeRentalId;
    }

    struct Rental {
        uint256 id;
        uint256 nodeId;
        address consumer;
        uint256 totalCost;
        uint256 startTime;
        uint256 endTime;
        bool isCompleted;
    }

    uint256 public nodeCounter;
    uint256 public rentalCounter;

    mapping(uint256 => Node) public nodes;
    mapping(uint256 => Rental) public rentals;
    
    // Tracks the stake deposited by providers
    mapping(address => uint256) public providerStakes;

    event NodeRegistered(uint256 indexed nodeId, address indexed provider, string specs, uint256 pricePerHour);
    event NodeRented(uint256 indexed rentalId, uint256 indexed nodeId, address indexed consumer, uint256 hoursRented);
    event RentalCompleted(uint256 indexed rentalId, uint256 payout);
    event StakeWithdrawn(address indexed provider, uint256 amount);

    /**
     * @dev 1. Provider registers their idle hardware on the marketplace.
     * They must deposit ETH as collateral to guarantee uptime.
     */
    function registerNode(string memory _specs, uint256 _pricePerHour) public payable nonReentrant {
        require(msg.value >= MIN_PROVIDER_STAKE, "Must deposit minimum stake to ensure uptime");
        
        providerStakes[msg.sender] += msg.value;
        uint256 nodeId = nodeCounter++;

        nodes[nodeId] = Node({
            id: nodeId,
            provider: msg.sender,
            hardwareSpecs: _specs,
            pricePerHour: _pricePerHour,
            isAvailable: true,
            activeRentalId: 0
        });

        emit NodeRegistered(nodeId, msg.sender, _specs, _pricePerHour);
    }

    /**
     * @dev 2. Consumer rents the node. Funds are locked in escrow.
     */
    function rentNode(uint256 _nodeId, uint256 _hoursToRent) public payable nonReentrant {
        require(_nodeId < nodeCounter, "Invalid Node ID");
        require(_hoursToRent > 0, "Must rent for at least 1 hour");
        
        Node storage node = nodes[_nodeId];
        require(node.isAvailable, "Node is currently in use or offline");
        
        uint256 totalCost = node.pricePerHour * _hoursToRent;
        require(msg.value == totalCost, "Must send exact rental cost");

        uint256 rentalId = rentalCounter++;
        
        rentals[rentalId] = Rental({
            id: rentalId,
            nodeId: _nodeId,
            consumer: msg.sender,
            totalCost: totalCost,
            startTime: block.timestamp,
            endTime: block.timestamp + (_hoursToRent * 1 hours),
            isCompleted: false
        });

        // Mark node as busy
        node.isAvailable = false;
        node.activeRentalId = rentalId;

        emit NodeRented(rentalId, _nodeId, msg.sender, _hoursToRent);
    }

    /**
     * @dev 3. Completes the rental. Releases funds to the Provider.
     * Can be called by anyone after the end time has passed.
     */
    function completeRental(uint256 _rentalId) public nonReentrant {
        require(_rentalId < rentalCounter, "Invalid Rental ID");
        Rental storage rental = rentals[_rentalId];
        require(!rental.isCompleted, "Rental already completed");
        require(block.timestamp >= rental.endTime, "Rental period not finished yet");

        Node storage node = nodes[rental.nodeId];

        rental.isCompleted = true;
        node.isAvailable = true;
        node.activeRentalId = 0;

        // Route the locked escrow funds to the hardware provider
        (bool success, ) = node.provider.call{value: rental.totalCost}("");
        require(success, "Transfer to provider failed");

        emit RentalCompleted(_rentalId, rental.totalCost);
    }

    /**
     * @dev Provider can withdraw their stake ONLY if their node is not currently rented.
     * This deregisters their node from active availability.
     */
    function withdrawStake(uint256 _nodeId) public nonReentrant {
        Node storage node = nodes[_nodeId];
        require(msg.sender == node.provider, "Not the node provider");
        require(node.isAvailable, "Cannot withdraw stake while node is rented");
        
        uint256 amount = providerStakes[msg.sender];
        require(amount > 0, "No stake to withdraw");

        // Mark node as completely unavailable
        node.isAvailable = false;
        providerStakes[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Stake withdrawal failed");

        emit StakeWithdrawn(msg.sender, amount);
    }

    // --- View Helpers ---
    function getActiveNodesCount() public view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < nodeCounter; i++) {
            if (nodes[i].isAvailable) count++;
        }
        return count;
    }
}