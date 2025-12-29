// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DigitalWarrantyRegistry
 * @dev A system to issue, track, and transfer product warranties.
 * Solves the problem of lost receipts and verifying second-hand goods.
 *
 * Easy Deployment: No constructor arguments needed.
 */
contract DigitalWarrantyRegistry is Ownable {

    struct Warranty {
        address currentOwner;
        uint256 startTime;
        uint256 endTime;
        bool isVoid;
        string productDetails; // e.g. "Model X - Black"
    }

    // Mapping from Serial Number (string) to Warranty Data
    mapping(string => Warranty) public warranties;
    
    event WarrantyIssued(string indexed serialNumber, address indexed owner, uint256 endTime);
    event WarrantyTransferred(string indexed serialNumber, address indexed from, address indexed to);
    event WarrantyVoided(string indexed serialNumber, string reason);

    // Deployer becomes the "Manufacturer" (Owner)
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Manufacturer issues a new warranty.
     * @param _serialNumber The unique ID of the physical item.
     * @param _buyer The wallet address of the customer.
     * @param _durationDays How long the warranty lasts (e.g., 365).
     * @param _details Description of the item.
     */
    function issueWarranty(
        string memory _serialNumber,
        address _buyer,
        uint256 _durationDays,
        string memory _details
    ) public onlyOwner {
        require(_buyer != address(0), "Invalid buyer address");
        require(warranties[_serialNumber].startTime == 0, "Warranty already exists for this serial");

        uint256 start = block.timestamp;
        uint256 end = start + (_durationDays * 1 days);

        warranties[_serialNumber] = Warranty({
            currentOwner: _buyer,
            startTime: start,
            endTime: end,
            isVoid: false,
            productDetails: _details
        });

        emit WarrantyIssued(_serialNumber, _buyer, end);
    }

    /**
     * @dev The current owner of the item can transfer the warranty to a new owner (resale).
     */
    function transferWarranty(string memory _serialNumber, address _newOwner) public {
        Warranty storage w = warranties[_serialNumber];
        
        require(msg.sender == w.currentOwner, "You do not own this warranty");
        require(!w.isVoid, "Warranty is void");
        require(block.timestamp < w.endTime, "Warranty has expired");
        require(_newOwner != address(0), "Invalid new owner");

        address oldOwner = w.currentOwner;
        w.currentOwner = _newOwner;

        emit WarrantyTransferred(_serialNumber, oldOwner, _newOwner);
    }

    /**
     * @dev Manufacturer can void a warranty (e.g., if device was tampered with).
     */
    function voidWarranty(string memory _serialNumber, string memory _reason) public onlyOwner {
        require(warranties[_serialNumber].startTime != 0, "Warranty does not exist");
        warranties[_serialNumber].isVoid = true;
        emit WarrantyVoided(_serialNumber, _reason);
    }

    // --- View Functions ---

    /**
     * @dev Check the status of a specific serial number.
     * Returns: isValid, statusText, owner, expiryDate
     */
    function checkWarranty(string memory _serialNumber) public view returns (
        bool isValid,
        string memory status,
        address owner,
        uint256 expiry,
        string memory details
    ) {
        Warranty memory w = warranties[_serialNumber];
        
        if (w.startTime == 0) {
            return (false, "Not Found", address(0), 0, "");
        }

        owner = w.currentOwner;
        expiry = w.endTime;
        details = w.productDetails;

        if (w.isVoid) {
            return (false, "VOIDED", owner, expiry, details);
        }
        
        if (block.timestamp > w.endTime) {
            return (false, "EXPIRED", owner, expiry, details);
        }

        return (true, "ACTIVE", owner, expiry, details);
    }
}