// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title ExpenseReimbursement
 * @dev A system for employees to claim expenses and managers to approve them instantly.
 * * Flow:
 * 1. Company deposits funds.
 * 2. Employee calls `submitClaim`.
 * 3. Company calls `approveClaim` -> Funds sent instantly.
 *
 * Deployment: Easy (No inputs).
 */
contract ExpenseReimbursement is Ownable, ReentrancyGuard {

    enum Status { Pending, Approved, Rejected }

    struct Claim {
        uint256 id;
        address claimant;
        string description;
        uint256 amount;
        Status status;
        uint256 timestamp;
    }

    Claim[] public claims;
    
    event ClaimSubmitted(uint256 indexed id, address indexed claimant, uint256 amount, string description);
    event ClaimApproved(uint256 indexed id, address indexed claimant, uint256 amount);
    event ClaimRejected(uint256 indexed id, string reason);
    event FundsDeposited(address indexed from, uint256 amount);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Company funds the reimbursement pool.
     */
    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }

    /**
     * @dev Employee submits a new expense claim.
     */
    function submitClaim(string memory _description, uint256 _amount) public {
        require(_amount > 0, "Amount must be > 0");
        
        claims.push(Claim({
            id: claims.length,
            claimant: msg.sender,
            description: _description,
            amount: _amount,
            status: Status.Pending,
            timestamp: block.timestamp
        }));

        emit ClaimSubmitted(claims.length - 1, msg.sender, _amount, _description);
    }

    /**
     * @dev Manager approves a claim. Funds move instantly.
     */
    function approveClaim(uint256 _claimId) public onlyOwner nonReentrant {
        require(_claimId < claims.length, "Invalid ID");
        Claim storage claim = claims[_claimId];

        require(claim.status == Status.Pending, "Claim not pending");
        require(address(this).balance >= claim.amount, "Insufficient company funds");

        claim.status = Status.Approved;

        (bool success, ) = claim.claimant.call{value: claim.amount}("");
        require(success, "Transfer failed");

        emit ClaimApproved(_claimId, claim.claimant, claim.amount);
    }

    /**
     * @dev Manager rejects a claim (e.g. invalid receipt).
     */
    function rejectClaim(uint256 _claimId, string memory _reason) public onlyOwner {
        require(_claimId < claims.length, "Invalid ID");
        Claim storage claim = claims[_claimId];
        require(claim.status == Status.Pending, "Claim not pending");

        claim.status = Status.Rejected;
        emit ClaimRejected(_claimId, _reason);
    }

    /**
     * @dev Manager can withdraw unused funds.
     */
    function withdrawCompanyFunds() public onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }

    // --- View Functions ---

    function getCompanyBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getClaimCount() public view returns (uint256) {
        return claims.length;
    }

    /**
     * @dev Fetch all claims (careful with gas limits in production, fine for small usage).
     */
    function getAllClaims() public view returns (Claim[] memory) {
        return claims;
    }
}