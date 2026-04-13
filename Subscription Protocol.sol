// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import ".deps/npm/@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title BaseSub Protocol
 * @dev Enterprise-grade recurring payment and subscription protocol.
 * Solves Web3 recurring billing using a user-funded escrow model.
 * Users deposit ETH once, and authorize creators to claim a fixed amount per time interval.
 * Users can cancel instantly at any time.
 */
contract BaseSub is ReentrancyGuard {

    struct Plan {
        uint256 id;
        address creator;
        string name;
        uint256 price;       // Cost per billing cycle (in Wei)
        uint256 interval;    // Duration of billing cycle (in seconds)
        bool active;         // Can new people subscribe?
    }

    struct Subscription {
        bool isActive;
        uint256 nextPaymentDue; // Timestamp when the creator can claim the next payment
    }

    uint256 public planCounter;
    
    // Plan ID => Plan Details
    mapping(uint256 => Plan) public plans;
    
    // User Address => Prepaid ETH Balance
    mapping(address => uint256) public userBalances;
    
    // Plan ID => User Address => Subscription Details
    mapping(uint256 => mapping(address => Subscription)) public subscriptions;

    // --- Events ---
    event PlanCreated(uint256 indexed planId, address indexed creator, string name, uint256 price, uint256 interval);
    event BalanceDeposited(address indexed user, uint256 amount);
    event BalanceWithdrawn(address indexed user, uint256 amount);
    event Subscribed(uint256 indexed planId, address indexed subscriber, uint256 nextPaymentDue);
    event Unsubscribed(uint256 indexed planId, address indexed subscriber);
    event PaymentClaimed(uint256 indexed planId, address indexed subscriber, address indexed creator, uint256 amount);

    /**
     * @dev 1. Creator launches a subscription tier (e.g., "Premium Newsletter", 0.01 ETH / 30 Days)
     */
    function createPlan(string memory _name, uint256 _priceWei, uint256 _intervalSeconds) public {
        require(_priceWei > 0, "Price must be > 0");
        require(_intervalSeconds >= 1 days, "Interval must be at least 1 day for safety");

        uint256 planId = planCounter++;
        plans[planId] = Plan({
            id: planId,
            creator: msg.sender,
            name: _name,
            price: _priceWei,
            interval: _intervalSeconds,
            active: true
        });

        emit PlanCreated(planId, msg.sender, _name, _priceWei, _intervalSeconds);
    }

    /**
     * @dev 2. User tops up their prepaid billing account.
     */
    function deposit() public payable {
        require(msg.value > 0, "Must deposit ETH");
        userBalances[msg.sender] += msg.value;
        emit BalanceDeposited(msg.sender, msg.value);
    }

    /**
     * @dev User withdraws unused funds from their billing account.
     */
    function withdraw(uint256 _amount) public nonReentrant {
        require(_amount > 0 && _amount <= userBalances[msg.sender], "Insufficient balance");
        
        userBalances[msg.sender] -= _amount;
        
        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Transfer failed");
        
        emit BalanceWithdrawn(msg.sender, _amount);
    }

    /**
     * @dev 3. User subscribes to a plan. 
     * Can optionally send ETH in the same transaction to fund their account instantly.
     */
    function subscribe(uint256 _planId) public payable nonReentrant {
        if (msg.value > 0) {
            userBalances[msg.sender] += msg.value;
            emit BalanceDeposited(msg.sender, msg.value);
        }

        Plan memory plan = plans[_planId];
        require(plan.active, "Plan does not exist or is inactive");
        
        Subscription storage sub = subscriptions[_planId][msg.sender];
        require(!sub.isActive, "Already subscribed");
        require(userBalances[msg.sender] >= plan.price, "Insufficient prepaid balance for first payment");

        // Deduct first payment instantly
        userBalances[msg.sender] -= plan.price;
        sub.isActive = true;
        sub.nextPaymentDue = block.timestamp + plan.interval;

        // Route payment to creator
        (bool success, ) = plan.creator.call{value: plan.price}("");
        require(success, "Transfer to creator failed");

        emit Subscribed(_planId, msg.sender, sub.nextPaymentDue);
        emit PaymentClaimed(_planId, msg.sender, plan.creator, plan.price);
    }

    /**
     * @dev 4. User cancels their subscription. No further charges can be made.
     */
    function unsubscribe(uint256 _planId) public {
        Subscription storage sub = subscriptions[_planId][msg.sender];
        require(sub.isActive, "Not subscribed");

        sub.isActive = false;
        emit Unsubscribed(_planId, msg.sender);
    }

    /**
     * @dev 5. Creator claims the next recurring payment once the time interval has passed.
     * If the user's balance is empty, the subscription is automatically cancelled.
     */
    function claimPayment(uint256 _planId, address _subscriber) public nonReentrant {
        Plan memory plan = plans[_planId];
        Subscription storage sub = subscriptions[_planId][_subscriber];

        require(sub.isActive, "User is not actively subscribed");
        require(block.timestamp >= sub.nextPaymentDue, "Payment is not due yet");

        if (userBalances[_subscriber] >= plan.price) {
            // User has funds: Process payment and advance the due date
            userBalances[_subscriber] -= plan.price;
            sub.nextPaymentDue = block.timestamp + plan.interval;

            (bool success, ) = plan.creator.call{value: plan.price}("");
            require(success, "Transfer to creator failed");

            emit PaymentClaimed(_planId, _subscriber, plan.creator, plan.price);
        } else {
            // User is out of funds: Auto-cancel the subscription
            sub.isActive = false;
            emit Unsubscribed(_planId, _subscriber);
        }
    }

    /**
     * @dev Enterprise Feature: Batch claim payments for multiple subscribers at once to save gas.
     */
    function batchClaimPayments(uint256 _planId, address[] memory _subscribers) public {
        for (uint256 i = 0; i < _subscribers.length; i++) {
            // We wrap this in a try-catch pattern equivalent by checking conditions first
            // to ensure one failing claim doesn't revert the whole batch.
            Subscription memory sub = subscriptions[_planId][_subscribers[i]];
            if (sub.isActive && block.timestamp >= sub.nextPaymentDue) {
                claimPayment(_planId, _subscribers[i]);
            }
        }
    }

    // --- View Helpers ---
    function getPlan(uint256 _id) public view returns (Plan memory) {
        return plans[_id];
    }
    
    function getSubscription(uint256 _planId, address _user) public view returns (Subscription memory) {
        return subscriptions[_planId][_user];
    }
}