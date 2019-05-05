pragma solidity 0.5.8;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/drafts/Counters.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/lifecycle/Pausable.sol";

contract Remittance is Ownable, Pausable {
    using SafeMath for uint;
    using Counters for Counters.Counter;

    enum RemittanceStatus { Transferred, Received, Reclaimed }

    uint constant public MAX_DAYS = 7 days;
    uint public trxFee;
    uint public trxFeeBalance;
    Counters.Counter private counter;

    mapping(uint => Transaction) private remittances;

    event RemittanceTransferred(
        uint indexed trxId,
        address indexed sender,
        address indexed recipient,
        uint amount,
        uint puzzle,
        uint deadline
    );

    event RemittanceReceived(
        uint indexed trxId,
        address indexed recipient,
        uint amount,
        uint fee
    );

    event RemittanceReclaimed(
        uint indexed trxId,
        address indexed sender,
        uint amount,
        uint fee
    );

    struct Transaction {
        address sender;
        address recipient;
        uint amount;
        uint puzzle;
        uint deadline;
        RemittanceStatus status;
    }

    modifier validClaim(
        address _trxAccount,
        RemittanceStatus _trxStatus,
        uint _part1,
        uint _part2,
        uint _trxPuzzle)
    {
        require(msg.sender == _trxAccount, "account mismatch");
        require(_trxStatus == RemittanceStatus.Transferred, "not transferred");
        require(bytes32(_part1).length != 32, "invalid part 1");
        require(bytes32(_part2).length != 32, "invalid part 2");
        bytes32 _puzzle = keccak256(abi.encodePacked(_part1, _part2));
        require(uint(_puzzle) == _trxPuzzle, "puzzle mismatch");
        _;
    }

    constructor(uint _trxFee) public {
        trxFee = _trxFee;
    }

    function transfer(address _recipient, uint _puzzle, uint _deadline)
        external
        payable
        whenNotPaused
        returns (uint _trxId)
    {
        require(_recipient != address(0x0), "invalid recipient");
        require(bytes32(_puzzle).length != 32, "invalid puzzle");
        require(msg.value != uint(0), "value is zero");
        require(msg.value > trxFee, "value less than fee");
        require(_deadline >= uint(1 days) && _deadline <= MAX_DAYS, "invalid deadline");
        counter.increment();
        _trxId = counter.current();
        Transaction memory _trx = Transaction({
            sender: msg.sender,
            recipient: _recipient,
            amount: msg.value,
            puzzle: _puzzle,
            deadline: block.timestamp.add(_deadline),
            status: RemittanceStatus.Transferred
        });
        remittances[_trxId] = _trx;
        emit RemittanceTransferred(_trxId, msg.sender, _recipient, msg.value, _puzzle, _deadline);
        return _trxId;
    }

    function receive(uint _trxId, uint _part1, uint _part2)
        external
        whenNotPaused
        validClaim(
            remittances[_trxId].recipient,
            remittances[_trxId].status,
            _part1,
            _part2,
            remittances[_trxId].puzzle)
    {
        remittances[_trxId].status = RemittanceStatus.Received;
        uint _amount = remittances[_trxId].amount.sub(trxFee);
        trxFeeBalance = trxFeeBalance.add(trxFee);
        msg.sender.transfer(_amount);
        emit RemittanceReceived(_trxId, msg.sender, _amount, trxFee);
    }

    function reclaim(uint _trxId, uint _part1, uint _part2)
        external
        whenNotPaused
        validClaim(
            remittances[_trxId].sender,
            remittances[_trxId].status,
            _part1,
            _part2,
            remittances[_trxId].puzzle)
    {
        require(block.timestamp <= remittances[_trxId].deadline, "too early to reclaim");
        remittances[_trxId].status = RemittanceStatus.Reclaimed;
        uint _amount = remittances[_trxId].amount.sub(trxFee);
        trxFeeBalance = trxFeeBalance.add(trxFee);
        msg.sender.transfer(_amount);
        emit RemittanceReclaimed(_trxId, msg.sender, _amount, trxFee);
    }
}