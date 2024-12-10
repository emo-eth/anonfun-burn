// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {BaseCreate2Script} from "create2-helpers/script/BaseCreate2Script.s.sol";
import {DeterministicUpgradeableFactory} from "src/proxy/DeterministicUpgradeableFactory.sol";
import {SimpleUpgradeableProxy} from "src/proxy/SimpleUpgradeableProxy.sol";
import {FarcasterSignatureValidator} from "src/FarcasterSignatureValidator.sol";
import {UniV3Rebuyer} from "src/UniV3Rebuyer.sol";

/**
 * @title Deploy
 * @notice Handles deployment and upgrades of proxy contracts
 */
contract Deploy is BaseCreate2Script {
    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Main deployment function
     */
    function run() external {
        runOnNetworks(this.runLogic, vm.envString("NETWORKS", ","));
    }

    /**
     * @notice Core deployment logic
     */
    function runLogic() external {
        // Deploy factory if needed
        address factory = _create2IfNotDeployed(
            deployer, bytes32(0), type(DeterministicUpgradeableFactory).creationCode
        );
        console2.log("Factory deployed at", factory);

        // Deploy and upgrade proxy
        address proxy = safeDeployProxy(address(factory));
        _upgradeOpProxy(proxy);
        _upgradeBaseProxy(proxy);
    }

    /**
     * @notice Safely deploys proxy if not already deployed
     * @param factory Factory contract address
     * @return Address of proxy
     */
    function safeDeployProxy(address factory) public returns (address) {
        address proxy = predictProxyAddress(factory);
        if (address(proxy).code.length > 0) {
            return proxy;
        }
        proxy = deployProxy(factory);
        console2.log("Proxy deployed at", proxy);
        logConstructorArgs(factory);
        return proxy;
    }

    /**
     * @notice Deploys new proxy
     * @param factory Factory contract address
     * @return Address of deployed proxy
     */
    function deployProxy(address factory) public returns (address) {
        console2.log("Deploying proxy");
        vm.broadcast(deployer);
        return DeterministicUpgradeableFactory(factory).deployDeterministicUUPS(
            bytes32("anonfun"), vm.envAddress("INITIAL_OWNER")
        );
    }

    /**
     * @notice Predicts proxy address before deployment
     * @param factory Factory contract address
     * @return Predicted proxy address
     */
    function predictProxyAddress(address factory) public view returns (address) {
        return DeterministicUpgradeableFactory(factory).predictDeterministicUUPSAddress(
            bytes32("anonfun"), vm.envAddress("INITIAL_OWNER")
        );
    }

    /**
     * @notice Upgrades Optimism proxy implementation
     * @param verifier New implementation address
     * @param proxy Proxy address
     */
    function upgradeOpProxy(address verifier, address proxy) external {
        vm.broadcast(deployer);
        SimpleUpgradeableProxy(proxy).upgradeToAndCall(
            verifier,
            abi.encodeCall(
                FarcasterSignatureValidator.reinitialize,
                (5, deployer, vm.envAddress("ERC1271_SIGNER"))
            )
        );

        // Verify upgrade
        require(FarcasterSignatureValidator(proxy).owner() == deployer, "Owner not set");
        require(
            FarcasterSignatureValidator(proxy).getSigner() == vm.envAddress("ERC1271_SIGNER"),
            "Signer not set"
        );
    }

    /**
     * @notice Upgrades Base proxy implementation
     * @param implementation New implementation address
     * @param proxy Proxy address
     */
    function upgradeBaseProxy(address implementation, address proxy) external {
        uint64 version = 2;
        uint96 maxAmountOutPerTx = 0.1 ether;
        uint40 minSwapDelay = 60 minutes;
        uint16 maxIncreaseBps = 100; // 1%

        vm.broadcast(deployer);
        SimpleUpgradeableProxy(proxy).upgradeToAndCall(
            implementation,
            abi.encodeCall(
                UniV3Rebuyer.reinitialize,
                (version, maxAmountOutPerTx, minSwapDelay, maxIncreaseBps)
            )
        );

        // Verify upgrade
        require(
            UniV3Rebuyer(payable(proxy)).getMaxAmountOutPerTx() == maxAmountOutPerTx,
            "Max amount out per tx not set"
        );
        require(
            UniV3Rebuyer(payable(proxy)).getMinSwapDelay() == minSwapDelay, "Min swap delay not set"
        );
        require(
            UniV3Rebuyer(payable(proxy)).getMaxIncreaseBps() == maxIncreaseBps,
            "Max increase bps not set"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Handles Optimism proxy upgrade logic
     * @param proxy Proxy address
     */
    function _upgradeOpProxy(address proxy) internal {
        if (block.chainid != 10 && block.chainid != 11155420) return;

        console2.log("Upgrading op proxy to signature validator");
        address verifier = _create2IfNotDeployed(
            deployer, bytes32(0), type(FarcasterSignatureValidator).creationCode
        );
        console2.log("Verifier deployed at", verifier);

        try this.upgradeOpProxy(verifier, proxy) {
            console2.log("Upgrade successful");
        } catch (bytes memory reason) {
            console2.log("Upgrade failed");
            console2.logBytes(reason);
        }
    }

    /**
     * @notice Handles Base proxy upgrade logic
     * @param proxy Proxy address
     */
    function _upgradeBaseProxy(address proxy) internal {
        if (block.chainid != 8453000000 && block.chainid != 84532) return;

        console2.log("Upgrading base proxy to UniV3Rebuyer");
        address implementation =
            _create2IfNotDeployed(deployer, bytes32(0), type(UniV3Rebuyer).creationCode);
        console2.log("Implementation deployed at", implementation);

        try this.upgradeBaseProxy(implementation, proxy) {
            console2.log("Upgrade successful");
        } catch (bytes memory reason) {
            console2.log("Upgrade failed");
            console2.logBytes(reason);
        }
    }

    /**
     * @notice Logs constructor arguments for verification
     * @param factory Factory contract address
     */
    function logConstructorArgs(address factory) internal view {
        bytes memory constructorArgs = abi.encode(
            DeterministicUpgradeableFactory(factory).implementation(),
            abi.encodeCall(SimpleUpgradeableProxy.initialize, vm.envAddress("INITIAL_OWNER"))
        );
        console2.logBytes(constructorArgs);
    }
}
