// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

contract mainMultisig {
    event Deposit(address indexed sender, uint256 amount, uint256 balance);
    address public deployedContract;
    event SubmitTransaction(
        address indexed owner,
        uint256 indexed txIndex,
        address indexed to,
        uint256 value,
        bytes data
    );

    event ContractDeployed(
        address indexed sender,
        address indexed contractAddress
    );

    event ConfirmTransaction(address indexed owner, uint256 indexed txIndex);
    event RevokeConfirmation(address indexed owner, uint256 indexed txIndex);
    event ExecuteTransaction(address indexed owner, uint256 indexed txIndex);

    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public numConfirmationsRequired;

    struct Transaction {
        uint8 txType; //1 for normal transaction..... 2 for contract creation
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 numConfirmations;
    }

    struct Contract {
        uint256 txIndex;
        address contractAddress;
    }
    // mapping from tx index => owner => bool
    mapping(uint256 => mapping(address => bool)) public isTransactionConfirmed;
    // Contract[] public contracts;
    mapping(uint256 => Contract) public deployedContracts;

    Transaction[] public transactions;

    modifier onlyOwner() {
        require(isOwner[msg.sender], "not owner");
        _;
    }

    modifier txExists(uint256 _txIndex) {
        require(_txIndex < transactions.length, "tx does not exist");
        _;
    }

    modifier txNotExecuted(uint256 _txIndex) {
        require(!transactions[_txIndex].executed, "tx already executed");
        _;
    }

    modifier txNotConfirmed(uint256 _txIndex) {
        require(
            !isTransactionConfirmed[_txIndex][msg.sender],
            "tx already confirmed"
        );
        _;
    }

    modifier contractTxNotConfirmed(uint256 _txIndex) {
        require(
            !isTransactionConfirmed[_txIndex][msg.sender],
            "tx already confirmed"
        );
        _;
    }

    constructor(address[] memory _owners, uint256 _numConfirmationsRequired) {
        require(_owners.length > 0, "owners required");
        require(
            _numConfirmationsRequired > 0 &&
                _numConfirmationsRequired <= _owners.length,
            "invalid number of required confirmations"
        );

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];

            require(owner != address(0), "invalid owner");
            require(!isOwner[owner], "owner not unique");

            isOwner[owner] = true;
            owners.push(owner);
        }

        numConfirmationsRequired = _numConfirmationsRequired;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    function submitTransaction(
        uint8 _type,
        address _to,
        uint256 _value,
        bytes memory _data
    ) public onlyOwner {
        uint256 txIndex = transactions.length;

        transactions.push(
            Transaction({
                txType: _type,
                to: _to,
                value: _value,
                data: _data,
                executed: false,
                numConfirmations: 1
            })
        );

        emit SubmitTransaction(msg.sender, txIndex, _to, _value, _data);
    }

    function confirmTransaction(uint256 _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        txNotExecuted(_txIndex)
        txNotConfirmed(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        transaction.numConfirmations += 1;
        isTransactionConfirmed[_txIndex][msg.sender] = true;

        emit ConfirmTransaction(msg.sender, _txIndex);
    if(transaction.numConfirmations >= numConfirmationsRequired){
        executeTransaction(_txIndex);
    }
    }

    function executeTransaction(uint256 _txIndex)
        internal
        onlyOwner
        txExists(_txIndex)
        txNotExecuted(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];

        // require(
        //     transaction.numConfirmations >= numConfirmationsRequired,
        //     "cannot execute tx"
        // );

        if (transaction.txType == 1) {
            transaction.executed = true;

            (bool success, ) = transaction.to.call{value: transaction.value}(
                transaction.data
            );
            require(success, "tx failed");

            emit ExecuteTransaction(msg.sender, _txIndex);
        } else if (transaction.txType == 2) {
            transaction.executed = true;

            address newContractAddress;
            bytes memory contractBytecode = transaction.data;

            assembly {
                newContractAddress := create(
                    0,
                    add(contractBytecode, 0x20),
                    mload(contractBytecode)
                )
            }
            require(newContractAddress != address(0), "Deployment failed");

            Contract memory newContract = Contract({
                txIndex: _txIndex,
                contractAddress: newContractAddress
            });
            deployedContracts[_txIndex] = newContract;

            emit ExecuteTransaction(msg.sender, _txIndex);
            emit ContractDeployed(msg.sender, newContractAddress);
        }
    }

    function revokeConfirmation(uint256 _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        txNotExecuted(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];

        require(
            isTransactionConfirmed[_txIndex][msg.sender],
            "tx not confirmed"
        );

        transaction.numConfirmations -= 1;
        isTransactionConfirmed[_txIndex][msg.sender] = false;

        emit RevokeConfirmation(msg.sender, _txIndex);
    }

    function getOwners() public view returns (address[] memory) {
        return owners;
    }

    function getTransactionCount() public view returns (uint256) {
        return transactions.length;
    }

    function getTransaction(uint256 _txIndex)
        public
        view
        returns (
            uint8 txType,
            address to,
            uint256 value,
            bytes memory data,
            bool executed,
            uint256 numConfirmations
        )
    {
        Transaction storage transaction = transactions[_txIndex];

        return (
            transaction.txType,
            transaction.to,
            transaction.value,
            transaction.data,
            transaction.executed,
            transaction.numConfirmations
        );
    }

    function getContract(uint256 _txIndex)
        public
        view
        returns (Contract memory)
    {
        return (deployedContracts[_txIndex]);
    }
}
