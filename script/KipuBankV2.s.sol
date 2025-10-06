// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {KipuBankV2} from "../src/KipuBankV2.sol";
import {MockToken} from "../src/MockToken.sol";

contract DeployKipuBankV2 is Script {
    function run() external {
        // Cargar variables de entorno
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        uint256 bankCap = vm.envUint("BANK_CAP");
        address priceFeedAddress = address(uint160(vm.envUint("PRICE_FEED_ADDRESS")));

        // Configurar el fork o la red
        vm.startBroadcast(privateKey);

        // Desplegar MockToken (solo para pruebas, omitir si ya tienes un token)
        MockToken mockToken = new MockToken(msg.sender);
        console.log("MockToken desplegado en:", address(mockToken));

        // Desplegar KipuBankV2
        KipuBankV2 kipuBank = new KipuBankV2(
            bankCap,
            priceFeedAddress
        );
        console.log("KipuBankV2 desplegado en:", address(kipuBank));

        // Configurar el token en el banco (si es necesario)
        // kipuBank.addSupportedToken(tokenToUse, 18, false, priceFeedAddress);

        // Detener la transmisión
        vm.stopBroadcast();

        // Verificar el código en Etherscan (opcional)
        // string memory etherscanApiKey = vm.envString("ETHERSCAN_API_KEY");
        // verifyContract(address(kipuBank), etherscanApiKey);
    }

    // Función para verificar el contrato en Etherscan (descomentar si es necesario)
    /*
    function verifyContract(address contractAddress, string memory apiKey) internal {
        string[2] memory args = [
            string(abi.encodePacked(bankCap)),
            string(abi.encodePacked(priceFeedAddress))
        ];
        string memory command = string.concat(
            "forge verify-contract --chain-id 11155111 --num-of-optimizations 200 --watch ",
            " --constructor-args ",
            args[0], " ", args[1],
            " --compiler-version v0.8.20+commit.a1b79de6 ",
            " --etherscan-api-key ", apiKey, " ",
            addressToString(contractAddress), " ",
            "contracts/KipuBankV2.sol:KipuBankV2"
        );
        console.log("Comando para verificación:", command);
        // vm.system(command);
    }

    function addressToString(address _addr) internal pure returns (string memory) {
        bytes memory bytesAddr = abi.encodePacked(_addr);
        string memory strAddr = string(bytesAddr);
        return strAddr;
    }
    */
}