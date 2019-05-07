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

    enum RemittanceStatus {
        NotSet,      // 0 - status not set
        Transferred, // 1 - start - funds transferred from sender to contract (in escrow)
        Received,    // 2 - finish - recipient (exchange) withdraw funds (receive) from contract
        Reclaimed    // 3 - finish - sender withdraw unclaimed funds (reclaim) from contract, after deadline is reached
    }

    struct Transaction {
        address sender;
        address recipient;
        uint amount;
        uint fee;
        uint deadline;
        RemittanceStatus status;
    }

    // Amount to be charged per remittance.
    uint public remittanceFee;

    // Total balance of fees collected from remittances.
    uint public remittanceFeeBalance;

    // Key is remittance unique ID.
    mapping(bytes32 => Transaction) private remittances;

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
        bytes32 _secret1,
        bytes32 _secret2)
    {
        Transaction storage _remittance = remittances[_remittanceId];
        require(_remittance.status == RemittanceStatus.Transferred, "not transferred");
        require(msg.sender == (_isReclaim ? _remittance.sender : _remittance.recipient), "account mismatch");
        bytes32 _id = _isReclaim
            ? remittanceId(msg.sender, _remittance.recipient, _secret1, _secret2)
            : remittanceId(_remittance.sender, msg.sender, _secret1, _secret2);
        require(_id == _remittanceId, "remittance ID mismatch");
        _;
    }

    constructor(uint _fee) public {
        setFee(_fee);
    }

    function transfer(bytes32 _remittanceId, address _recipient, uint _deadline)
        external
        payable
        whenNotPaused
    {
        require(_recipient != address(0x0), "invalid recipient");
        require(remittances[_remittanceId].status == RemittanceStatus.NotSet, "existing puzzle");
        require(msg.value != uint(0), "value is zero");
        require(msg.value > remittanceFee, "value less than fee");
        require(msg.value.sub(remittanceFee) != uint(0), "amount after fee is zero");
        require(_deadline >= 1 days && _deadline <= 7 days, "invalid deadline");
        remittanceFeeBalance = remittanceFeeBalance.add(remittanceFee);
        Transaction memory _remittance = Transaction({
            sender: msg.sender,
            recipient: _recipient,
            amount: msg.value.sub(remittanceFee),
            fee: remittanceFee,
            deadline: block.timestamp.add(_deadline),
            status: RemittanceStatus.Transferred
        });
        remittances[_remittanceId] = _remittance;
        emit RemittanceTransferred(
            _remittanceId,
            _remittance.sender,
            _remittance.recipient,
            _remittance.amount,
            _remittance.fee,
            _remittance.deadline);
    }

    function receive(bytes32 _remittanceId, bytes32 _secret1, bytes32 _secret2)
        external
        whenNotPaused
        validClaim(false, _remittanceId, _secret1, _secret2)
    {
        remittances[_remittanceId].status = RemittanceStatus.Received;
        uint _amount = remittances[_remittanceId].amount;
        msg.sender.transfer(_amount);
        emit RemittanceReceived(_remittanceId, msg.sender, _amount);
    }

    function reclaim(bytes32 _remittanceId, bytes32 _secret1, bytes32 _secret2)
        external
        whenNotPaused
        validClaim(true, _remittanceId, _secret1, _secret2)
    {
        require(block.timestamp <= remittances[_remittanceId].deadline, "too early to reclaim");
        remittances[_remittanceId].status = RemittanceStatus.Reclaimed;
        uint _amount = remittances[_remittanceId].amount;
        msg.sender.transfer(_amount);
        emit RemittanceReclaimed(_remittanceId, msg.sender, _amount);
    }

    function remittanceInfo(bytes32 _remittanceId)
        external
        view
        whenNotPaused
        returns (address sender, address recipient, uint amount, uint fee, uint deadline, uint status)
    {
        Transaction storage _remittance = remittances[_remittanceId];
        return (
            _remittance.sender,
            _remittance.recipient,
            _remittance.amount,
            _remittance.fee,
            _remittance.deadline,
            uint(_remittance.status)
        );
    }

    function setFee(uint _fee) public onlyOwner whenNotPaused {
        require(_fee != uint(0), "fee cannot be zero");
        if(_fee != remittanceFee) {
            remittanceFee = _fee;
        }
    }

    function remittanceId(
        address _sender,
        address _recipient,
        bytes32 _part1,
        bytes32 _part2)
        public
        pure
        returns (bytes32 id)
    {
        require(_sender != address(0x0), "invalid sender");
        require(_recipient != address(0x0), "invalid recipient");
        id = keccak256(abi.encodePacked(_sender, _recipient, _part1, _part2));
    }
}