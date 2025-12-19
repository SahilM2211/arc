// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AutoBillPayer
 * @dev A smart contract to automate recurring payments.
 * You define the bills (payee, amount, interval).
 * The contract ensures bills are paid on time, but never double-paid.
 *
 * Easy Deployment: No constructor arguments needed.
 */
contract AutoBillPayer is Ownable {

    struct Bill {
        string name;        // e.g., "Rent" or "Internet"
        address payee;      // Who gets the money
        uint256 amount;     // How much (in wei)
        uint256 interval;   // How often (in seconds, e.g., 30 days)
        uint256 lastPaid;   // Timestamp of last payment
        bool active;        // Is this bill currently active?
    }

    Bill[] public bills;

    event BillAdded(uint256 indexed id, string name, address payee, uint256 amount);
    event BillPaid(uint256 indexed id, string name, uint256 amount, uint256 time);
    event FundsDeposited(address indexed from, uint256 amount);
    event BillStatusUpdated(uint256 indexed id, bool active);

    // Empty constructor for easy deployment
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Receive ETH to fund the bill payer.
     */
    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }

    /**
     * @dev Add a new recurring bill.
     * @param _name Name of the bill (e.g., "Landlord")
     * @param _payee Wallet address to send money to
     * @param _amount Amount in WEI
     * @param _intervalDays How many days between payments
     */
    function addBill(
        string memory _name, 
        address _payee, 
        uint256 _amount, 
        uint256 _intervalDays
    ) public onlyOwner {
        require(_payee != address(0), "Invalid address");
        require(_amount > 0, "Amount must be > 0");
        require(_intervalDays > 0, "Interval must be > 0");

        bills.push(Bill({
            name: _name,
            payee: _payee,
            amount: _amount,
            interval: _intervalDays * 1 days,
            lastPaid: 0, // Never paid yet
            active: true
        }));

        emit BillAdded(bills.length - 1, _name, _payee, _amount);
    }

    /**
     * @dev Trigger a payment for a specific bill.
     * ANYONE can call this. If the rent is due, the landlord can trigger it themselves!
     */
    function payBill(uint256 _billId) public {
        require(_billId < bills.length, "Invalid Bill ID");
        Bill storage bill = bills[_billId];

        require(bill.active, "Bill is inactive");
        require(address(this).balance >= bill.amount, "Not enough funds in contract");
        
        // The Core Logic: Check if enough time has passed
        require(block.timestamp >= bill.lastPaid + bill.interval, "Bill is not due yet");

        // Update timestamp BEFORE sending to prevent re-entrancy
        bill.lastPaid = block.timestamp;

        (bool success, ) = bill.payee.call{value: bill.amount}("");
        require(success, "Transfer failed");

        emit BillPaid(_billId, bill.name, bill.amount, block.timestamp);
    }

    /**
     * @dev Pause or Resume a bill.
     */
    function toggleBill(uint256 _billId) public onlyOwner {
        require(_billId < bills.length, "Invalid Bill ID");
        bills[_billId].active = !bills[_billId].active;
        emit BillStatusUpdated(_billId, bills[_billId].active);
    }

    /**
     * @dev Withdraw excess funds.
     */
    function withdraw() public onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    // --- View Functions ---

    function getBillCount() public view returns (uint256) {
        return bills.length;
    }

    function isBillDue(uint256 _billId) public view returns (bool) {
        if (_billId >= bills.length) return false;
        Bill memory bill = bills[_billId];
        if (!bill.active) return false;
        return block.timestamp >= bill.lastPaid + bill.interval;
    }
}