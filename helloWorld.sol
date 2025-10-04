// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

contract UserVaultSystem {
    struct User {
        string username;
        uint256 balance; // wei
        bytes32 password; // hash
        bool exists;
        bool frozen; // 是否被冻结
        bool isLoggedIn; 
    }

    address public owner;
    uint256 public sessionTimeout = 60*60*100; //秒

    mapping(address => User) public users;
    mapping(address => uint256) public lastActivity; // 单独存储最后活动时间

    event UserRegistered(address indexed userAddress, string username);
    event Deposited(address indexed userAddress, uint256 amount);
    event Withdrawn(address indexed userAddress, uint256 amount);
    event LoggedIn(address indexed userAddress);
    event LoggedOut(address indexed userAddress);
    event Transferred(address indexed from, address indexed to, uint256 amount);
    event UserFrozen(address indexed userAddress);
    event UserUnfrozen(address indexed userAddress);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyRegisteredUser() {
        require(users[msg.sender].exists, "User not registered");
        _;
    }

    modifier onlyLoggedIn() {
        require(users[msg.sender].isLoggedIn, "User not logged in");
        require(!isSessionExpired(msg.sender), "Session expired, please log in again");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function registerUser(string calldata username, string calldata password) external {
        require(!users[msg.sender].exists, "User already registered");
        require(bytes(username).length > 0, "Username cannot be empty");
        require(bytes(password).length > 0, "Password cannot be empty");

        users[msg.sender] = User({
            username: username,
            balance: 0,
            password: keccak256(abi.encodePacked(password)),
            exists: true,
            frozen: false,
            isLoggedIn: false
        });

        lastActivity[msg.sender] = 0; // 初始化最后活动时间

        emit UserRegistered(msg.sender, username);
    }

    function login(string calldata password) external onlyRegisteredUser {
        require(users[msg.sender].password == keccak256(abi.encodePacked(password)), "Incorrect password");

        users[msg.sender].isLoggedIn = true;
        lastActivity[msg.sender] = block.timestamp;
        emit LoggedIn(msg.sender);
    }

    function logout() public onlyRegisteredUser {
        require(users[msg.sender].isLoggedIn, "User not logged in");
        users[msg.sender].isLoggedIn = false;
        emit LoggedOut(msg.sender);
    }

    function checkLoginStatus() external view returns (bool) {
        return users[msg.sender].isLoggedIn && !isSessionExpired(msg.sender);
    }

    function isSessionExpired(address userAddress) public view returns (bool) {
        require(users[userAddress].exists, "User not registered");
        if (!users[userAddress].isLoggedIn) {
            return true;
        }
        return (block.timestamp - lastActivity[userAddress]) > sessionTimeout;
    }

    function updateLastActivity() internal {
        lastActivity[msg.sender] = block.timestamp;
    }

    function verifyPassword(string calldata password) external view onlyRegisteredUser returns (bool) {
        return users[msg.sender].password == keccak256(abi.encodePacked(password));
    }

    function changePassword(string calldata oldPassword, string calldata newPassword) external onlyRegisteredUser onlyLoggedIn {
        require(users[msg.sender].password == keccak256(abi.encodePacked(oldPassword)), "Old password incorrect");
        require(bytes(newPassword).length > 0, "New password cannot be empty");

        users[msg.sender].password = keccak256(abi.encodePacked(newPassword));
        updateLastActivity();
    }

    function deposit() external payable onlyRegisteredUser onlyLoggedIn {
        require(msg.value > 0, "Deposit amount must be greater than 0");

        users[msg.sender].balance += msg.value;
        updateLastActivity();

        emit Deposited(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external onlyRegisteredUser onlyLoggedIn {
        require(!users[msg.sender].frozen, "User account is frozen");
        require(amount > 0, "Withdrawal amount must be greater than 0");
        require(users[msg.sender].balance >= amount, "Insufficient balance");
        require(address(this).balance >= amount, "Vault has insufficient funds");

        users[msg.sender].balance -= amount;
        updateLastActivity();

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");

        emit Withdrawn(msg.sender, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external {
        require(users[from].exists, "Sender not registered");
        require(users[to].exists, "Recipient not registered");
        require(amount > 0, "Transfer amount must be greater than 0");
        require(users[from].balance >= amount, "Insufficient balance for transfer");
        require(!users[from].frozen, "Sender account is frozen");
        require(msg.sender == owner, "Not authorized");

        users[from].balance -= amount;
        users[to].balance += amount;

        emit Transferred(from, to, amount);
    }

    function freezeUser(address userAddress) external onlyOwner {
        require(users[userAddress].exists, "User not registered");
        require(!users[userAddress].frozen, "User already frozen");

        users[userAddress].frozen = true;
        emit UserFrozen(userAddress);
    }

    function unfreezeUser(address userAddress) external onlyOwner {
        require(users[userAddress].exists, "User not registered");
        require(users[userAddress].frozen, "User is not frozen");

        users[userAddress].frozen = false;
        emit UserUnfrozen(userAddress);
    }

    function isBalanceGreaterThan(address userAddress, uint256 amount) external view returns (bool) {
        require(users[userAddress].exists, "User is not registered");
        return users[userAddress].balance > amount;
    }

    function getUserInfo() external view onlyRegisteredUser onlyLoggedIn returns (
        string memory username,
        uint256 balance,
        bool frozen
    ) {
        User storage user = users[msg.sender];
        return (user.username, user.balance, user.frozen);
    }

    function getVaultBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function isAdmin(address account) external view returns (bool) {
        return account == owner;
    }
}