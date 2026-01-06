// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CryptoGiftCards
 * @dev A smart contract that lets you create ETH gift cards using a secret passphrase.
 * * 1. Sender deposits ETH and attaches it to a HASH of a secret code.
 * 2. Receiver enters the secret code.
 * 3. Contract verifies hash(code) matches the deposit, and transfers funds.
 *
 * Easy Deployment: No constructor arguments.
 */
contract CryptoGiftCards {

    struct Gift {
        uint256 amount;
        address sender;
        bool active;
    }

    // Mapping from the Hash of the secret code to the Gift data
    mapping(bytes32 => Gift) public gifts;

    event GiftCreated(bytes32 indexed giftHash, uint256 amount, address indexed sender);
    event GiftRedeemed(bytes32 indexed giftHash, address indexed receiver, uint256 amount);
    event GiftCancelled(bytes32 indexed giftHash, address indexed sender, uint256 amount);

    constructor() {}

    /**
     * @dev Create a new gift card.
     * @param _giftHash The keccak256 hash of the secret code.
     * Note: We pass the HASH, not the secret, so the secret remains private.
     */
    function createGift(bytes32 _giftHash) public payable {
        require(msg.value > 0, "Gift value must be > 0");
        require(!gifts[_giftHash].active, "Gift code already exists! Pick a new secret.");

        gifts[_giftHash] = Gift({
            amount: msg.value,
            sender: msg.sender,
            active: true
        });

        emit GiftCreated(_giftHash, msg.value, msg.sender);
    }

    /**
     * @dev Redeem a gift card using the secret code.
     * @param _secretCode The plaintext secret (e.g., "HappyBirthday").
     */
    function redeemGift(string memory _secretCode) public {
        // 1. Re-create the hash from the secret
        bytes32 codeHash = keccak256(abi.encodePacked(_secretCode));
        
        // 2. Find the gift
        Gift storage gift = gifts[codeHash];

        // 3. Verify validity
        require(gift.active, "Invalid code or gift already redeemed.");
        require(gift.amount > 0, "Gift has no value.");

        // 4. Update state (Effects)
        uint256 amount = gift.amount;
        gift.amount = 0;
        gift.active = false;

        // 5. Transfer ETH (Interactions)
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed.");

        emit GiftRedeemed(codeHash, msg.sender, amount);
    }

    /**
     * @dev Sender can cancel the gift and get money back if it hasn't been claimed.
     * Useful if you lose the secret code or typed it wrong.
     */
    function cancelGift(string memory _secretCode) public {
        bytes32 codeHash = keccak256(abi.encodePacked(_secretCode));
        Gift storage gift = gifts[codeHash];

        require(msg.sender == gift.sender, "Only the sender can cancel.");
        require(gift.active, "Gift already redeemed or inactive.");

        uint256 amount = gift.amount;
        gift.amount = 0;
        gift.active = false;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed.");

        emit GiftCancelled(codeHash, msg.sender, amount);
    }
}