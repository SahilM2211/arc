
// File: @openzeppelin/contracts/utils/StorageSlot.sol


// OpenZeppelin Contracts (last updated v5.1.0) (utils/StorageSlot.sol)
// This file was procedurally generated from scripts/generate/templates/StorageSlot.js.

pragma solidity ^0.8.20;

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC-1967 implementation slot:
 * ```solidity
 * contract ERC1967 {
 *     // Define the slot. Alternatively, use the SlotDerivation library to derive the slot.
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(newImplementation.code.length > 0);
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 *
 * TIP: Consider using this library along with {SlotDerivation}.
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    struct Int256Slot {
        int256 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Int256Slot` with member `value` located at `slot`.
     */
    function getInt256Slot(bytes32 slot) internal pure returns (Int256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `StringSlot` with member `value` located at `slot`.
     */
    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` representation of the string storage pointer `store`.
     */
    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }

    /**
     * @dev Returns a `BytesSlot` with member `value` located at `slot`.
     */
    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` representation of the bytes storage pointer `store`.
     */
    function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }
}

// File: @openzeppelin/contracts/utils/ReentrancyGuard.sol


// OpenZeppelin Contracts (last updated v5.5.0) (utils/ReentrancyGuard.sol)

pragma solidity ^0.8.20;


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
 * TIP: If EIP-1153 (transient storage) is available on the chain you're deploying at,
 * consider using {ReentrancyGuardTransient} instead.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 *
 * IMPORTANT: Deprecated. This storage-based reentrancy guard will be removed and replaced
 * by the {ReentrancyGuardTransient} variant in v6.0.
 *
 * @custom:stateless
 */
abstract contract ReentrancyGuard {
    using StorageSlot for bytes32;

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant REENTRANCY_GUARD_STORAGE =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

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
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _reentrancyGuardStorageSlot().getUint256Slot().value = NOT_ENTERED;
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

    /**
     * @dev A `view` only version of {nonReentrant}. Use to block view functions
     * from being called, preventing reading from inconsistent contract state.
     *
     * CAUTION: This is a "view" modifier and does not change the reentrancy
     * status. Use it only on view functions. For payable or non-payable functions,
     * use the standard {nonReentrant} modifier instead.
     */
    modifier nonReentrantView() {
        _nonReentrantBeforeView();
        _;
    }

    function _nonReentrantBeforeView() private view {
        if (_reentrancyGuardEntered()) {
            revert ReentrancyGuardReentrantCall();
        }
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        _nonReentrantBeforeView();

        // Any calls to nonReentrant after this point will fail
        _reentrancyGuardStorageSlot().getUint256Slot().value = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _reentrancyGuardStorageSlot().getUint256Slot().value = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _reentrancyGuardStorageSlot().getUint256Slot().value == ENTERED;
    }

    function _reentrancyGuardStorageSlot() internal pure virtual returns (bytes32) {
        return REENTRANCY_GUARD_STORAGE;
    }
}

// File: @openzeppelin/contracts/utils/Context.sol


// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

pragma solidity ^0.8.20;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// File: @openzeppelin/contracts/access/Ownable.sol


// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

pragma solidity ^0.8.20;


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// File: arc_testnet/Carbon Market Protocol.sol


pragma solidity ^0.8.20;

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