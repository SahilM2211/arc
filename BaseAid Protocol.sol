// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import ".deps/npm/@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BaseAid Protocol
 * @dev Enterprise-grade Transparent Relief and Conditional Cash Transfer System.
 * Eliminates corruption and administrative bloat in charitable giving.
 * Donated funds are locked in escrow and can ONLY be withdrawn by verified local
 * vendors after providing real goods/services to verified beneficiaries.
 */
contract BaseAid is ReentrancyGuard, Ownable {

    // --- State Variables ---
    uint256 public totalDonated;
    uint256 public unallocatedFunds; // Donated funds not yet assigned to a victim

    struct Vendor {
        bool isVerified;
        string name;
        string serviceType; // e.g., "Pharmacy", "Grocery", "Construction"
        uint256 claimableBalance; // Real ETH the vendor can withdraw
    }

    struct Beneficiary {
        bool isRegistered;
        uint256 voucherBalance; // Virtual balance backed by unallocatedFunds
    }

    mapping(address => Vendor) public vendors;
    mapping(address => Beneficiary) public beneficiaries;

    // --- Events for 100% On-Chain Transparency ---
    event DonationReceived(address indexed donor, uint256 amount);
    event VendorVerified(address indexed vendor, string name, string serviceType);
    event BeneficiaryRegistered(address indexed beneficiary);
    event AidAllocated(address indexed beneficiary, uint256 amount);
    event AidSpent(address indexed beneficiary, address indexed vendor, uint256 amount, string goodsDescription);
    event VendorCashedOut(address indexed vendor, uint256 amount);
    event AidClawback(address indexed beneficiary, uint256 amount);

    /**
     * @dev Deployer is the NGO Administrator.
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev 1. Anyone in the world can donate ETH to the relief fund.
     */
    function donate() public payable {
        require(msg.value > 0, "Donation must be > 0");
        totalDonated += msg.value;
        unallocatedFunds += msg.value;
        
        emit DonationReceived(msg.sender, msg.value);
    }

    /**
     * @dev Allows the contract to receive raw ETH transfers.
     */
    receive() external payable {
        donate();
    }

    // --- NGO ADMIN FUNCTIONS ---

    /**
     * @dev 2. Admin whitelists local, on-the-ground merchants.
     */
    function verifyVendor(address _vendorWallet, string memory _name, string memory _serviceType) public onlyOwner {
        require(_vendorWallet != address(0), "Invalid vendor address");
        require(!vendors[_vendorWallet].isVerified, "Vendor already verified");

        vendors[_vendorWallet] = Vendor({
            isVerified: true,
            name: _name,
            serviceType: _serviceType,
            claimableBalance: 0
        });

        emit VendorVerified(_vendorWallet, _name, _serviceType);
    }

    /**
     * @dev 3. Admin registers a disaster victim.
     */
    function registerBeneficiary(address _beneficiaryWallet) public onlyOwner {
        require(_beneficiaryWallet != address(0), "Invalid beneficiary address");
        require(!beneficiaries[_beneficiaryWallet].isRegistered, "Already registered");

        beneficiaries[_beneficiaryWallet] = Beneficiary({
            isRegistered: true,
            voucherBalance: 0
        });

        emit BeneficiaryRegistered(_beneficiaryWallet);
    }

    /**
     * @dev 4. Admin allocates a portion of the donated funds to a specific victim.
     * This moves funds from 'unallocated' into the victim's virtual 'voucher' balance.
     */
    function allocateAid(address _beneficiaryWallet, uint256 _amount) public onlyOwner {
        require(beneficiaries[_beneficiaryWallet].isRegistered, "Beneficiary not registered");
        require(unallocatedFunds >= _amount, "Not enough unallocated donations in the treasury");
        require(_amount > 0, "Amount must be > 0");

        unallocatedFunds -= _amount;
        beneficiaries[_beneficiaryWallet].voucherBalance += _amount;

        emit AidAllocated(_beneficiaryWallet, _amount);
    }

    /**
     * @dev Emergency/Cleanup: If a victim leaves the area or doesn't spend their aid, 
     * the NGO can claw back the unspent virtual balance to allocate to someone else.
     */
    function clawbackUnspentAid(address _beneficiaryWallet) public onlyOwner {
        uint256 unspent = beneficiaries[_beneficiaryWallet].voucherBalance;
        require(unspent > 0, "No unspent aid to clawback");

        beneficiaries[_beneficiaryWallet].voucherBalance = 0;
        unallocatedFunds += unspent;

        emit AidClawback(_beneficiaryWallet, unspent);
    }

    // --- BENEFICIARY (VICTIM) FUNCTIONS ---

    /**
     * @dev 5. Victim goes to a local verified store to buy food/medicine.
     * They transfer their virtual voucher to the vendor.
     * The `goodsDescription` allows Donors to see exactly what their money bought.
     */
    function spendAid(address _vendorWallet, uint256 _amount, string memory _goodsDescription) public {
        require(beneficiaries[msg.sender].isRegistered, "Not a registered beneficiary");
        require(vendors[_vendorWallet].isVerified, "Not a verified local vendor");
        require(beneficiaries[msg.sender].voucherBalance >= _amount, "Insufficient aid balance");
        require(_amount > 0, "Amount must be > 0");
        require(bytes(_goodsDescription).length > 0, "Must declare what goods were purchased");

        // Move virtual balance from Victim to Vendor
        beneficiaries[msg.sender].voucherBalance -= _amount;
        vendors[_vendorWallet].claimableBalance += _amount;

        emit AidSpent(msg.sender, _vendorWallet, _amount, _goodsDescription);
    }

    // --- VENDOR (MERCHANT) FUNCTIONS ---

    /**
     * @dev 6. Local merchant cashes out their earned vouchers for actual hard ETH.
     */
    function cashOut() public nonReentrant {
        require(vendors[msg.sender].isVerified, "Not a verified vendor");
        
        uint256 amountToClaim = vendors[msg.sender].claimableBalance;
        require(amountToClaim > 0, "No funds to cash out");
        require(address(this).balance >= amountToClaim, "Contract out of funds (Critical Error)");

        vendors[msg.sender].claimableBalance = 0;

        (bool success, ) = msg.sender.call{value: amountToClaim}("");
        require(success, "Transfer to vendor failed");

        emit VendorCashedOut(msg.sender, amountToClaim);
    }

    // --- Transparency Helpers ---
    function getTreasuryBalance() public view returns (uint256) {
        return address(this).balance;
    }
}