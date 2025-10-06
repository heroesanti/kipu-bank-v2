// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {KipuBankV2} from "../src/KipuBankV2.sol";
import {MockToken} from "../src/MockToken.sol";
import {AggregatorV3Interface} from "@chainlink/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract KipuBankV2Test is Test {
    // Direcciones constantes para pruebas
    address public constant DEPLOYER = address(1);
    address public constant USER1 = address(2);
    address public constant USER2 = address(3);
    address public constant ADMIN = address(4);

    // Contratos
    KipuBankV2 public kipuBank;
    MockToken public mockToken;
    MockToken public mockToken2;
    MockAggregator public ethUsdPriceFeed;
    MockAggregator public tokenEthPriceFeed;

    // Valores de configuración
    uint256 public constant BANK_CAP = 1_000_000 * 1e6; // 1M USD (6 decimales)
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant ETH_PRICE = 2000 * 1e8; // 2000 USD/ETH (8 decimales)
    uint256 public constant TOKEN_ETH_PRICE = 0.01 * 1e18; // 0.01 ETH/token (18 decimales)

    // Configuración de Foundry
    function setUp() public {
        // Configurar VM para pruebas
        vm.startPrank(DEPLOYER);

        // Desplegar MockAggregator para ETH/USD
        ethUsdPriceFeed = new MockAggregator(ETH_PRICE, 8);

        // Desplegar MockAggregator para Token/ETH
        tokenEthPriceFeed = new MockAggregator(TOKEN_ETH_PRICE, 18);

        // Desplegar MockToken (18 decimales)
        mockToken = new MockToken(DEPLOYER);
        mockToken.mint(DEPLOYER, INITIAL_SUPPLY);
        mockToken.mint(USER1, INITIAL_SUPPLY);
        mockToken.mint(USER2, INITIAL_SUPPLY);

        // Desplegar segundo MockToken (6 decimales)
        mockToken2 = new MockToken(DEPLOYER);
        vm.stopPrank();
        vm.startPrank(DEPLOYER);
        mockToken2 = new MockToken(DEPLOYER);
        vm.stopPrank();
        vm.prank(DEPLOYER);
        mockToken2.mint(DEPLOYER, 1_000_000 * 1e6);
        mockToken2.mint(USER1, 1_000_000 * 1e6);
        mockToken2.mint(USER2, 1_000_000 * 1e6);

        // Desplegar KipuBankV2
        vm.startPrank(DEPLOYER);
        kipuBank = new KipuBankV2(
            BANK_CAP,
            address(ethUsdPriceFeed)
        );

        // Configurar roles
        kipuBank.grantRole(kipuBank.ADMIN_ROLE(), ADMIN);
        kipuBank.grantRole(kipuBank.OPERATOR_ROLE(), DEPLOYER);

        // Añadir soporte para tokens
        kipuBank.addSupportedToken(
            address(mockToken),
            18,
            false,
            address(tokenEthPriceFeed)
        );

        kipuBank.addSupportedToken(
            address(mockToken2),
            6,
            false,
            address(tokenEthPriceFeed)
        );

        vm.stopPrank();
    }

    // Test para creación de cuentas
    function testCreateAccount() public {
        vm.prank(USER1);
        kipuBank.createAccount();

        assertEq(kipuBank.getUserDepositCount(USER1), 0);
        assertEq(kipuBank.getUserWithdrawalCount(USER1), 0);
    }

    function testCreateAccountTwiceReverts() public {
        vm.prank(USER1);
        kipuBank.createAccount();

        vm.prank(USER1);
        vm.expectRevert(KipuBankV2.KipuBank__AccountAlreadyExists.selector);
        kipuBank.createAccount();
    }

    // Test para depósitos
    function testDeposit() public {
        vm.prank(USER1);
        kipuBank.createAccount();

        // Aprobar transferencia
        vm.prank(USER1);
        mockToken.approve(address(kipuBank), 100 * 1e18);

        // Hacer depósito
        vm.prank(USER1);
        kipuBank.deposit(address(mockToken), 100 * 1e18);

        assertEq(kipuBank.getUserBalance(USER1, address(mockToken)), 100 * 1e18);
        assertEq(kipuBank.getUserDepositCount(USER1), 1);
    }

    function testDepositBelowMinimumReverts() public {
        vm.prank(USER1);
        kipuBank.createAccount();

        // Configurar mínimo de depósito
        vm.prank(ADMIN);
        kipuBank.setMinimumDeposit(50 * 1e6); // 50 USD (6 decimales)

        // Aprobar transferencia
        vm.prank(USER1);
        mockToken2.approve(address(kipuBank), 10 * 1e6); // 10 USD (menos que el mínimo)

        // Intentar depósito (debería fallar)
        vm.prank(USER1);
        vm.expectRevert(KipuBankV2.KipuBank__AmountBelowMinimumDeposit.selector);
        kipuBank.deposit(address(mockToken2), 10 * 1e6);
    }

    function testDepositExceedsBankCapReverts() public {
        vm.prank(USER1);
        kipuBank.createAccount();

        // Configurar bank cap bajo para la prueba
        vm.prank(ADMIN);

        // Aprobar transferencia
        vm.prank(USER1);
        mockToken2.approve(address(kipuBank), 200 * 1e6); // 200 USD (excede el límite)

        // Intentar depósito (debería fallar)
        vm.prank(USER1);
        vm.expectRevert(KipuBankV2.KipuBank__DepositExceedsBankCapacity.selector);
        kipuBank.deposit(address(mockToken2), 200 * 1e6);
    }

    // Test para retiros
    function testWithdraw() public {
        vm.prank(USER1);
        kipuBank.createAccount();

        // Depositar primero
        vm.prank(USER1);
        mockToken.approve(address(kipuBank), 100 * 1e18);
        kipuBank.deposit(address(mockToken), 100 * 1e18);

        // Balance inicial del usuario
        uint256 initialBalance = mockToken.balanceOf(USER1);

        // Hacer retiro
        vm.prank(USER1);
        kipuBank.withdraw(address(mockToken), 50 * 1e18);

        // Verificar balance del usuario (debería aumentar en 50 - fee)
        uint256 expectedAmount = 50 * 1e18 - (50 * 1e18 * 5 / 100); // 5% fee
        assertEq(mockToken.balanceOf(USER1), initialBalance + expectedAmount);
        assertEq(kipuBank.getUserBalance(USER1, address(mockToken)), 50 * 1e18);
        assertEq(kipuBank.getUserWithdrawalCount(USER1), 1);
    }

    function testWithdrawDuringLockPeriodReverts() public {
        vm.prank(USER1);
        kipuBank.createAccount();

        // Depositar primero
        vm.prank(USER1);
        mockToken.approve(address(kipuBank), 100 * 1e18);
        kipuBank.deposit(address(mockToken), 100 * 1e18);

        // Intentar retirar antes de que termine el lock period
        vm.prank(USER1);
        vm.expectRevert(KipuBankV2.KipuBank__FundsLocked.selector);
        kipuBank.withdraw(address(mockToken), 50 * 1e18);
    }

    function testWithdrawExceedsLimitReverts() public {
        vm.prank(USER1);
        kipuBank.createAccount();

        // Depositar primero
        vm.prank(USER1);
        mockToken.approve(address(kipuBank), 300 * 1e18);
        kipuBank.deposit(address(mockToken), 300 * 1e18);

        // Avanzar tiempo para evitar lock period
        vm.warp(block.timestamp + 1 days + 1);

        // Intentar retirar más del límite por transacción
        vm.prank(USER1);
        vm.expectRevert(KipuBankV2.KipuBank__WithdrawalLimitExceeded.selector);
        kipuBank.withdraw(address(mockToken), 250 * 1e18); // Asumiendo MAX_WITHDRAWAL_PER_TRANSACTION = 200 * 1e18
    }

    // Test para manejo de roles
    function testRoleManagement() public {
        // Verificar que ADMIN puede otorgar roles
        vm.prank(ADMIN);
        kipuBank.grantRole(kipuBank.OPERATOR_ROLE(), USER1);

        assertTrue(kipuBank.hasRole(kipuBank.OPERATOR_ROLE(), USER1));

        // Verificar que ADMIN puede revocar roles
        vm.prank(ADMIN);
        kipuBank.revokeRole(kipuBank.OPERATOR_ROLE(), USER1);

        assertFalse(kipuBank.hasRole(kipuBank.OPERATOR_ROLE(), USER1));
    }

    function testUnauthorizedRoleGrantReverts() public {
        // Intentar otorgar rol sin permisos
        vm.prank(USER1);
        vm.expectRevert(KipuBankV2.KipuBank__Unauthorized.selector);
        kipuBank.grantRole(kipuBank.OPERATOR_ROLE(), USER2);
    }

    // Test para soporte multi-token
    function testMultiTokenSupport() public {
        vm.prank(USER1);
        kipuBank.createAccount();

        // Depositar token1
        vm.prank(USER1);
        mockToken.approve(address(kipuBank), 100 * 1e18);
        kipuBank.deposit(address(mockToken), 100 * 1e18);

        // Depositar token2
        vm.prank(USER1);
        mockToken2.approve(address(kipuBank), 200 * 1e6);
        kipuBank.deposit(address(mockToken2), 200 * 1e6);

        // Verificar balances
        assertEq(kipuBank.getUserBalance(USER1, address(mockToken)), 100 * 1e18);
        assertEq(kipuBank.getUserBalance(USER1, address(mockToken2)), 200 * 1e6);

        // Verificar que los saldos están en USD (6 decimales)
        uint256 token1InUsd = kipuBank.getUserBalanceInUsd(USER1, address(mockToken));
        uint256 token2InUsd = kipuBank.getUserBalanceInUsd(USER1, address(mockToken2));

        // Calcular valores esperados manualmente
        // token1: 100 * 0.01 ETH/token * 2000 USD/ETH = 2000 USD
        // token2: 200 * 0.01 ETH/token * 2000 USD/ETH = 4000 USD
        // Total: 6000 USD (6000 * 1e6)
        uint256 expectedTotal = 6000 * 1e6;
        uint256 actualTotal = token1InUsd + token2InUsd;

        // Permitir pequeña diferencia por redondeo
        assertApproxEqAbs(actualTotal, expectedTotal, 1 * 1e6);
    }

    // Test para conversión de decimales
    function testDecimalConversion() public {
        // Depositar token con 6 decimales (mockToken2)
        vm.prank(USER1);
        kipuBank.createAccount();

        vm.prank(USER1);
        mockToken2.approve(address(kipuBank), 100 * 1e6); // 100 tokens (6 decimales)
        kipuBank.deposit(address(mockToken2), 100 * 1e6);

        // Verificar conversión a USD (6 decimales)
        uint256 balanceInUsd = kipuBank.getUserBalanceInUsd(USER1, address(mockToken2));

        // Valor esperado: 100 tokens * 0.01 ETH/token * 2000 USD/ETH = 2000 USD
        // En 6 decimales: 2000 * 1e6 = 2000000000
        assertEq(balanceInUsd, 2000 * 1e6);
    }

    // Test para retiro de emergencia
    function testEmergencyWithdraw() public {
        vm.prank(USER1);
        kipuBank.createAccount();

        // Depositar fondos
        vm.prank(USER1);
        mockToken.approve(address(kipuBank), 100 * 1e18);
        kipuBank.deposit(address(mockToken), 100 * 1e18);

        // Balance inicial del usuario
        uint256 initialBalance = mockToken.balanceOf(USER1);

        // Otorgar rol de emergencia
        vm.prank(ADMIN);
        kipuBank.grantRole(kipuBank.EMERGENCY_ROLE(), USER1);

        // Retiro de emergencia
        vm.prank(USER1);
        kipuBank.emergencyWithdraw(address(mockToken));

        // Verificar que los fondos fueron retirados completamente
        assertEq(kipuBank.getUserBalance(USER1, address(mockToken)), 0);
        assertEq(mockToken.balanceOf(USER1), initialBalance + 100 * 1e18);
    }

    // Test para configuración de parámetros
    function testParameterConfiguration() public {
        // Cambiar mínimo de depósito
        vm.prank(ADMIN);
        kipuBank.setMinimumDeposit(200 * 1e6);

        assertEq(kipuBank.minimumDeposit(), 200 * 1e6);

        // Cambiar fee de retiro
        vm.prank(ADMIN);
        kipuBank.setWithdrawalFee(10);

        assertEq(kipuBank.withdrawalFee(), 10);

        // Cambiar período de bloqueo
        vm.prank(ADMIN);
        kipuBank.setLockPeriod(2 days);

        assertEq(kipuBank.lockPeriod(), 2 days);
    }

    // Test para manejo de ETH nativo
    function testNativeETHSupport() public {
        // Añadir soporte para ETH nativo
        vm.prank(ADMIN);
        kipuBank.addSupportedToken(address(0), 18, true, address(ethUsdPriceFeed));

        vm.prank(USER1);
        kipuBank.createAccount();

        // Depositar ETH
        vm.deal(USER1, 100 ether);
        vm.prank(USER1);
        kipuBank.deposit{value: 5 ether}(address(0), 5 ether);

        // Verificar balance
        assertEq(kipuBank.getUserBalance(USER1, address(0)), 5 ether);

        // Verificar conversión a USD
        uint256 balanceInUsd = kipuBank.getUserBalanceInUsd(USER1, address(0));
        // 5 ETH * 2000 USD/ETH = 10000 USD (10000 * 1e6 en 6 decimales)
        assertEq(balanceInUsd, 10000 * 1e6);

        // Avanzar tiempo para evitar lock period
        vm.warp(block.timestamp + 1 days + 1);

        // Retirar ETH
        uint256 initialBalance = USER1.balance;
        vm.prank(USER1);
        kipuBank.withdraw(address(0), 2 ether);

        // Verificar balance del usuario (2 ETH - 5% fee = 1.9 ETH)
        assertEq(USER1.balance, initialBalance + 1.9 ether);
        assertEq(kipuBank.getUserBalance(USER1, address(0)), 3 ether);
    }

    // Test para manejo de price feeds
    function testPriceFeedUpdates() public {
        vm.prank(ADMIN);

        // Verificar que el nuevo precio se usa
        assertEq(kipuBank.getLatestEthPrice(), 2500 * 1e8);
    }

    // Test para retiro de fees
    function testWithdrawFees() public {
        vm.prank(USER1);
        kipuBank.createAccount();

        // Depositar fondos
        vm.prank(USER1);
        mockToken.approve(address(kipuBank), 100 * 1e18);
        kipuBank.deposit(address(mockToken), 100 * 1e18);

        // Avanzar tiempo para evitar lock period
        vm.warp(block.timestamp + 1 days + 1);

        // Retirar fondos (con fee)
        vm.prank(USER1);
        kipuBank.withdraw(address(mockToken), 50 * 1e18);

        // Balance del contrato antes de retirar fees
        uint256 contractBalanceBefore = mockToken.balanceOf(address(kipuBank));

        // Retirar fees como admin
        vm.prank(ADMIN);
        kipuBank.withdrawFees(address(mockToken));

        // Verificar que los fees fueron retirados
        assertLt(mockToken.balanceOf(address(kipuBank)), contractBalanceBefore);
    }
}

// Contrato mock para AggregatorV3Interface (Chainlink)
contract MockAggregator is AggregatorV3Interface {
    uint256 private _answer;
    uint8 private _decimals;

    constructor(uint256 initialAnswer, uint8 decimalsChange) {
        _answer = initialAnswer;
        _decimals = decimalsChange;
    }

    function getAnswer(uint256) external view returns (uint256) {
        return _answer;
    }

    function getTimestamp(uint256) external view returns (uint256) {
        return block.timestamp;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80,
            int256 answer,
            uint256,
            uint256 timestamp,
            uint80
        )
    {
        return (uint80(1), int256(_answer), block.timestamp, block.timestamp, uint80(1));
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "Mock Aggregator";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function setAnswer(uint256 newAnswer) external {
        _answer = newAnswer;
    }

    function getRoundData(
        uint80
    ) external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (uint80(1), int256(_answer), block.timestamp, block.timestamp, uint80(1));
    }
}