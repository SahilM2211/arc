// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BuyMeACoffee
 * @dev A decentralized tipping platform.
 * Fans send ETH + a message.
 * Creator withdraws the ETH.
 * Zero platform fees.
 *
 * Easy Deployment: No constructor arguments needed.
 */
contract BuyMeACoffee {

    // Event to emit when a memo is created.
    event NewMemo(
        address indexed from,
        uint256 timestamp,
        string name,
        string message
    );

    // Memo struct.
    struct Memo {
        address from;
        uint256 timestamp;
        string name;
        string message;
    }

    // List of all memos received from friends.
    Memo[] public memos;

    // Address of contract deployer.
    address payable public owner;

    // Deploy logic.
    constructor() {
        owner = payable(msg.sender);
    }

    /**
     * @dev buyCoffee to send ETH and leave a note.
     * @param _name Name of the tipper.
     * @param _message A nice message from the tipper.
     */
    function buyCoffee(string memory _name, string memory _message) public payable {
        require(msg.value > 0, "Can't buy coffee with 0 ETH");

        // Add the memo to storage
        memos.push(Memo(
            msg.sender,
            block.timestamp,
            _name,
            _message
        ));

        // Emit a log event when a new memo is created
        emit NewMemo(
            msg.sender,
            block.timestamp,
            _name,
            _message
        );
    }

    /**
     * @dev withdraw sends the entire balance stored in this contract to the owner.
     */
    function withdrawTips() public {
        require(msg.sender == owner, "Only the owner can withdraw tips");
        require(address(this).balance > 0, "No tips to withdraw");
        
        (bool success, ) = owner.call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    /**
     * @dev retrieve all the memos stored on the blockchain.
     */
    function getMemos() public view returns (Memo[] memory) {
        return memos;
    }
}