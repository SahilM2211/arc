// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import ".deps/npm/@openzeppelin/contracts/security/ReentrancyGuard.sol";
/**
 * @title BaseSplitter
 * @dev Enterprise-grade Revenue Routing Protocol.
 * All ETH sent to this contract is mathematically divided according to an immutable Cap Table.
 * Solves co-founder disputes and automates accounting/payroll for collectives.
 */
contract BaseSplitter is ReentrancyGuard {
    
    uint256 public totalShares;
    uint256 public totalReleased;

    address[] public payees;
    mapping(address => uint256) public shares;
    mapping(address => uint256) public released;

    event PayeeAdded(address account, uint256 shares);
    event PaymentReleased(address to, uint256 amount);
    event RevenueReceived(address from, uint256 amount);

    /**
     * @dev Creates the immutable Cap Table.
     * @param _payees Array of wallet addresses.
     * @param _shares Array of shares (e.g., [50, 25, 25]).
     */
    constructor(address[] memory _payees, uint256[] memory _shares) {
        require(_payees.length == _shares.length, "Splitter: payees and shares length mismatch");
        require(_payees.length > 0, "Splitter: no payees");
        require(_payees.length <= 50, "Splitter: too many payees (gas limit protection)");

        for (uint256 i = 0; i < _payees.length; i++) {
            _addPayee(_payees[i], _shares[i]);
        }
    }

    /**
     * @dev The contract can receive ETH natively. Any ETH sent here is automatically
     * eligible to be split among the payees.
     */
    receive() external payable {
        emit RevenueReceived(msg.sender, msg.value);
    }

    /**
     * @dev View function to calculate how much ETH a specific payee is owed right now.
     * Math: (Total ETH ever received * User's Shares / Total Shares) - What user already withdrew.
     */
    function pendingPayment(address _account) public view returns (uint256) {
        uint256 totalReceived = address(this).balance + totalReleased;
        uint256 payment = (totalReceived * shares[_account]) / totalShares;
        return payment - released[_account];
    }

    /**
     * @dev Triggers the release of owed funds to a specific payee.
     * Anyone can call this function (you can pay the gas to route funds to your co-founder).
     */
    function release(address payable _account) public nonReentrant {
        require(shares[_account] > 0, "Splitter: account has no shares");

        uint256 payment = pendingPayment(_account);
        require(payment > 0, "Splitter: account is not due payment");

        released[_account] += payment;
        totalReleased += payment;

        (bool success, ) = _account.call{value: payment}("");
        require(success, "Splitter: transfer failed");
        
        emit PaymentReleased(_account, payment);
    }

    /**
     * @dev Convenience function to distribute all pending revenue to all payees at once.
     * Highly efficient on L2s like Base.
     */
    function releaseAll() public nonReentrant {
        uint256 totalReceived = address(this).balance + totalReleased;
        
        for (uint256 i = 0; i < payees.length; i++) {
            address payable payee = payable(payees[i]);
            uint256 payment = ((totalReceived * shares[payee]) / totalShares) - released[payee];
            
            if (payment > 0) {
                released[payee] += payment;
                totalReleased += payment;
                
                (bool success, ) = payee.call{value: payment}("");
                require(success, "Splitter: transfer failed");
                
                emit PaymentReleased(payee, payment);
            }
        }
    }

    /**
     * @dev Internal function to securely add a payee during deployment.
     */
    function _addPayee(address _account, uint256 _shares) private {
        require(_account != address(0), "Splitter: account is the zero address");
        require(_shares > 0, "Splitter: shares are 0");
        require(shares[_account] == 0, "Splitter: payee already has shares");

        payees.push(_account);
        shares[_account] = _shares;
        totalShares = totalShares + _shares;
        
        emit PayeeAdded(_account, _shares);
    }

    // --- View Helpers ---
    function getPayeeCount() public view returns (uint256) {
        return payees.length;
    }
}