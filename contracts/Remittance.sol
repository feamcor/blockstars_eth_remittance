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
    // Minimum number of seconds before a remittance could be reclaimed.
    uint private deadlineRangeMin;
    // Maximum number of seconds before a remittance could be reclaimed.
    uint private deadlineRangeMax;
    // Key is remittance unique ID.
    mapping(bytes32 => Transaction) public remittances;

    event RemittanceFeeSet(address by, uint fee);

    event RemittanceFeeWithdrew(address by, uint balance);

    event RemittanceDeadlineRangeSet(address by, uint mix, uint max);

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

    /// @notice Instantiate contract and set its initial remittance fee
    /// @param _fee amount to be set as remittance fee
    /// @param _min minimum number of seconds before remittance could be reclaimed
    /// @param _max maximum number of seconds before remittance could be reclaimed
    /// @dev Emit `RemittanceFeeSet` event
    constructor(uint _fee, uint _min, uint _max) public {
        setFee(_fee);
        setDeadlineRange(_min, _max);
    }

    /// @notice Set remittance attributes to zero, for releasing storage
    /// @param _remittanceId id of the remittance to be released
    function release(bytes32 _remittanceId) private {
        Transaction storage _remittance = remittances[_remittanceId];
        _remittance.sender = address(0x0);
        _remittance.recipient = address(0x0);
        _remittance.amount = uint(0);
        // _remittance.deadline is not zeroed in order to keep track of previous remittance IDs.
    }

    /// @notice Start remittance by transferring funds from sender to contract, in escrow
    /// @notice Recipient will claim the funds on a final step
    /// @param _remittanceId id of the new remittance
    /// @param _recipient address of the recipient account
    /// @param _deadline number of seconds before the remittance could be claimed by sender (between min and max)
    /// @dev Emit `RemittanceTransferred` event
    function transfer(bytes32 _remittanceId, address _recipient, uint _deadline)
        external
        payable
        whenNotPaused
    {
        require(_recipient != address(0x0), "invalid recipient");
        /// Stored remittance deadline must be zero, which means that remittance ID is new.
        require(remittances[_remittanceId].deadline == uint(0), "previous remittance");
        /// Value transferred must be enough for remittance amount and fee.
        require(msg.value > remittanceFee, "value less than fee");
        require(_deadline >= deadlineRangeMin && _deadline <= deadlineRangeMax, "deadline out of range");
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
    /// @param _sender address of the sender account
    /// @param _secret secret key used to generate the remittance ID and validate this transaction
    /// @dev Emit `RemittanceReceived` event
    function receive(address _sender, bytes32 _secret)
        external
        whenNotPaused
    {
        bytes32 _remittanceId = generateRemittanceId(address(this), _sender, msg.sender, _secret);
        Transaction storage _remittance = remittances[_remittanceId];
        require(_remittance.deadline != uint(0), "remittance not set");
        require(_remittance.amount != uint(0), "remittance already claimed");
        require(_remittance.sender == _sender, "sender mismatch");
        require(_remittance.recipient == msg.sender, "recipient mismatch");
        uint _amount = remittances[_remittanceId].amount;
        emit RemittanceReceived(_remittanceId, msg.sender, _amount);
        release(_remittanceId);
        msg.sender.transfer(_amount);
    }

    /// @notice Revert remittance by transferring funds in escrow from contract to sender, after deadline
    /// @param _recipient address of the recipient account
    /// @param _secret secret key used to generate the remittance ID and validate this transaction
    /// @dev Emit `RemittanceReclaimed` event
    function reclaim(address _recipient, bytes32 _secret)
        external
        whenNotPaused
    {
        bytes32 _remittanceId = generateRemittanceId(address(this), msg.sender, _recipient, _secret);
        Transaction storage _remittance = remittances[_remittanceId];
        require(_remittance.deadline != uint(0), "remittance not set");
        require(_remittance.amount != uint(0), "remittance already claimed");
        require(_remittance.sender == msg.sender, "sender mismatch");
        require(_remittance.recipient == _recipient, "recipient mismatch");
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
        emit RemittanceFeeSet(msg.sender, _fee);
        remittanceFee = _fee;
    }

    /// @notice Return deadline range
    /// @return Minimum (start) and maximum (end) number of seconds
    function deadlineRange() public view returns (uint min, uint max) {
        return (deadlineRangeMin, deadlineRangeMax);
    }

    /// @notice Set deadline range
    /// @param _min Minimum number of seconds (not zero, less than max)
    /// @param _max Maximum number of seconds (greater than min)
    function setDeadlineRange(uint _min, uint _max) public onlyOwner {
        require(_min > uint(0), "min cannot be zero");
        require(_max >= _min, "max must be >= min");
        emit RemittanceDeadlineRangeSet(msg.sender, _min, _max);
        deadlineRangeMin = _min;
        deadlineRangeMax = _max;
    }

    /// @notice Helper function to generate unique remittance ID
    /// @param _contract address of the Remittance contract
    /// @param _sender address of the sender account
    /// @param _recipient address of the recipient account
    /// @param _secret key generated by sender as secret validation factor
    /// @return Remittance ID calculated based on the input parameters
    /// @dev Function is pure to ensure non-visibility through blockchain
    function generateRemittanceId(
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