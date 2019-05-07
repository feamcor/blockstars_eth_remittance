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
        require(_remittance.recipient != address(0x0), "not set or already claimed");
        require(msg.sender == (_isReclaim ? _remittance.sender : _remittance.recipient), "account mismatch");
        bytes32 _id = _isReclaim
            ? remittanceId(address(this), msg.sender, _remittance.recipient, _secret)
            : remittanceId(address(this), _remittance.sender, msg.sender, _secret);
        require(_id == _remittanceId, "remittance ID mismatch");
        _;
    }

    constructor(uint _fee) public {
        setFee(_fee);
    }

    function release(bytes32 _remittanceId) private {
        Transaction storage _remittance = remittances[_remittanceId];
        _remittance.recipient = address(0x0);
        _remittance.amount = uint(0);
        _remittance.deadline = uint(0);
    }

    function transfer(bytes32 _remittanceId, address _recipient, uint _deadline)
        external
        payable
        whenNotPaused
    {
        require(_recipient != address(0x0), "invalid recipient");
        require(remittances[_remittanceId].sender == address(0x0), "previous remittance");
        require(msg.value > remittanceFee, "value less than fee");
        require(_deadline >= 1 days && _deadline <= 7 days, "invalid deadline");
        remittanceFeeBalance = remittanceFeeBalance.add(remittanceFee);
        Transaction memory _remittance = Transaction({
            sender: msg.sender,
            recipient: _recipient,
            amount: msg.value.sub(remittanceFee),
            deadline: block.timestamp.add(_deadline)
        });
        remittances[_remittanceId] = _remittance;
        emit RemittanceTransferred(
            _remittanceId,
            _remittance.sender,
            _remittance.recipient,
            _remittance.amount,
            remittanceFee,
            _remittance.deadline);
    }

    function receive(bytes32 _remittanceId, bytes32 _secret)
        external
        whenNotPaused
        validClaim(false, _remittanceId, _secret)
    {
        uint _amount = remittances[_remittanceId].amount;
        release(_remittanceId);
        msg.sender.transfer(_amount);
        emit RemittanceReceived(_remittanceId, msg.sender, _amount);
    }

    function reclaim(bytes32 _remittanceId, bytes32 _secret)
        external
        whenNotPaused
        validClaim(true, _remittanceId, _secret)
    {
        require(block.timestamp <= remittances[_remittanceId].deadline, "too early to reclaim");
        uint _amount = remittances[_remittanceId].amount;
        release(_remittanceId);
        msg.sender.transfer(_amount);
        emit RemittanceReclaimed(_remittanceId, msg.sender, _amount);
    }

    function fee() public view whenNotPaused returns (uint) {
        return remittanceFee;
    }

    function setFee(uint _fee) public onlyOwner whenNotPaused {
        require(_fee != uint(0), "fee cannot be zero");
        if(_fee != remittanceFee) {
            remittanceFee = _fee;
        }
    }

    function remittanceId(
        address _contract,
        address _sender,
        address _recipient,
        bytes32 _secret)
        public
        pure
        returns (bytes32 id)
    {
        require(_sender != address(0x0), "invalid sender");
        require(_recipient != address(0x0), "invalid recipient");
        id = keccak256(abi.encodePacked(_contract, _sender, _recipient, _secret));
    }
}