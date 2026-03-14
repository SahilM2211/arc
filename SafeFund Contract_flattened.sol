
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

// File: arc_testnet/SafeFund Contract.sol


pragma solidity ^0.8.20;

/**
 * @title SafeFund Protocol
 * @dev Enterprise-grade milestone crowdfunding.
 * Solves the "Kickstarter Problem" by forcing creators to get 
 * democratic approval from backers before spending raised funds.
 *
 * Easy Deployment: Empty constructor. You initialize the campaign after deploying.
 */
contract SafeFund is ReentrancyGuard {

    address public creator;
    uint256 public goalAmount;
    uint256 public deadline;
    uint256 public totalRaised;
    bool public isInitialized;

    enum CampaignState { Pending, Active, Failed, Successful }

    struct Request {
        uint256 id;
        string description;
        address payable recipient;
        uint256 amount;
        uint256 yesVotes;
        uint256 noVotes;
        bool isCompleted;
    }

    mapping(address => uint256) public contributions;
    
    Request[] public requests;
    // Mapping: RequestID => BackerAddress => HasVoted
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event CampaignInitialized(uint256 goal, uint256 deadline);
    event Funded(address indexed backer, uint256 amount);
    event RefundIssued(address indexed backer, uint256 amount);
    event RequestCreated(uint256 indexed id, string description, uint256 amount, address recipient);
    event Voted(address indexed backer, uint256 indexed requestId, bool support, uint256 weight);
    event RequestExecuted(uint256 indexed id, uint256 amount);

    constructor() {
        creator = msg.sender;
    }

    /**
     * @dev 1. Initialize the campaign details.
     * @param _goalAmountWei The funding goal in WEI.
     * @param _durationDays How long the funding phase lasts.
     */
    function initializeCampaign(uint256 _goalAmountWei, uint256 _durationDays) public {
        require(msg.sender == creator, "Only creator can initialize");
        require(!isInitialized, "Already initialized");
        require(_goalAmountWei > 0, "Goal must be > 0");
        require(_durationDays > 0, "Duration must be > 0");

        goalAmount = _goalAmountWei;
        deadline = block.timestamp + (_durationDays * 1 days);
        isInitialized = true;

        emit CampaignInitialized(_goalAmountWei, deadline);
    }

    /**
     * @dev Determine the current state of the campaign.
     */
    function getCampaignState() public view returns (CampaignState) {
        if (!isInitialized) return CampaignState.Pending;
        if (block.timestamp < deadline) return CampaignState.Active;
        if (totalRaised >= goalAmount) return CampaignState.Successful;
        return CampaignState.Failed;
    }

    /**
     * @dev 2. Backers fund the campaign.
     */
    function contribute() public payable nonReentrant {
        require(getCampaignState() == CampaignState.Active, "Campaign is not active");
        require(msg.value > 0, "Contribution must be > 0");

        contributions[msg.sender] += msg.value;
        totalRaised += msg.value;

        emit Funded(msg.sender, msg.value);
    }

    /**
     * @dev 3. If campaign fails to meet goal by deadline, backers claim full refunds.
     */
    function claimRefund() public nonReentrant {
        require(getCampaignState() == CampaignState.Failed, "Campaign did not fail");
        uint256 amount = contributions[msg.sender];
        require(amount > 0, "No contribution found");

        contributions[msg.sender] = 0;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Refund failed");

        emit RefundIssued(msg.sender, amount);
    }

    /**
     * @dev 4. (If Successful) Creator creates a request to spend funds on a milestone.
     */
    function createRequest(string memory _description, address payable _recipient, uint256 _amount) public {
        require(msg.sender == creator, "Only creator can request funds");
        require(getCampaignState() == CampaignState.Successful, "Campaign not successful");
        require(_amount <= address(this).balance, "Request exceeds available balance");

        requests.push(Request({
            id: requests.length,
            description: _description,
            recipient: _recipient,
            amount: _amount,
            yesVotes: 0,
            noVotes: 0,
            isCompleted: false
        }));

        emit RequestCreated(requests.length - 1, _description, _amount, _recipient);
    }

    /**
     * @dev 5. Backers vote on the spending request. Voting power = ETH contributed.
     */
    function voteOnRequest(uint256 _requestId, bool _support) public {
        require(getCampaignState() == CampaignState.Successful, "Campaign not successful");
        require(contributions[msg.sender] > 0, "Only backers can vote");
        require(_requestId < requests.length, "Invalid request ID");
        
        Request storage req = requests[_requestId];
        require(!req.isCompleted, "Request already executed");
        require(!hasVoted[_requestId][msg.sender], "You already voted");

        hasVoted[_requestId][msg.sender] = true;
        uint256 votingPower = contributions[msg.sender];

        if (_support) {
            req.yesVotes += votingPower;
        } else {
            req.noVotes += votingPower;
        }

        emit Voted(msg.sender, _requestId, _support, votingPower);
    }

    /**
     * @dev 6. If > 50% of the total raised capital votes YES, the funds are released.
     */
    function executeRequest(uint256 _requestId) public nonReentrant {
        require(msg.sender == creator, "Only creator can execute");
        require(_requestId < requests.length, "Invalid request ID");
        
        Request storage req = requests[_requestId];
        require(!req.isCompleted, "Request already executed");
        
        // Mathematical absolute majority required
        require(req.yesVotes > (totalRaised / 2), "Need >50% approval from total capital");
        require(address(this).balance >= req.amount, "Insufficient vault funds");

        req.isCompleted = true;

        (bool success, ) = req.recipient.call{value: req.amount}("");
        require(success, "Transfer failed");

        emit RequestExecuted(_requestId, req.amount);
    }

    // --- View Helpers ---
    function getRequestsCount() public view returns (uint256) {
        return requests.length;
    }

    function getRequest(uint256 _id) public view returns (Request memory) {
        return requests[_id];
    }
}