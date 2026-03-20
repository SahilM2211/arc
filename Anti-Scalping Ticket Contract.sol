// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title BaseTicket Protocol
 * @dev Enterprise-grade Event Ticketing System.
 * Solves: Scalping, Counterfeiting, and Exorbitant Fees.
 * * Features:
 * 1. Fixed primary market price.
 * 2. Capped secondary market (e.g., max 10% markup).
 * 3. Peer-to-peer (OTC) transfers are blocked to enforce the price cap.
 * 4. Secure check-in system for event organizers.
 */
contract BaseTicket is ReentrancyGuard {

    address public organizer;
    string public eventName;
    uint256 public ticketPrice;
    uint256 public maxCapacity;
    uint256 public maxResaleMarkupPercent; // e.g., 10 means 10% max profit
    
    uint256 public totalTicketsSold;

    struct Ticket {
        uint256 id;
        address owner;
        bool isScanned;      // Has the fan entered the venue?
        bool isForSale;      // Is it listed on the secondary market?
        uint256 resalePrice; // The listing price
    }

    // Mapping from Ticket ID to Ticket Data
    mapping(uint256 => Ticket) public tickets;
    
    // Quick lookup to see how many tickets a user owns
    mapping(address => uint256[]) public userTickets;

    // --- Events ---
    event TicketPurchased(uint256 indexed ticketId, address indexed buyer);
    event TicketListed(uint256 indexed ticketId, uint256 price);
    event TicketDelisted(uint256 indexed ticketId);
    event TicketResold(uint256 indexed ticketId, address indexed oldOwner, address indexed newOwner, uint256 price);
    event TicketScanned(uint256 indexed ticketId);

    constructor() {
        organizer = msg.sender;
    }

    /**
     * @dev 1. Organizer sets up the event.
     */
    function initializeEvent(
        string memory _eventName,
        uint256 _ticketPriceWei,
        uint256 _maxCapacity,
        uint256 _maxResaleMarkupPercent
    ) public {
        require(msg.sender == organizer, "Only organizer");
        require(bytes(eventName).length == 0, "Event already initialized");
        require(_maxCapacity > 0, "Capacity must be > 0");

        eventName = _eventName;
        ticketPrice = _ticketPriceWei;
        maxCapacity = _maxCapacity;
        maxResaleMarkupPercent = _maxResaleMarkupPercent;
    }

    /**
     * @dev 2. Fans buy directly from the Box Office (Primary Market).
     */
    function buyTicket() public payable nonReentrant {
        require(bytes(eventName).length > 0, "Event not active");
        require(totalTicketsSold < maxCapacity, "Event is sold out");
        require(msg.value == ticketPrice, "Must pay exact ticket price");

        uint256 newTicketId = totalTicketsSold;
        
        tickets[newTicketId] = Ticket({
            id: newTicketId,
            owner: msg.sender,
            isScanned: false,
            isForSale: false,
            resalePrice: 0
        });

        userTickets[msg.sender].push(newTicketId);
        totalTicketsSold++;

        emit TicketPurchased(newTicketId, msg.sender);
    }

    /**
     * @dev 3. A fan can't make it. They list the ticket for resale.
     * ANTI-SCALPING: The contract strictly enforces the price cap.
     */
    function listForResale(uint256 _ticketId, uint256 _price) public {
        Ticket storage ticket = tickets[_ticketId];
        require(msg.sender == ticket.owner, "Not your ticket");
        require(!ticket.isScanned, "Ticket already used");
        
        // Calculate max allowed price: Original Price + (Original Price * Markup / 100)
        uint256 maxAllowedPrice = ticketPrice + ((ticketPrice * maxResaleMarkupPercent) / 100);
        require(_price <= maxAllowedPrice, "Price exceeds anti-scalping cap");

        ticket.isForSale = true;
        ticket.resalePrice = _price;

        emit TicketListed(_ticketId, _price);
    }

    /**
     * @dev Remove a ticket from the resale market.
     */
    function cancelResale(uint256 _ticketId) public {
        Ticket storage ticket = tickets[_ticketId];
        require(msg.sender == ticket.owner, "Not your ticket");
        
        ticket.isForSale = false;
        ticket.resalePrice = 0;

        emit TicketDelisted(_ticketId);
    }

    /**
     * @dev 4. Another fan buys from the secondary market.
     * Peer-to-peer transfer, but securely routed through the contract.
     */
    function buyResaleTicket(uint256 _ticketId) public payable nonReentrant {
        Ticket storage ticket = tickets[_ticketId];
        require(ticket.isForSale, "Ticket not for sale");
        require(msg.value == ticket.resalePrice, "Must pay exact resale price");
        require(!ticket.isScanned, "Ticket already used");

        address previousOwner = ticket.owner;

        // Update Ticket State
        ticket.owner = msg.sender;
        ticket.isForSale = false;
        ticket.resalePrice = 0;

        // Add to new owner's wallet (We don't prune the old array to save gas, 
        // the frontend filters ownership based on ticket.owner)
        userTickets[msg.sender].push(_ticketId);

        // Send 100% of the funds to the fan who sold it
        (bool success, ) = previousOwner.call{value: msg.value}("");
        require(success, "Transfer to seller failed");

        emit TicketResold(_ticketId, previousOwner, msg.sender, msg.value);
    }

    /**
     * @dev 5. At the door: The Organizer scans the ticket.
     * This destroys its value and prevents double-entry.
     */
    function scanTicket(uint256 _ticketId) public {
        require(msg.sender == organizer, "Only organizer can scan");
        Ticket storage ticket = tickets[_ticketId];
        require(ticket.owner != address(0), "Ticket does not exist");
        require(!ticket.isScanned, "Ticket ALREADY SCANNED! Possible fraud.");

        ticket.isScanned = true;
        ticket.isForSale = false; // Delist if it was for sale

        emit TicketScanned(_ticketId);
    }

    /**
     * @dev Organizer withdraws primary ticket sales revenue.
     */
    function withdrawBoxOfficeRevenue() public nonReentrant {
        require(msg.sender == organizer, "Only organizer");
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");

        (bool success, ) = organizer.call{value: balance}("");
        require(success, "Withdrawal failed");
    }

    // --- View Helpers ---

    function getTicketsForSale() public view returns (uint256[] memory) {
        // Find how many are for sale
        uint256 forSaleCount = 0;
        for (uint256 i = 0; i < totalTicketsSold; i++) {
            if (tickets[i].isForSale && !tickets[i].isScanned) {
                forSaleCount++;
            }
        }

        // Populate array
        uint256[] memory forSaleIds = new uint256[](forSaleCount);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < totalTicketsSold; i++) {
            if (tickets[i].isForSale && !tickets[i].isScanned) {
                forSaleIds[currentIndex] = i;
                currentIndex++;
            }
        }
        return forSaleIds;
    }

    function getUserTickets(address _user) public view returns (uint256[] memory) {
        uint256[] memory allUserTxs = userTickets[_user];
        uint256 activeCount = 0;
        
        for (uint256 i = 0; i < allUserTxs.length; i++) {
            if (tickets[allUserTxs[i]].owner == _user) {
                activeCount++;
            }
        }

        uint256[] memory activeTxs = new uint256[](activeCount);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < allUserTxs.length; i++) {
            if (tickets[allUserTxs[i]].owner == _user) {
                activeTxs[currentIndex] = allUserTxs[i];
                currentIndex++;
            }
        }
        return activeTxs;
    }
}