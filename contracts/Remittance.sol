pragma solidity 0.5.8;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/lifecycle/Pausable.sol";

/// @title Transfer funds from A (on-chain) to C (off-chain) using B (on-chain) as exchange to fiat currency
/// @notice B9lab Blockstars Certified Ethereum Developer Course
/// @notice Module 7 project: Remittance
/// @author Fábio Corrêa <feamcor@gmail.com>
contract Remittance is Ownable, Pausable {
    using SafeMath for uint;

    struct Transaction {
        address sender;
        address recipient;
        uint amount;
        uint deadline;
    }

    // Amount to be charged per remittance.
    uint private remittanceFee;

    // Total balance of fees collected from remittances.
    uint public remittanceFeeBalance;

    // Key is remittance unique ID.
    mapping(bytes32 => Transaction) public remittances;

    event RemittanceFeeSet(address by, uint fee);

    event RemittanceFeeWithdrew(address by, uint balance);

    event RemittanceTransferred(
        bytes32 indexed remittanceId,
        address indexed sender,
        address indexed recipient,
        uint amount,
        uint fee,
        uint deadline
    );

    event RemittanceReceived(
        bytes32 indexed remittanceId,
        address indexed recipient,
        uint amount
    );

    event RemittanceReclaimed(
        bytes32 indexed remittanceId,
        address indexed sender,
        uint amount
    );

    modifier validClaim(
        bool _isReclaim,
        bytes32 _remittanceId,
        bytes32 _secret)
    {
        Transaction storage _remittance = remittances[_remittanceId];
        // If recipient address is 0x0, then remittance ID refers to a
        // remittance that does not exist, or that was released after a
        // valid claim throuhg `receive` or `reclaim` functions.
        require(_remittance.recipient != address(0x0), "not set or already claimed");
        // Check that sender is the correct one, depending on type of claim.
        require(msg.sender == (_isReclaim ? _remittance.sender : _remittance.recipient), "account mismatch");
        bytes32 _id = _isReclaim
            ? remittanceId(address(this), msg.sender, _remittance.recipient, _secret)
            : remittanceId(address(this), _remittance.sender, msg.sender, _secret);
        // Check that remittance being claimed is the one that the secret would refer to.
        require(_id == _remittanceId, "remittance ID mismatch");
        _;
    }

    /// @notice Instantiate contract and set its initial remittance fee
    /// @param _fee amount to be set as remittance fee
    /// @dev Emit `RemittanceFeeSet` event
    constructor(uint _fee) public {
        setFee(_fee);
    }

    /// @notice Set remittance attributes to zero, for releasing storage
    /// @param _remittanceId id of the remittance to be released
    function release(bytes32 _remittanceId) private {
        Transaction storage _remittance = remittances[_remittanceId];
        // Sender is not set as 0x0 in order to keep track of previous IDs.
        _remittance.recipient = address(0x0);
        _remittance.amount = uint(0);
        _remittance.deadline = uint(0);
    }

    /// @notice Start remittance by transferring funds from sender to contract, in escrow
    /// @notice Recipient will claim the funds on a final step
    /// @param _remittanceId id of the new remittance
    /// @param _recipient address of the recipient account
    /// @param _deadline number of seconds before the remittance could be claimed by sender (1..7 days)
    /// @dev Emit `RemittanceTransferred` event
    function transfer(bytes32 _remittanceId, address _recipient, uint _deadline)
        external
        payable
        whenNotPaused
    {
        require(_recipient != address(0x0), "invalid recipient");
        /// Stored sender address must be 0x0, which means that remittance ID is new.
        require(remittances[_remittanceId].sender == address(0x0), "previous remittance");
        /// Value transferred must be enough for remittance amount and fee.
        require(msg.value > remittanceFee, "value less than fee");
        require(_deadline >= 1 days && _deadline <= 7 days, "invalid deadline");
        remittanceFeeBalance = remittanceFeeBalance.add(remittanceFee);
        Transaction memory _remittance = Transaction({
            sender: msg.sender,
            recipient: _recipient,
            amount: msg.value.sub(remittanceFee),
            deadline: block.timestamp.add(_deadline)
        });
        emit RemittanceTransferred(
            _remittanceId,
            _remittance.sender,
            _remittance.recipient,
            _remittance.amount,
            remittanceFee,
            _remittance.deadline);
        remittances[_remittanceId] = _remittance;
    }

    /// @notice Complete remittance by transferring funds in escrow from contract to recipient
    /// @param _remittanceId id of the remittance to be claimed
    /// @param _secret secret key used to generate the remittance ID and validate this transaction
    /// @dev Emit `RemittanceReceived` event
    function receive(bytes32 _remittanceId, bytes32 _secret)
        external
        whenNotPaused
        validClaim(false, _remittanceId, _secret)
    {
        uint _amount = remittances[_remittanceId].amount;
        emit RemittanceReceived(_remittanceId, msg.sender, _amount);
        release(_remittanceId);
        msg.sender.transfer(_amount);
    }

    /// @notice Revert remittance by transferring funds in escrow from contract to sender, after deadline
    /// @param _remittanceId id of the remittance to be claimed
    /// @param _secret secret key used to generate the remittance ID and validate this transaction
    /// @dev Emit `RemittanceReclaimed` event
    function reclaim(bytes32 _remittanceId, bytes32 _secret)
        external
        whenNotPaused
        validClaim(true, _remittanceId, _secret)
    {
        require(block.timestamp <= remittances[_remittanceId].deadline, "too early to reclaim");
        uint _amount = remittances[_remittanceId].amount;
        emit RemittanceReclaimed(_remittanceId, msg.sender, _amount);
        release(_remittanceId);
        msg.sender.transfer(_amount);
    }

    /// @notice Withdraw accumulated remittance fees
    /// @dev Emit `RemittanceFeeWithdrew` event
    function withdraw() external whenNotPaused onlyOwner {
        uint _balance = remittanceFeeBalance;
        require(_balance != uint(0), "no balance available");
        emit RemittanceFeeWithdrew(msg.sender, _balance);
        remittanceFeeBalance = uint(0);
        msg.sender.transfer(_balance);
    }

    /// @notice Return current remittance fee
    /// @return remittance fee
    function fee() public view returns (uint) {
        return remittanceFee;
    }

    /// @notice Set remittance fee
    /// @param _fee remittance fee value
    /// @dev Emit `RemittanceFeeSet` event
    function setFee(uint _fee) public onlyOwner {
        require(_fee != uint(0), "fee cannot be zero");
        if(_fee != remittanceFee) {
            emit RemittanceFeeSet(msg.sender, _fee);
            remittanceFee = _fee;
        }
    }

    /// @notice Helper function to generate unique remittance ID
    /// @param _contract address of the Remittance contract
    /// @param _sender address of the sender account
    /// @param _recipient address of the recipient account
    /// @param _secret key generated by sender as secret validation factor
    /// @return Remittance ID calculated based on the input parameters
    /// @dev Function is pure to ensure non-visibility through blockchain
    function remittanceId(
        address _contract,
        address _sender,
        address _recipient,
        bytes32 _secret)
        public
        pure
        returns (bytes32)
    {
        require(_sender != address(0x0), "invalid sender");
        require(_recipient != address(0x0), "invalid recipient");
        return keccak256(abi.encodePacked(_contract, _sender, _recipient, _secret));
    }
}