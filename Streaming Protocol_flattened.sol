
// File: @openzeppelin/contracts/security/ReentrancyGuard.sol


// OpenZeppelin Contracts (last updated v4.9.0) (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }
}

// File: arc_testnet/Streaming Protocol.sol


pragma solidity ^0.8.20;

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