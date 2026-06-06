// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BaseCarbon Registry
 * @dev Enterprise-grade Voluntary Carbon Market (VCM) Protocol.
 * Eliminates brokers and "Double Counting" fraud.
 * Allows eco-projects to sell verified carbon credits directly to corporations.
 * Corporations "Retire" credits to generate immutable public proof of offset.
 */
contract BaseCarbon is ReentrancyGuard, Ownable {

    struct Project {
        uint256 id;
        address developer;
        string name;
        string projectType; // e.g., "Reforestation", "Solar", "Direct Air Capture"
        string location;
        bool isVerified;
    }

    struct CreditBatch {
        uint256 id;
        uint256 projectId;
        uint256 vintageYear; // Year the carbon was removed
        uint256 totalTonsMinted;
        uint256 availableTons;
        uint256 pricePerTon; // In Wei
    }

    struct RetirementRecord {
        uint256 id;
        address retiringWallet;
        string corporateName; // Name of the entity claiming the offset
        uint256 batchId;
        uint256 amountTons;
        string retirementMessage; // e.g., "Offsetting Q3 Server Emissions"
        uint256 timestamp;
    }

    uint256 public projectCounter;
    uint256 public batchCounter;
    uint256 public retirementCounter;

    mapping(uint256 => Project) public projects;
    mapping(uint256 => CreditBatch) public creditBatches;
    
    // User Wallet => Batch ID => Amount of Tons currently held (unretired)
    mapping(address => mapping(uint256 => uint256)) public unretiredBalances;
    
    mapping(uint256 => RetirementRecord) public retirementLedger;

    // --- Events for Public ESG Auditing ---
    event ProjectProposed(uint256 indexed id, address indexed developer, string name);
    event ProjectVerified(uint256 indexed id);
    event CreditsMinted(uint256 indexed batchId, uint256 indexed projectId, uint256 amount);
    event PriceUpdated(uint256 indexed batchId, uint256 newPrice);
    event CreditsPurchased(uint256 indexed batchId, address indexed buyer, uint256 amount);
    event CreditsRetired(uint256 indexed retirementId, address indexed entity, string corporateName, uint256 amount, uint256 timestamp);

    /**
     * @dev Deployer acts as the Initial Verifier/Auditor (e.g., Verra or Gold Standard).
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev 1. Eco-Developer proposes a new environmental project.
     */
    function proposeProject(string memory _name, string memory _type, string memory _location) public {
        uint256 id = projectCounter++;
        projects[id] = Project({
            id: id,
            developer: msg.sender,
            name: _name,
            projectType: _type,
            location: _location,
            isVerified: false
        });

        emit ProjectProposed(id, msg.sender, _name);
    }

    /**
     * @dev 2. Auditor physically verifies the project in the real world and approves it on-chain.
     */
    function verifyProject(uint256 _projectId) public onlyOwner {
        require(_projectId < projectCounter, "Invalid Project ID");
        require(!projects[_projectId].isVerified, "Already verified");

        projects[_projectId].isVerified = true;
        emit ProjectVerified(_projectId);
    }

    /**
     * @dev 3. Auditor mints carbon credits (1 Token = 1 Metric Ton of CO2) after verification.
     */
    function issueCarbonCredits(
        uint256 _projectId, 
        uint256 _vintageYear, 
        uint256 _tonsToMint, 
        uint256 _initialPriceWei
    ) public onlyOwner {
        require(projects[_projectId].isVerified, "Project must be verified first");
        require(_tonsToMint > 0, "Must mint at least 1 ton");

        uint256 batchId = batchCounter++;
        
        creditBatches[batchId] = CreditBatch({
            id: batchId,
            projectId: _projectId,
            vintageYear: _vintageYear,
            totalTonsMinted: _tonsToMint,
            availableTons: _tonsToMint,
            pricePerTon: _initialPriceWei
        });

        emit CreditsMinted(batchId, _projectId, _tonsToMint);
    }

    /**
     * @dev 4. Developer can adjust the market price of their credits.
     */
    function updateCreditPrice(uint256 _batchId, uint256 _newPriceWei) public {
        CreditBatch storage batch = creditBatches[_batchId];
        Project memory project = projects[batch.projectId];
        
        require(msg.sender == project.developer, "Only project developer can set price");
        batch.pricePerTon = _newPriceWei;

        emit PriceUpdated(_batchId, _newPriceWei);
    }

    /**
     * @dev 5. Corporation buys carbon credits. Funds bypass brokers and go DIRECTLY to the developer.
     */
    function buyCredits(uint256 _batchId, uint256 _tonsToBuy) public payable nonReentrant {
        require(_batchId < batchCounter, "Invalid Batch ID");
        require(_tonsToBuy > 0, "Must buy at least 1 ton");
        
        CreditBatch storage batch = creditBatches[_batchId];
        require(batch.availableTons >= _tonsToBuy, "Not enough credits available in this batch");

        uint256 totalCost = batch.pricePerTon * _tonsToBuy;
        require(msg.value == totalCost, "Incorrect ETH sent");

        // Update balances
        batch.availableTons -= _tonsToBuy;
        unretiredBalances[msg.sender][_batchId] += _tonsToBuy;

        // Route funds securely to the project developer
        Project memory project = projects[batch.projectId];
        (bool success, ) = project.developer.call{value: totalCost}("");
        require(success, "Transfer to developer failed");

        emit CreditsPurchased(_batchId, msg.sender, _tonsToBuy);
    }

    /**
     * @dev 6. Corporation permanently RETIRES the credits to offset their carbon footprint.
     * This destroys the fungible credit and generates an immutable Public ESG Certificate.
     */
    function retireCredits(
        uint256 _batchId, 
        uint256 _tonsToRetire, 
        string memory _corporateName, 
        string memory _retirementMessage
    ) public {
        require(_tonsToRetire > 0, "Must retire at least 1 ton");
        require(unretiredBalances[msg.sender][_batchId] >= _tonsToRetire, "Insufficient unretired credits");

        // Burn the credits from the user's wallet
        unretiredBalances[msg.sender][_batchId] -= _tonsToRetire;

        // Create permanent public ledger entry
        uint256 retirementId = retirementCounter++;
        retirementLedger[retirementId] = RetirementRecord({
            id: retirementId,
            retiringWallet: msg.sender,
            corporateName: _corporateName,
            batchId: _batchId,
            amountTons: _tonsToRetire,
            retirementMessage: _retirementMessage,
            timestamp: block.timestamp
        });

        emit CreditsRetired(retirementId, msg.sender, _corporateName, _tonsToRetire, block.timestamp);
    }

    // --- View Helpers ---
    function getBatchDetails(uint256 _batchId) public view returns (CreditBatch memory, Project memory) {
        CreditBatch memory batch = creditBatches[_batchId];
        Project memory project = projects[batch.projectId];
        return (batch, project);
    }
}