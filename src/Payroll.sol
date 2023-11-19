// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// imports
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
 /**
     * @author Funkornaut
     * @notice This is a simple payroll contract that allows the owner to add employees and pay them.
     * Employees are able to select which evm chain & tokens they wish to be paid on.
     * Assumptions:
     *  Original Employee address/wallet is created by Employer admin and the employeeId is created from that wallet address
     *  We only pay Employees in BnMTokens (therortically this will be a stablecoin) 
     */

// token sender 0x8B54f0741eE90d4b688681B6F8d5B7F8A7EB3031 --trev remix no owner restrictions
/// bnm token address 0xD21341536c5cF5EB1bcb58f6723cE26e8D8E90e4 -- avax
// 0x9768818565ED5968fAACC6F66ca02CBf2785dB84 -- trev addy 'employee'
// new payroll 0xd492948950A3ed53A90c07918877C370a963bcAe
interface ICCIPTokenSender {
    function transferTokens(uint64 _destinationChainSelector, address _receiver, address _token, uint256 _amount) external returns (bytes32);
    // ... other necessary functions
}

contract Payroll is Ownable {

//////////////
/// errors ///
////////////// 
error PercentageMustEqual100();
error InvalidAddress();
error EmployeeAlreadyExists();
error EmployeeDoesNotExists();
error EmployeeIsNotSalary();
error EmployeeIsNotHourly();
error HoursWorkedArrayDoesNotMatchEmployees(uint8[]);

// interfaces, libraries, contracts

///@dev Burn And Mint Test Token assume this is the stablecoin the Employer has choosen to pay its Employees in 
IERC20 public bnmToken;
ICCIPTokenSender public ccip;

// Type declarations

// State variables

    // eth sepolia
    uint64 public immutable i_destinationChainIdEth = 16015286601757825753;
    // OP goerli
    uint64 public immutable i_destinationChainIDdOP = 2664363617261496610;
    // Avax Fuji
    // uint64 public immutable i_destinationChainIdAvax = 14767482510784806043;
    // ARB Goerli
    // uint64 public immutable i_destinationChainIdArb = 6101244977088475029; 
    // Polygon Mumbai
    uint64 public immutable i_destinationChainIdPolygon = 12532609583862916517;
    // BNB Testnet
    uint64 public immutable i_destinationChainIdBnb = 13264668187771770619;
    // Base Goreli
    uint64 public immutable i_destinationChainIdBase = 5790810961207155433;

    struct Employee {
        // Primary wallet address of the employee, could be used on any chain, is updateable by employee or employeer
        address primaryWallet; 
        // Unique identifier for the employee - hash of the originally assigned wallet and block.timestamp
        bytes32 employeeId;
        bool isSalary;
        bool localChainPayment;
        uint256 payRate;
        // the split information for each chain
        PaymentSplit paymentSplits; 
    }

    ///@dev Mapping of primary wallet to Employee struct
    mapping (address => Employee) public employees;

    struct PaymentSplit {
        // The percentage of pay to be sent to those chains
        uint8 paySplitPercentageEth; 
        uint8 paySplitPercentageOp; 
        //uint8 paySplitPercentageAvax; 
        //uint8 paySplitPercentageArb; 
        uint8 paySplitPercentagePolygon; 
        uint8 paySplitPercentageBnb; 
        uint8 paySplitPercentageBase; 
    }

    // mapping of employeeId to PaymentSplit struct -- might not be necessary
    mapping (bytes32 => PaymentSplit) public paymentSplits;

    // array of all employees addresses
    address[] public allEmployees;
    // array of all salaried employees
    address[] public salariedEmployees;
    // array of all hourly employees
    address[] public hourlyEmployees;

    // Events

    event EmployeePaid(address indexed _employeeAddress, uint256 _amount);

// Modifiers
    modifier onlyEmployee() {
        require(employees[msg.sender].employeeId != 0, "Only employees can call this function");
        _;
    }

    modifier onlyEmployeeOrOwner() {
        require(employees[msg.sender].employeeId != 0 || msg.sender == owner(), "Only employees or owner can call this function");
        _;
    }

// Functions

// Layout of Functions:
// constructor
    // might want to set the destinationChainIds in the constructor?
    // maybe make a constructor params struct that can set all chainIds, CCIPcontract, token whitelist?
    constructor(address _ccipTokenSender, address _bnmToken) {
        ccip = ICCIPTokenSender(_ccipTokenSender);
        bnmToken = IERC20(_bnmToken);
    }

// receive function (if exists)
// fallback function (if exists)
    function recieve() external payable {}


// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

    /// TOKEN SENDING WORKING WITH THIS LOGIC
    /// @notice Payment function
    /// @dev This function will pay all employees on the payroll
    /// @dev only callable by the owner or automation contract
    function pay(uint64 _destinationChainSelector, address _employeeAddress, address _token, uint256 _amount) public returns (bytes32 messageId) {
        //@todo not sure I need this approval
        bnmToken.approve(address(ccip), _amount);

        bool success = bnmToken.transfer(address(ccip), _amount);
        require(success, "Token transfer failed");

        messageId = ccip.transferTokens(_destinationChainSelector, _employeeAddress, _token, _amount);

    }
    
    function payEmployee(address _employeeAddress, uint8 _hoursWorked) external  {
        //"Invalid address"
        if (_employeeAddress == address(0)) {
            revert InvalidAddress();
        }
        //@todo can this be memory?
        Employee storage employee = employees[_employeeAddress];

        //"Employee does not exist"
        if (employees[_employeeAddress].employeeId == 0) {
            revert EmployeeDoesNotExists();
        }

        uint256 weeklyPay = employees[_employeeAddress].isSalary 
            ? _calculateWeeklyPaymentSalary(_employeeAddress) 
            : _calculateWeeklyPaymentHourly(_employeeAddress, _hoursWorked);

        if (employee.localChainPayment == true) {
            bool success = bnmToken.transfer(_employeeAddress, weeklyPay);
            require(success, "Token transfer failed");
        }

        PaymentSplit memory splits = employees[_employeeAddress].paymentSplits;
        

        // Transfer tokens to each chain according to the payment split
        _transferToChain(i_destinationChainIdEth, _employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageEth) / 100));
        _transferToChain(i_destinationChainIDdOP, _employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageOp) / 100));
        //_transferToChain(i_destinationChainIdAvax, _employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageAvax) / 100));
       // _transferToChain(i_destinationChainIdArb, _employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageArb) / 100));
        _transferToChain(i_destinationChainIdPolygon, _employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentagePolygon) / 100));
        _transferToChain(i_destinationChainIdBnb, _employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageBnb) / 100));
        _transferToChain(i_destinationChainIdBase, _employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageBase) / 100));


        //ccip.transferTokens(, _employeeAddress, , weeklyPay)
        
        emit EmployeePaid(_employeeAddress, weeklyPay);
    }

    function payAllSallaryEmployees() public onlyOwner {
        for(uint i = 0; i < salariedEmployees.length; ++i) {
        address employeeAddress = salariedEmployees[i];

        uint256 weeklyPay = _calculateWeeklyPaymentSalary(employeeAddress);

        PaymentSplit memory splits = employees[employeeAddress].paymentSplits;
        

        // Transfer tokens to each chain according to the payment split
        _transferToChain(i_destinationChainIdEth, employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageEth) / 100));
        _transferToChain(i_destinationChainIDdOP, employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageOp) / 100));
        //_transferToChain(i_destinationChainIdAvax, _employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageAvax) / 100));
        // _transferToChain(i_destinationChainIdArb, employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageArb) / 100));
        _transferToChain(i_destinationChainIdPolygon, employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentagePolygon) / 100));
        _transferToChain(i_destinationChainIdBnb, employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageBnb) / 100));
        _transferToChain(i_destinationChainIdBase, employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageBase) / 100));

        }
    }

    function payAllHourlyEmployees(uint8[] calldata _hoursWorked) public onlyOwner {
        if (hourlyEmployees.length != _hoursWorked.length){
            revert HoursWorkedArrayDoesNotMatchEmployees(_hoursWorked);
        }

        for(uint i = 0; i < hourlyEmployees.length; ++i){
            address employeeAddress = hourlyEmployees[i];
            
            uint256 weeklyPay = _calculateWeeklyPaymentHourly(employeeAddress, _hoursWorked[i]);

            PaymentSplit memory splits = employees[employeeAddress].paymentSplits;
        
        // Transfer tokens to each chain according to the payment split
        _transferToChain(i_destinationChainIdEth, employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageEth) / 100));
        _transferToChain(i_destinationChainIDdOP, employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageOp) / 100));
        //_transferToChain(i_destinationChainIdAvax, _employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageAvax) / 100));
        // _transferToChain(i_destinationChainIdArb, employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageArb) / 100));
        _transferToChain(i_destinationChainIdPolygon, employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentagePolygon) / 100));
        _transferToChain(i_destinationChainIdBnb, employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageBnb) / 100));
        _transferToChain(i_destinationChainIdBase, employeeAddress, address(bnmToken), ((weeklyPay * splits.paySplitPercentageBase) / 100));


        }

    }

    function payAllEmployees(uint8[] calldata _hoursWorked) external onlyOwner {
        payAllSallaryEmployees();
        payAllHourlyEmployees(_hoursWorked);
    }

    function _transferToChain(uint64 _destinationChainSelector, address _receiver, address _token, uint256 _amount) internal returns (bytes32 messageId) {
        // not sure I need this approval
        bnmToken.approve(address(ccip), _amount);

        bool success = bnmToken.transfer(address(ccip), _amount);
        require(success, "Token transfer failed");
        
        messageId = ccip.transferTokens(_destinationChainSelector, _receiver, _token, _amount);

    }


    ///////////////////////////////////////////////
    /// Only Owner Employee Managment Functions ///
    ///////////////////////////////////////////////

    ///@dev if employee _isSalary = true then _payRate is their annual salary. 
    ///@dev if employee _isSalary = false then _payRate is their hourly rate. 
    function addEmployee(address _employeeAddress, bool _isSalary, uint256 _payRate) external onlyOwner {
        //"Invalid address"
        if (_employeeAddress == address(0)) {
            revert InvalidAddress();
        }
        //"Employee already exists"
        if (employees[_employeeAddress].employeeId != 0) {
            revert EmployeeAlreadyExists();
        }

        // Generate a unique ID for the new employee
        // Employee address has been created by Employer w/ account abstraction
        bytes32 employeeId = keccak256(abi.encodePacked(_employeeAddress, block.timestamp));

        Employee memory newEmployee = Employee({
            employeeId: employeeId,
            primaryWallet: _employeeAddress,
            isSalary: _isSalary,
            localChainPayment: true,
            payRate: _payRate,
            paymentSplits: PaymentSplit({
                paySplitPercentageEth: 0,
                paySplitPercentageOp: 0, 
                //paySplitPercentageAvax: 0, 
                //paySplitPercentageArb: 0,
                paySplitPercentagePolygon: 0, 
                paySplitPercentageBnb: 0,
                paySplitPercentageBase: 0
            })
        });

        // update employees mapping
        employees[_employeeAddress] = newEmployee;
        // update allEmployees array
        allEmployees.push(_employeeAddress); 
        // update salary/hourly array
        if (_isSalary = true){
            salariedEmployees.push(_employeeAddress);
        } else {
            hourlyEmployees.push(_employeeAddress);
        }

    }

    ///@dev if employee _isSalary = true then _payRate is their annual salary. 
    ///@dev if employee _isSalary = false then _payRate is their hourly rate.
    function setEmployeeSalary(address _employeeAddress, bool _isSalary, uint256 _payRate) external onlyOwner {
        //"Invalid address"
        if (_employeeAddress == address(0)) {
            revert InvalidAddress();
        }
        //"Employee does not exist"
        if (employees[_employeeAddress].employeeId == 0) {
            revert EmployeeDoesNotExists();
        }

        employees[_employeeAddress].isSalary = _isSalary;
        employees[_employeeAddress].payRate = _payRate;
    }

    function removeEmployee(address _employeeAddress) external onlyOwner {
        // might not be necessary
        if (employees[_employeeAddress].employeeId != 0) {
            revert EmployeeDoesNotExists();
        }
        //@todo do I need to update the mapping or address to employee struct too?
        delete employees[_employeeAddress];
    }

    //function updateEmployee(address _employee) external onlyOwner {}

    //////////////////////////////////////////////////////////
    /// Employee & Owner Only Emloyee Management Functions ///
    //////////////////////////////////////////////////////////

    function changePrimaryWalletAddress(address _oldAddress, address _newAddress) public onlyEmployeeOrOwner {
        Employee storage employee = employees[_oldAddress];

        //"Invalid address"
        if (_newAddress == address(0)) {
            revert InvalidAddress();
        }
        //"Employee does not exist"
        if (employees[_oldAddress].employeeId == 0) {
            revert EmployeeDoesNotExists();
        }
        //@todo might need to update the mapping as well or use the employeeId for the mapping key
        employee.primaryWallet = _newAddress;   
    }

    //@todo does _paySplit need to be callData?
    function setPaymentSplits(address _employeeAddress, uint8[5] memory _paySplitPercentages) public onlyEmployeeOrOwner {
        //require(_paymentSplits.length <= 8, "Exceeds maximum split count");
        uint8 totalPercentage = 0;
        // if (_paymentSplits.paySplitPercentage1 + _paymentSplits.paySplitPercentage2 + _paymentSplits.paySplitPercentage3 + _paymentSplits.paySplitPercentage4 + _paymentSplits.paySplitPercentage5 + _paymentSplits.paySplitPercentage6 != 100) {
        //     revert PercentageMustEqual100();
        // }
        for (uint i = 0; i < _paySplitPercentages.length; ++i) {
            totalPercentage += _paySplitPercentages[i];
        }

        if (totalPercentage != 100) {revert PercentageMustEqual100();}

         PaymentSplit memory newSplit = PaymentSplit({
            //@todo get the chainIds out of this struct
            paySplitPercentageEth: _paySplitPercentages[0],
            paySplitPercentageOp: _paySplitPercentages[1],
            //paySplitPercentageAvax: _paySplitPercentages[2],
            //paySplitPercentageArb: _paySplitPercentages[2],
            paySplitPercentagePolygon: _paySplitPercentages[2],
            paySplitPercentageBnb: _paySplitPercentages[3],
            paySplitPercentageBase: _paySplitPercentages[4]
        });
        // can this be memory or callData?
        Employee storage employee = employees[_employeeAddress];
        employee.paymentSplits = newSplit;
        employee.localChainPayment = false;
    }
    

    ///////////////////////////////////
    /// VIEW & GETTER FUNCS
    //////////////////////////////////
    function _calculateWeeklyPaymentSalary(address _employeeAddress) internal view returns (uint256 weeklyPay) {
        //@todo do I need to check if the employee is valid & exists
        //"Invalid address"
        // if (_employeeAddress == address(0)) {
        //     revert InvalidAddress();
        // }
        // //"Employee does not exist"
        // if (employees[_employeeAddress].employeeId == 0) {
        //     revert EmployeeDoesNotExists();
        // }

        weeklyPay = employees[_employeeAddress].payRate / 52;

        // if (employees[_employeeAddress].isSalary == true) {
        //     // call the salary payment function
        //     weeklyPayRate = employees[_employeeAddress].payRate / 52;
        // } else {
        //     // call the hourly payment function
        //     revert EmployeeIsNotSalary();
        // }

    }

    function _calculateWeeklyPaymentHourly(address _employeeAddress, uint8 _hoursWorked) internal view returns (uint256 weeklyPay) {
        //@todo do I need to check if the employee is valid & exists
        //"Invalid address"
        // if (_employeeAddress == address(0)) {
        //     revert InvalidAddress();
        // }
        // //"Employee does not exist"
        // if (employees[_employeeAddress].employeeId == 0) {
        //     revert EmployeeDoesNotExists();
        // }
        
        weeklyPay = employees[_employeeAddress].payRate * _hoursWorked;

        // if (employees[_employeeAddress].isSalary == false) {
        //     // call the hourly payment function
        //     weeklyPay = employees[_employeeAddress].payRate * _hoursWorked;
        // } else {
        //     // call the salary payment function
        //     revert EmployeeIsNotHourly();
        // }
    }

    function viewPaymentSplit(address _employeeAddress) public view returns (PaymentSplit memory){
       return employees[_employeeAddress].paymentSplits;
    }

}
