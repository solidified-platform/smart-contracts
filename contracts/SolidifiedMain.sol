pragma solidity ^0.5.0;

import "./Deployer.sol";
import "./Controlled.sol";
import "./Stoppable.sol";
import "./SolidifiedDepositableFactoryI.sol";
import "./SolidifiedVault.sol";

contract SolidifiedMain is Controlled, Deployer, Stoppable {

  using SafeMath for uint;

  // VARIABLES
  address public depositableFactoryAddress;
  address payable public vault;

  mapping(address => UserStruct) public userStructs;
  mapping(address => address) public depositAddresses; //maps user address to depositAddress

  struct UserStruct {
    uint balance;
    uint pointer;
  }
  address[] public userList;

  //EVENTS
  event LogUserDeposit(address user, address depositAddress, uint amount);
  event LogUserCreditCollected(address user, uint amount, bytes32 ref);
  event LogUserCreditDeposit(address user, uint amount, bytes32 ref);
  event LogDepositableDeployed(address user, address depositableAddress, uint id);
  event LogRequestWithdraw(address user, uint amount);
  event LogUserInserted(address user, uint userId);
  event LogVaultAddressChanged(address newAddress, address sender);
  event LogDepositableFactoryAddressChanged(address newAddress, address sender);

  // CONSTRUCTOR
  /**
  @dev Constructor function
  @param controller address Address of the controller
  @param _depositableFactoryAddress address Address of the depositable factoryAddress
  @param _vault address Address of the vault
  **/
  constructor(address controller,
      address _depositableFactoryAddress,
      address payable _vault)
      public
    Controlled(controller) {
      vault = _vault;
      depositableFactoryAddress = _depositableFactoryAddress;
    }

  //PUBLIC FUNCTIONS

  /**
  @dev Allows the contract to receive an deposit for specif user
  @param _userAddress address Address of the user to be deposited
  **/
  function receiveDeposit(address _userAddress)
    payable
    public
    onlyDeployed
    onlyIfRunning
  {
    require(msg.sender == depositAddresses[_userAddress], "Main:sender should be deposit address");
    userStructs[_userAddress].balance = userStructs[_userAddress].balance.add(msg.value);

    vault.transfer(msg.value);
    emit LogUserDeposit(_userAddress, msg.sender, msg.value);
  }

  /**
  @dev Allows the controller to collect/lock user funds
  @param _userAddress address Adress of the user to collect credit from
  @param amount uint256 Amount to be collected
  @param ref bytes32 Referece for the reason for collection
  **/
  function collectUserCredit(address _userAddress, uint256 amount, bytes32 ref)
    public
    onlyController
    onlyIfRunning
  {
      require(userStructs[_userAddress].balance >= amount, "Main:user does not have enough balance");
      userStructs[_userAddress].balance = userStructs[_userAddress].balance.sub(amount);
      emit LogUserCreditCollected(_userAddress, amount, ref);
  }

  /**
  @dev Allows controller to deposit funds for user
  @param _userAddress address Adress of the user to collect credit from
  @param amount uint256 Amount to be collected
  @param ref bytes32 Referece for the reason for collection
  **/
  function depositUserCredit(address _userAddress, uint256 amount, bytes32 ref)
    public
    onlyController
    onlyIfRunning
  {
      userStructs[_userAddress].balance = userStructs[_userAddress].balance.add(amount);
      emit LogUserCreditDeposit(_userAddress, amount, ref);
  }

  /**
  @dev Deploys a new depositable contract, which users can send ether to.
  @param _userAddress address Address of the user that will be credited the money
  @return An address of the new depositable address
  **/
  function deployDepositableContract(address _userAddress)
    public
    onlyController
    onlyIfRunning
    returns(address depositable)
  {
      if(!isUser(_userAddress)) require(insertNewUser(_userAddress), "Main:inserting user has failed");
      require(depositAddresses[_userAddress] == address(0), "Main:invalid address");
      SolidifiedDepositableFactoryI f = SolidifiedDepositableFactoryI(depositableFactoryAddress);
      address d = f.deployDepositableContract(_userAddress, address(this));

      require(insertDeployedContract(d), "Main:insert contract failed");
      require(registerDepositAddress(_userAddress, d), "Main:contract registration failed");

      emit LogDepositableDeployed(_userAddress, d,getDeployedContractsCount());

      return d;
  }

  /**
  @dev Request a eth withdraw in the vault for specif user
  @param _userAddress address Adress of the user to withdraw
  @param amount uint256 Amount to be withdrawn
  **/
  function requestWithdraw(address _userAddress, uint amount)
    public
    onlyController
    onlyIfRunning
  {
    require(userStructs[_userAddress].balance >= amount,"Main:user does not have enough balance");
    userStructs[_userAddress].balance = userStructs[_userAddress].balance.sub(amount);
    (bool success, bytes memory _) = vault.call(abi.encodeWithSignature("submitTransaction(address,uint256)",_userAddress,amount));
    require(success, "Main:low level call failed");

    emit LogRequestWithdraw(_userAddress, amount);
  }

  /**
  @dev Register a deposit address for a specif user, so all Eth deposited in that
  address will be credited only to the user.
  @param _userAddress address Address of the user
  @param _depositAddress address Address of the depositable contract
  **/
  function registerDepositAddress(address _userAddress, address _depositAddress)
    public
    onlyController
    onlyIfRunning
    returns(bool success)
  {
    depositAddresses[_userAddress] = _depositAddress;
    return true;
  }

  /**
  @dev Allows to disconnect an user address from a deposit address
  @param _userAddress address Address of the user
  **/
  function deregisterUserDepositAddress(address _userAddress)
    public
    onlyController
    onlyIfRunning
  {
    depositAddresses[_userAddress] = address(0);
  }

  /**
  @dev Allows to register a new user into the system
  @param user address Address of the user
  **/
  function insertNewUser(address user)
    public
    onlyController
    onlyIfRunning
    returns(bool success)
  {
    require(!isUser(user), "Main:address is already user");
    userStructs[user].pointer = userList.push(user).sub(uint(1));
    emit LogUserInserted(user, userStructs[user].pointer);
    return true;
  }

  /**
  @dev Change the vault address
  @param _newVault address Address of the new vault
  **/
  function changeVaultAddress(address payable _newVault)
    public
    onlyOwner
    onlyIfRunning
  {
    require(_newVault != address(0),"Main:invalid address");
    vault = _newVault;
    emit LogVaultAddressChanged(_newVault, msg.sender);
  }

  /**
  @dev Change depositable factory address
  @param _newAddress address Address of the new depositable factory
  **/
  function changeDespositableFactoryAddress(address _newAddress)
    public
    onlyController
    onlyIfRunning
  {
    require(_newAddress != address(0),"Main:invalid address");
    depositableFactoryAddress = _newAddress;

    emit LogDepositableFactoryAddressChanged(_newAddress, msg.sender);
  }

  /**
  @dev Check if an address is a registered user
  @param user address Address of the user
  @return true if address is user
  **/
  function isUser(address user) public view returns(bool isIndeed) {
      if(userList.length ==0) return false;
      return(userList[userStructs[user].pointer] == user);
  }

  /**
  @dev Checks the depositable Factory address of a specif user
  @return The depositable factory address
  **/
  function getDepositableFactoryAddress()
    public
    view
    returns(address factoryAddress)
  {
    return depositableFactoryAddress;
  }

  /**
  @dev Getter for the vault address
  @return The address of the vault
  **/
  function getVaultAddress()
    public
    view
    returns(address vaultAddress)
  {
    return vault;
  }

  /**
  @dev Checks the depositable Factory address of a specif user
  @param _userAddress address Address of the user
  @return The depositable address of the user.
  **/
  function getDepositAddressForUser(address _userAddress)
    public
    view
    returns(address depositAddress)
  {
    return depositAddresses[_userAddress];
  }

  /**
  @dev Checks the balance of specif user
  @param _userAddress address Address of the user
  @return uint representing the balance
  **/
  function getUserBalance(address _userAddress)
    public
    view
    returns(uint256 balance)
  {
    return userStructs[_userAddress].balance;
  }

}
