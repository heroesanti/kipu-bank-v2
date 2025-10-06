// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract KipuBankV2 is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // Token constants (USDC decimals for internal accounting)
    uint8 private constant USDC_DECIMALS = 6;
    uint256 private constant DECIMALS_MULTIPLIER = 10**USDC_DECIMALS;

    // Bank configuration
    uint256 public immutable bankCap; // Global deposit limit in USD (6 decimals)
    uint256 public totalDeposits; // Total deposits in USD (6 decimals)

    // Chainlink ETH/USD Price Feed
    AggregatorV3Interface internal ethUsdPriceFeed;

    // Token management
    struct TokenConfig {
        address tokenAddress;
        uint8 decimals;
        bool isNativeETH;
        AggregatorV3Interface tokenEthPriceFeed; // For non-ETH tokens
    }

    TokenConfig[] public supportedTokens;
    mapping(address => bool) private _supportedTokens;

    // User accounts
    struct UserBalance {
        uint256 amount; // In token's native decimals
        uint256 lastDepositTimestamp;
    }

    struct Account {
        mapping(address => UserBalance) tokenBalances;
        bool exists;
        uint256 depositCount;
        uint256 withdrawalCount;
    }

    mapping(address => Account) public accounts;

    // Configuration parameters
    uint256 public minimumDeposit = 100 * 10**18; // Default for ETH (18 decimals)
    uint256 public withdrawalFee = 5; // 5% fee
    uint256 public lockPeriod = 1 days;
    uint256 private constant MAX_WITHDRAWAL_PER_TRANSACTION = 200 * 10**18; // Default for ETH

    // Counters
    uint256 public totalDepositsCount;
    uint256 public totalWithdrawalsCount;

    // Errors
    error KipuBank__AccountAlreadyExists();
    error KipuBank__AccountDoesNotExist();
    error KipuBank__InsufficientBalance();
    error KipuBank__AmountBelowMinimumDeposit();
    error KipuBank__DepositExceedsBankCapacity();
    error KipuBank__FundsLocked(uint256 unlockTime);
    error KipuBank__WithdrawalLimitExceeded();
    error KipuBank__TokenNotSupported();
    error KipuBank__InvalidPrice();
    error KipuBank__ZeroAddress();
    error KipuBank__Unauthorized();
    error KipuBank__TransferFailed();

    // Events
    event AccountCreated(address indexed owner);
    event Deposited(
        address indexed owner,
        address indexed token,
        uint256 amount,
        uint256 userDepositCount,
        uint256 totalDepositsCount
    );
    event Withdrawn(
        address indexed owner,
        address indexed token,
        uint256 amount,
        uint256 fee,
        uint256 userWithdrawalCount,
        uint256 totalWithdrawalsCount
    );
    event TokenSupported(address indexed token, uint8 decimals, bool isNativeETH);
    event TokenUnsupported(address indexed token);
    event MinimumDepositUpdated(uint256 newMinimumDeposit);
    event WithdrawalFeeUpdated(uint256 newWithdrawalFee);
    event LockPeriodUpdated(uint256 newLockPeriod);
    event BankCapSet(uint256 cap);
    event PriceFeedUpdated(address indexed token, address newPriceFeed);
    event RoleGranted(bytes32 indexed role, address indexed account);
    event RoleRevoked(bytes32 indexed role, address indexed account);
    event EmergencyWithdrawal(address indexed owner, address indexed token, uint256 amount);

    constructor(
        uint256 _bankCap,
        address _priceFeedAddress
    ) {
        require(_priceFeedAddress != address(0), "Price feed cannot be zero");

        // Setup roles
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        bankCap = _bankCap;
        ethUsdPriceFeed = AggregatorV3Interface(_priceFeedAddress);

        emit BankCapSet(_bankCap);
        emit PriceFeedUpdated(address(0), _priceFeedAddress); // address(0) for ETH
        emit RoleGranted(ADMIN_ROLE, msg.sender);
        emit RoleGranted(OPERATOR_ROLE, msg.sender);
    }

    // ========== Access Control ==========
    function grantRole(bytes32 role, address account) public override onlyRole(ADMIN_ROLE) {
        _grantRole(role, account);
        emit RoleGranted(role, account);
    }

    function revokeRole(bytes32 role, address account) public override onlyRole(ADMIN_ROLE) {
        _revokeRole(role, account);
        emit RoleRevoked(role, account);
    }

    // ========== Account Management ==========
    function createAccount() external {
        if (accounts[msg.sender].exists) {
            revert KipuBank__AccountAlreadyExists();
        }
        // Initialize the account structure without trying to assign the mapping directly
        accounts[msg.sender].exists = true;
        accounts[msg.sender].depositCount = 0;
        accounts[msg.sender].withdrawalCount = 0;
        emit AccountCreated(msg.sender);
    }

    // ========== Token Management ==========
    function addSupportedToken(
        address tokenAddress,
        uint8 tokenDecimals,
        bool isNativeETH,
        address priceFeedAddress
    ) external onlyRole(ADMIN_ROLE) {
        if (tokenAddress == address(0)) {
            revert KipuBank__ZeroAddress();
        }
        if (_supportedTokens[tokenAddress]) {
            return; // Already supported
        }

        TokenConfig memory newToken = TokenConfig({
            tokenAddress: tokenAddress,
            decimals: tokenDecimals,
            isNativeETH: isNativeETH,
            tokenEthPriceFeed: priceFeedAddress != address(0)
                ? AggregatorV3Interface(priceFeedAddress)
                : AggregatorV3Interface(address(0))
        });

        supportedTokens.push(newToken);
        _supportedTokens[tokenAddress] = true;

        emit TokenSupported(tokenAddress, tokenDecimals, isNativeETH);
        if (priceFeedAddress != address(0)) {
            emit PriceFeedUpdated(tokenAddress, priceFeedAddress);
        }
    }

    function removeSupportedToken(address tokenAddress) external onlyRole(ADMIN_ROLE) {
        if (!isTokenSupported(tokenAddress)) {
            return;
        }

        _supportedTokens[tokenAddress] = false;
        emit TokenUnsupported(tokenAddress);
    }

    function isTokenSupported(address tokenAddress) public view returns (bool) {
        return _supportedTokens[tokenAddress] || tokenAddress == address(0);
    }

    function getTokenConfig(address tokenAddress) external view returns (TokenConfig memory) {
        if (!isTokenSupported(tokenAddress)) {
            revert KipuBank__TokenNotSupported();
        }

        if (tokenAddress == address(0)) {
            // Return ETH config
            return TokenConfig({
                tokenAddress: address(0),
                decimals: 18,
                isNativeETH: true,
                tokenEthPriceFeed: ethUsdPriceFeed
            });
        }

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i].tokenAddress == tokenAddress) {
                return supportedTokens[i];
            }
        }

        revert KipuBank__TokenNotSupported();
    }

    // ========== Core Banking Functions ==========
    function deposit(address tokenAddress, uint256 amount) public payable nonReentrant {
        if (!accounts[msg.sender].exists) {
            revert KipuBank__AccountDoesNotExist();
        }

        TokenConfig memory tokenConfig = this.getTokenConfig(tokenAddress);
        uint256 tokenDecimals = tokenConfig.decimals;

        // Check minimum deposit (converted to token's native decimals)
        uint256 minDepositInToken = (minimumDeposit * 10**tokenDecimals) / DECIMALS_MULTIPLIER;
        if (amount < minDepositInToken) {
            revert KipuBank__AmountBelowMinimumDeposit();
        }

        // Check bank capacity
        uint256 amountInUsd = _getTokenAmountInUsd(tokenAddress, amount);
        uint256 totalDepositsInUsd = totalDeposits;

        if (totalDepositsInUsd + amountInUsd > bankCap) {
            revert KipuBank__DepositExceedsBankCapacity();
        }

        // Transfer tokens (or ETH)
        if (tokenAddress == address(0)) {
            if (msg.value != amount) {
                revert KipuBank__TransferFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Update balances
        accounts[msg.sender].tokenBalances[tokenAddress].amount += amount;
        accounts[msg.sender].tokenBalances[tokenAddress].lastDepositTimestamp = block.timestamp;
        accounts[msg.sender].depositCount++;
        totalDeposits += amountInUsd;
        totalDepositsCount++;

        emit Deposited(msg.sender, tokenAddress, amount, accounts[msg.sender].depositCount, totalDepositsCount);
    }

    function withdraw(address tokenAddress, uint256 amount) external nonReentrant {
        Account storage account = accounts[msg.sender];
        if (!account.exists) {
            revert KipuBank__AccountDoesNotExist();
        }

        // TokenConfig memory tokenConfig = this.getTokenConfig(tokenAddress);
        UserBalance storage userBalance = account.tokenBalances[tokenAddress];

        if (userBalance.amount < amount) {
            revert KipuBank__InsufficientBalance();
        }

        // Check lock period
        if (block.timestamp < userBalance.lastDepositTimestamp + lockPeriod) {
            revert KipuBank__FundsLocked(userBalance.lastDepositTimestamp + lockPeriod);
        }

        // Check withdrawal limit
        if (amount > MAX_WITHDRAWAL_PER_TRANSACTION) {
            revert KipuBank__WithdrawalLimitExceeded();
        }

        // Calculate fee (in token's native decimals)
        uint256 feeAmount = (amount * withdrawalFee) / 100;
        uint256 amountAfterFee = amount - feeAmount;

        // Update balances
        userBalance.amount -= amount;
        account.withdrawalCount++;
        totalDeposits -= _getTokenAmountInUsd(tokenAddress, amount);
        totalWithdrawalsCount++;

        // Transfer tokens (or ETH)
        if (tokenAddress == address(0)) {
            (bool success, ) = msg.sender.call{value: amountAfterFee}("");
            if (!success) {
                revert KipuBank__TransferFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransfer(msg.sender, amountAfterFee);
        }

        emit Withdrawn(msg.sender, tokenAddress, amount, feeAmount, account.withdrawalCount, totalWithdrawalsCount);
    }

    // Emergency withdrawal (no fees, no lock period)
    function emergencyWithdraw(address tokenAddress) external nonReentrant {
        if (!hasRole(EMERGENCY_ROLE, msg.sender) && !accounts[msg.sender].exists) {
            revert KipuBank__AccountDoesNotExist();
        }

        Account storage account = accounts[msg.sender];
        UserBalance storage userBalance = account.tokenBalances[tokenAddress];
        uint256 amount = userBalance.amount;

        if (amount == 0) {
            return;
        }

        // Update balances
        userBalance.amount = 0;
        account.withdrawalCount++;
        totalDeposits -= _getTokenAmountInUsd(tokenAddress, amount);

        // Transfer tokens (or ETH)
        if (tokenAddress == address(0)) {
            (bool success, ) = msg.sender.call{value: amount}("");
            if (!success) {
                revert KipuBank__TransferFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransfer(msg.sender, amount);
        }

        emit EmergencyWithdrawal(msg.sender, tokenAddress, amount);
    }

    // ========== View Functions ==========
    function getUserBalance(address user, address tokenAddress) external view returns (uint256) {
        if (!accounts[user].exists) {
            revert KipuBank__AccountDoesNotExist();
        }
        return accounts[user].tokenBalances[tokenAddress].amount;
    }

    function getUserBalanceInUsd(address user, address tokenAddress) external view returns (uint256) {
        return _getTokenAmountInUsd(tokenAddress, this.getUserBalance(user, tokenAddress));
    }

    function getTotalDepositsInUsd() external view returns (uint256) {
        return totalDeposits;
    }

    function getUserDepositCount(address user) external view returns (uint256) {
        if (!accounts[user].exists) {
            revert KipuBank__AccountDoesNotExist();
        }
        return accounts[user].depositCount;
    }

    function getUserWithdrawalCount(address user) external view returns (uint256) {
        if (!accounts[user].exists) {
            revert KipuBank__AccountDoesNotExist();
        }
        return accounts[user].withdrawalCount;
    }

    function getLatestEthPrice() public view returns (uint256) {
        (, int256 price, , , ) = ethUsdPriceFeed.latestRoundData();
        if (price <= 0) {
            revert KipuBank__InvalidPrice();
        }
        return uint256(price);
    }

    function getTokenPriceInEth(address tokenAddress) public view returns (uint256) {
        if (tokenAddress == address(0)) {
            return 10**18; // 1 ETH = 1 ETH
        }

        TokenConfig memory tokenConfig = this.getTokenConfig(tokenAddress);
        if (address(tokenConfig.tokenEthPriceFeed) == address(0)) {
            revert KipuBank__InvalidPrice();
        }

        (, int256 price, , , ) = tokenConfig.tokenEthPriceFeed.latestRoundData();
        if (price <= 0) {
            revert KipuBank__InvalidPrice();
        }

        return uint256(price);
    }

    // ========== Admin Functions ==========
    function setMinimumDeposit(uint256 _minimumDeposit) external onlyRole(ADMIN_ROLE) {
        minimumDeposit = _minimumDeposit;
        emit MinimumDepositUpdated(_minimumDeposit);
    }

    function setWithdrawalFee(uint256 _withdrawalFee) external onlyRole(ADMIN_ROLE) {
        require(_withdrawalFee <= 10, "Fee cannot exceed 10%");
        withdrawalFee = _withdrawalFee;
        emit WithdrawalFeeUpdated(_withdrawalFee);
    }

    function setLockPeriod(uint256 _lockPeriod) external onlyRole(ADMIN_ROLE) {
        lockPeriod = _lockPeriod;
        emit LockPeriodUpdated(_lockPeriod);
    }

    function setPriceFeed(address tokenAddress, address _priceFeedAddress) external onlyRole(ADMIN_ROLE) {
        if (_priceFeedAddress == address(0)) {
            revert KipuBank__ZeroAddress();
        }

        if (tokenAddress == address(0)) {
            ethUsdPriceFeed = AggregatorV3Interface(_priceFeedAddress);
        } else {
            for (uint256 i = 0; i < supportedTokens.length; i++) {
                if (supportedTokens[i].tokenAddress == tokenAddress) {
                    supportedTokens[i].tokenEthPriceFeed = AggregatorV3Interface(_priceFeedAddress);
                    break;
                }
            }
        }

        emit PriceFeedUpdated(tokenAddress, _priceFeedAddress);
    }

    function withdrawFees(address tokenAddress) external nonReentrant onlyRole(ADMIN_ROLE) {
        // TokenConfig memory tokenConfig = this.getTokenConfig(tokenAddress);
        uint256 contractBalance;

        if (tokenAddress == address(0)) {
            contractBalance = address(this).balance;
        } else {
            contractBalance = IERC20(tokenAddress).balanceOf(address(this));
        }

        // Calculate total user balances for this token
        uint256 totalUserBalances;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i].tokenAddress == tokenAddress) {
                // In a real implementation, you'd need to track all user balances
                // This is simplified for the example
                // Consider using EnumerableSet for efficient iteration in production
                break;
            }
        }

        uint256 fees = contractBalance > totalUserBalances ? contractBalance - totalUserBalances : 0;
        if (fees == 0) {
            return;
        }

        if (tokenAddress == address(0)) {
            (bool success, ) = msg.sender.call{value: fees}("");
            if (!success) {
                revert KipuBank__TransferFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransfer(msg.sender, fees);
        }
    }

    // ========== Internal Functions ==========
    function _getTokenAmountInUsd(address tokenAddress, uint256 tokenAmount) internal view returns (uint256) {
        if (tokenAmount == 0) return 0;

        if (tokenAddress == address(0)) {
            // ETH to USD conversion
            uint256 ethPrice = getLatestEthPrice();
            // ethPrice is in USD with 8 decimals (from Chainlink)
            // tokenAmount is in wei (18 decimals)
            // Convert to USD with 6 decimals (USDC standard)
            return (tokenAmount * ethPrice) / (10**(18 + 8 - USDC_DECIMALS));
        } else {
            // ERC20 token to USD conversion
            TokenConfig memory tokenConfig = this.getTokenConfig(tokenAddress);
            uint256 tokenEthPrice = getTokenPriceInEth(tokenAddress);
            uint256 ethPrice = getLatestEthPrice();

            // tokenAmount is in token's native decimals
            // tokenEthPrice is token/ETH price with 18 decimals (Chainlink standard)
            // ethPrice is ETH/USD price with 8 decimals (Chainlink standard)
            // Result should be in USD with 6 decimals (USDC standard)

            // First convert token to ETH (tokenAmount * tokenEthPrice / 10^tokenDecimals)
            uint256 amountInEth = (tokenAmount * tokenEthPrice) / (10**tokenConfig.decimals);

            // Then convert ETH to USD (amountInEth * ethPrice / 10^18)
            uint256 amountInUsd = (amountInEth * ethPrice) / 10**18;

            // Convert from 8 decimals (Chainlink) to 6 decimals (USDC)
            return amountInUsd * 10**(USDC_DECIMALS - 8);
        }
    }

    // ========== Fallback for ETH deposits ==========
    receive() external payable {
        this.deposit(address(0), msg.value);
    }
}