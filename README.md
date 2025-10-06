# KipuBankV2 - Guía de Despliegue con Foundry

Este documento explica cómo desplegar el contrato inteligente **KipuBankV2** (versión mejorada del contrato original) usando el framework **Foundry**.

---

## 📋 Requisitos Previos

Antes de comenzar, asegúrate de tener instalado lo siguiente:

1. **Foundry** (versión recomendada: `>= 0.2.0`)
   - Instalación: [Documentación oficial de Foundry](https://book.getfoundry.sh/getting-started/installation)
   - Verifica la instalación con:
     ```bash
     forge --version
     ```

2. **Node.js** (versión recomendada: `>= 16.0.0`)
   - Instalación: [Node.js oficial](https://nodejs.org/)

3. **Git** (opcional, pero recomendado)
   - Instalación: [Git oficial](https://git-scm.com/)

4. **Variables de entorno** (para claves privadas y APIs)
   - Recomendamos usar un archivo `.env` (ver sección de configuración)

---

## 🚀 Configuración Inicial

### Clonar el repositorio (si aplica)
Si estás trabajando desde un repositorio:
```bash
git clone <URL_DEL_REPOSITORIO>
cd <NOMBRE_DEL_PROYECTO>
```

### Instalar dependencias
Ejecuta el siguiente comando para instalar las dependencias necesarias (OpenZeppelin, Chainlink, etc.):

```bash
forge install
```

Si necesitas instalar dependencias específicas manualmente:

```bash
forge install OpenZeppelin/openzeppelin-contracts
forge install smartcontractkit/chainlink-brownie-contracts
forge install foundry-rs/forge-std
```

### 3. Configurar variables de entorno
Crea un archivo .env en la raíz del proyecto con las siguientes variables (ajusta los valores según tu entorno):
```txt
# Configuración de red
RPC_URL_SEPOLIA=https://eth-sepolia.g.alchemy.com/v2/TU_API_KEY
RPC_URL_MAINNET=https://eth-mainnet.g.alchemy.com/v2/TU_API_KEY

# Claves privadas (¡NUNCA las compartas!)
PRIVATE_KEY=0x<tu_clave_privada_sin_0x>

# API Keys para verificación
ETHERSCAN_API_KEY=tu_api_key_de_etherscan

# Configuración del contrato
TOKEN_ADDRESS=0x...  # Dirección del token ERC20 (ej: MockToken)
BANK_CAP=1000000     # Límite global de depósitos (en USD con 6 decimales)
PRICE_FEED_ADDRESS=0x...  # Dirección del Price Feed de Chainlink (ej: ETH/USD)
```
⚠️ ADVERTENCIA: Nunca compartas tu .env o claves privadas. Añade .env a tu .gitignore.

🛠 Configuración de Foundry

### Compilar los contratos
Ejecuta el siguiente comando para compilar todos los contratos:

```bash
forge build
```
Esto generará los artefactos en la carpeta out/.

## 📝 Script de Despliegue

```bash
forge script script/KipuBankV2.s.sol:DeployKipuBankV2 --rpc-url $RPC_URL_SEPOLIA --private-key $PRIVATE_KEY --broadcast --verify
```

# 🔄 Mejoras Realizadas en V2

## 1. Seguridad Mejorada 🔒

Reentrancy Guard: Implementación de ReentrancyGuard de OpenZeppelin para prevenir ataques de reentrada

Ownable: Uso del patrón Ownable para funciones administrativas

Validaciones estrictas: Chequeos exhaustivos en todas las funciones críticas

Uso de nonReentrant: En funciones que manejan fondos (depósitos y retiros)

## 2. Contabilidad Mejorada 📊

Sistema de cuentas estructurado: Cada usuario tiene su propia estructura Account con:

Balance

Timestamp del último depósito

Contadores de depósitos y retiros

Contadores globales: Seguimiento de todas las operaciones en el contrato

Conversión a USD: Funciones para convertir saldos a valor en USD usando Chainlink


## 3. Lógica de Negocio Robusta 💼

Límite global de depósitos (bankCap): Previene que el contrato acumule demasiado riesgo

Depósito mínimo (minimumDeposit): Evita transacciones muy pequeñas

Período de bloqueo (lockPeriod): 1 día por defecto para prevenir retiros inmediatos

Límite por transacción (MAX_WITHDRAWL_PER_TRANS): 200 tokens por defecto

Fee de retiro (withdrawalFee): 5% por defecto


## 4. Observabilidad 👁️

Eventos detallados: Para todas las operaciones importantes

Funciones de consulta: Para obtener información sobre cuentas y estado del contrato

Conversión a USD: Funciones para obtener valores en USD usando Chainlink Price Feeds


## 5. Administración Flexible 🛠

Funciones configurables: Todos los parámetros principales pueden ser actualizados por el owner

Cambio de token: Posibilidad de cambiar el token ERC20 asociado

Cambio de price feed: Posibilidad de actualizar el oráculo de Chainlink

Retiro de fees: Función para que el owner retire las fees acumuladas


## 6. Integración con Chainlink 🔗

Uso de AggregatorV3Interface para obtener precios en tiempo real

Conversión de saldos a USD para validar el límite global (bankCap)

Flexibilidad para cambiar el price feed

# ⚖️ Decisiones de Diseño y Trade-offs

## 1. Uso de bankCap en lugar de un límite por usuario

Decisión: Implementar un límite global (bankCap) en lugar de límites individuales por usuario.


### Razón:

Más fácil de administrar para el owner del contrato

Permite una mejor gestión del riesgo global

Simplifica la lógica del contrato


### Trade-off:

No protege contra un solo usuario que acumule muchos fondos

Requiere monitoreo constante del total de depósitos


## 2. Período de bloqueo de 1 día

Decisión: Implementar un período de bloqueo de 1 día después de cada depósito.


### Razón:

Previene ataques de "depósito y retiro inmediato"

Da tiempo para detectar actividades sospechosas

Reduce la volatilidad en el corto plazo


### Trade-off:

Menor liquidez para los usuarios

Puede ser inconveniente para usuarios que necesitan acceso rápido a sus fondos


## 3. Fee de retiro del 5%

Decisión: Implementar un fee de retiro del 5%.


### Razón:

Cubre costos operativos

Desincentiva retiros frecuentes

Genera ingresos para el mantenimiento del contrato


### Trade-off:

Menor atractivo para usuarios que buscan bajos costos

Puede ser considerado alto en comparación con servicios tradicionales


## 4. Uso de Chainlink para precios

Decisión: Usar Chainlink Price Feeds para conversiones a USD.


### Razón:

Confiabilidad y descentralización

Amplia adopción en el ecosistema

Precios actualizados en tiempo real


### Trade-off:

Dependencia de un servicio externo

Costos adicionales por llamadas a Chainlink

Complejidad añadida en el código


## 5. Límite por transacción de 200 tokens

Decisión: Implementar un límite de 200 tokens por transacción de retiro.


### Razón:

Previene grandes retiros que podrían afectar la estabilidad

Reduce el riesgo de manipulación de precios

Limita el impacto de posibles errores


### Trade-off:

Los usuarios deben hacer múltiples transacciones para retiros grandes

Puede ser inconveniente para usuarios con grandes saldos


## 6. Uso de Ownable en lugar de un sistema de gobernanza

Decisión: Usar el patrón Ownable simple en lugar de un sistema de gobernanza completo.


### Razón:

Simplicidad en la implementación

Menor costo de gas para operaciones administrativas

Suficiente para la fase inicial del proyecto


### Trade-off:

Centralización en el owner

Menor transparencia en las decisiones

Riesgo si la clave privada del owner se compromete


## 7. Almacenamiento de saldos en el contrato

Decisión: Almacenar los saldos de los usuarios directamente en el contrato.


### Razón:

Simplicidad en la implementación

Fácil auditoría de los fondos totales

Menor complejidad en comparación con soluciones como ERC-4626


### Trade-off:

Todos los fondos están en un solo contrato (mayor riesgo)

Costos de gas más altos para operaciones con muchos usuarios

Menor flexibilidad para estrategias de inversión
