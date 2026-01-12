// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {MultipliVault} from "../../src/vault/MultipliVault.sol";
import {VariableVaultFee} from "../../src/fees/VariableVaultFee.sol";
import {IVariableVaultFee} from "../../src/interfaces/IVariableVaultFee.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {VaultFundManager} from "../../src/managers/VaultFundManager.sol";
import {Role} from "../../src/common/Role.sol";



/**
 * @title BaseDeployment
 * @dev Abstract base contract for MultipliVault deployment across different environments
 */
abstract contract BaseDeployment is Script {
    // =============== DEPLOYMENT VARIABLES =============
    address public ASSET;
    uint256 public INITIAL_LOCK_DEPOSIT_AMOUNT;
    string public SHARE_NAME;
    string public SHARE_SYMBOL;
    uint256 public MIN_DEPOSIT_AMOUNT;
    address public MULTIPLI_FUND_MANAGER_WALLET;
    address public OWNER;

    // =============== ROLE CONSTANTS =============
    uint8 constant ADMIN_ROLE = uint8(Role.ADMIN);
    uint8 constant FUND_MANAGER_ROLE = uint8(Role.FUND_MANAGER);
    uint8 constant FUND_MANAGER_CONTRACT_ROLE = uint8(Role.FUND_MANAGER_CONTRACT);
    uint8 constant ORACLE_ROLE = uint8(Role.ORACLE);
    uint8 constant EXTERNAL_CURATOR_ROLE = uint8(Role.EXTERNAL_CURATOR);


    MultipliVault public vault;
    VaultFundManager public fundManager;

    /**
     * @dev Abstract function to read environment variables
     * Must be implemented by child contracts
     */
    function setDeploymentConfig() public virtual;

    function _convertAddressToString(address addr) public pure returns (string memory) {
        return Strings.toHexString(uint256(uint160(addr)), 20);
    }

    /**
     * @dev Validates whether the deployment configuration variables
     *      have been correctly set. Logs the values and reverts if any required value is missing.
     */
    function validateDeploymentConfig() public view {
        require(ASSET != address(0), "ASSET cannot be empty");
        require(OWNER != address(0), "OWNER cannot be empty");
        require(bytes(SHARE_NAME).length > 0, "SHARE_NAME cannot be empty");
        require(bytes(SHARE_SYMBOL).length > 0, "SHARE_SYMBOL cannot be empty");
        require(INITIAL_LOCK_DEPOSIT_AMOUNT > 0, "INITIAL_LOCK_DEPOSIT_AMOUNT must be greater than 0");
        require(MIN_DEPOSIT_AMOUNT > 0, "MIN_DEPOSIT_AMOUNT must be greater than 0");
        require(MULTIPLI_FUND_MANAGER_WALLET != address(0), "MULTIPLI_FUND_MANAGER_WALLET cannot be empty");
        require(msg.sender == OWNER, string(abi.encodePacked(
            "Only deployer can call this: sender mismatch. Owner=", _convertAddressToString(OWNER), 
            " msg.sender=", _convertAddressToString(msg.sender))));
        
        console.log("ASSET:", ASSET);
        console.log("SHARE_NAME:", SHARE_NAME);
        console.log("SHARE_SYMBOL:", SHARE_SYMBOL);
        console.log("INITIAL_LOCK_DEPOSIT_AMOUNT:", INITIAL_LOCK_DEPOSIT_AMOUNT);
        console.log("MIN_DEPOSIT_AMOUNT:", MIN_DEPOSIT_AMOUNT);
        console.log("MULTIPLI_FUND_MANAGER_WALLET:", MULTIPLI_FUND_MANAGER_WALLET);
        console.log("OWNER/DEPLOYER:", OWNER);
        console.log("===========================================");
    }
  
    /**
     * @dev Main deployment function
     */
    function run() public {
       /*
        Note:
        When using the deployer bash helper with the `--verify` flag, 
        it may only verify the proxy contract — full verification is not guaranteed.

        In such cases, each deployed contract (e.g., implementation logic contracts)
        must be manually verified using the `forge verify-contract` command.

        Refer to:
        - base_helpers/deploy_xusdc_on_avax_testnet.sh
        - base_helpers/deploy_xusdc_on_avax_mainnet.sh

        Generic syntax:
            forge verify-contract \
                --compiler-version v0.8.30 \
                --watch \
                <IMPLEMENTATION_ADDRESS> \
                MultipliVault \
                --constructor-args <hex-encoded-args-if-any>

        Example for Avalanche Mainnet (Snowtrace via RouteScan):
            forge verify-contract \
                --chain-id 43114 \
                0x2a66bb2da3ad1c854e79307f64b862decd860d4c \
                src/vault/MultipliVault.sol:MultipliVault \
                --compiler-version v0.8.30+commit.2fe13dce \
                --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/43114/etherscan' \
                --etherscan-api-key YOUR_API_KEY_HERE \
                --watch
        */

        bool isFromTest = vm.envOr("IS_TEST", false); // default false

       if (!isFromTest) {
        // Only start broadcasting real transactions in non-test environments.
        // In tests, vm.startBroadcast() sets msg.sender to a default Foundry sender,
        // which breaks ownership logic that expects msg.sender to be the test contract.
            vm.startBroadcast();
        } else {
            // Group all owner operations together to avoid prank conflicts
            // In test environments, we need to simulate that all ownership-required operations
            // are called by the designated OWNER address, not by msg.sender (which would be
            // the test contract). This ensures proper access control validation.
            vm.startPrank(OWNER);
        }

        // Load and validate deployment-specific configuration values
        setDeploymentConfig();
        validateDeploymentConfig();

        console.log("msg.sender: %s", msg.sender);
        console.log("owner: %s", OWNER);
        console.log("block number: %d", block.number);

        require(OWNER != address(0), "Owner is not set");
        require(ASSET != address(0), "Asset address has not been set");
        require(INITIAL_LOCK_DEPOSIT_AMOUNT != 0, "INITIAL_LOCK_DEPOSIT_AMOUNT is 0");
        require(IERC20(ASSET).balanceOf(OWNER) >= INITIAL_LOCK_DEPOSIT_AMOUNT, "Insufficient funds");

        // =============== DEPLOY ROLES AUTHORITY CONTRACT  =============
        console.log("Deploying Authority contract...");
        RolesAuthority authority = new RolesAuthority(OWNER, RolesAuthority(address(0)));
        console.log("Authority deployed at: ", address(authority));
        // =============== ENDS HERE ================================

        // =============== DEPLOY VariableVaultFee CONTRACT  =============
        console.log("Deploying Fee contract");
        VariableVaultFee feeContract = new VariableVaultFee(OWNER);
        console.log("Fee contract deployed at: ", address(feeContract));
        // =============== ENDS HERE ================================
        
        // =============== REGISTER USDC FEE TO FEE CONTRACT  =============
        IVariableVaultFee.AssetFeeConfig memory initialFeeConfig = IVariableVaultFee.AssetFeeConfig({
            depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
            withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e15}), // Set withdrawal fee as 0.1%
            instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 5e15}), // Set instantRedeem fee as 0.5%
            flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e15}), // Set flashRedeem fee as 0.1%
            feeRecipient: OWNER
        });
        feeContract.registerAsset(ASSET, initialFeeConfig);
        console.log("Registered asset with Fee contract. Asset: ", ASSET);
        // =============== ENDS HERE ================================

        // =============== DEPLOY MULTIPLI XUSDC CONTRACT =============
        console.log("Deploying MultipliVault...");
        bytes memory data =
            abi.encodeWithSelector(MultipliVault.initialize.selector, IERC20(ASSET), OWNER, SHARE_NAME, SHARE_SYMBOL);
        address proxy = Upgrades.deployUUPSProxy("MultipliVault.sol", data);
        vault = MultipliVault(payable(address(proxy)));
        console.log("Multipli proxy deployed at: ", address(vault));
        // =============== ENDS HERE ================================

        // =============== SET FEE CONTRACT TO MULTIPLI XUSDC VAULT =============
        vault.setFeeContract(feeContract);
        console.log("Fee contract set for the vault");
        // =============== ENDS HERE ================================

        // =============== ASSIGN AUTHORITY TO MULTIPLI XUSDC VAULT =============
        vault.setAuthority(authority);
        console.log("Authority set for vault");
        // =============== ENDS HERE ================================

        // =============== INITIAL DEPOSIT INTO VAULT =============
        IERC20(ASSET).approve(address(vault), 0); // Resetting the allowance before setting a new allowance
        IERC20(ASSET).approve(address(vault), INITIAL_LOCK_DEPOSIT_AMOUNT);
        console.log("Allowance for vault: ", IERC20(ASSET).allowance(OWNER, address(vault)));
        vault.deposit(INITIAL_LOCK_DEPOSIT_AMOUNT, OWNER);
        // =============== ENDS HERE ================================

        // =============== SET MINIMUM DEPOSIT AMOUNT FOR VAULT =============
        console.log("Setting MinDepositAmount: ", MIN_DEPOSIT_AMOUNT);
        vault.updateMinDepositAmount(MIN_DEPOSIT_AMOUNT);
        // =============== ENDS HERE ================================

        // =============== FUND MANAGER AND FUND MANAGER PERMISSIONS =============
        fundManager = new VaultFundManager(payable(address(vault)));

        authority.setUserRole(MULTIPLI_FUND_MANAGER_WALLET, FUND_MANAGER_ROLE, true); // Wallets, EOA's, etc can be added to FUND_MANAGER_ROLE. 
        authority.setUserRole(address(fundManager), FUND_MANAGER_CONTRACT_ROLE, true); // VaultFundManager contract itself will belong to this user group
        authority.setUserRole(OWNER, ADMIN_ROLE, true); // Assign ADMIN_ROLE to the OWNER address to allow admin-level permissions.

        // Set permissions for fund manager to call `manage` through which the methods in this contract are called.
        authority.setRoleCapability(
            FUND_MANAGER_ROLE, address(vault), bytes4(keccak256("manage(address,bytes,uint256)")), true
        ); // there are two manage methods, so manually adding in the signature
        authority.setRoleCapability(
            FUND_MANAGER_ROLE, address(fundManager), VaultFundManager.removeFundsFromVault.selector, true
        );
        authority.setRoleCapability(
            FUND_MANAGER_ROLE, address(fundManager), VaultFundManager.updateUnderlyingBalance.selector, true
        );
        authority.setRoleCapability(
            FUND_MANAGER_ROLE, address(fundManager), VaultFundManager.addFundsAndFulfillRedeem.selector, true
        );

        // set permissions for fund manager to call the following methods in the Vault
         authority.setRoleCapability(
            FUND_MANAGER_ROLE, address(vault), MultipliVault.pause.selector, true
        );
         authority.setRoleCapability(
            FUND_MANAGER_ROLE, address(vault), MultipliVault.unpause.selector, true
        );

        // Allow ADMIN_ROLE to update the user-operator whitelist on VaultFundManage, enabling or disabling operators who can interact with the vault via the fund manager (for flashRedeem functionality)
         authority.setRoleCapability(
            ADMIN_ROLE, address(fundManager), VaultFundManager.updateUserOperatorWhitelist.selector, true
        );
        
        // set permissions for fund manager contract to call the following methods in the Vault
        authority.setRoleCapability(
            FUND_MANAGER_CONTRACT_ROLE, address(vault), MultipliVault.onUnderlyingBalanceUpdate.selector, true
        );
        authority.setRoleCapability(
            FUND_MANAGER_CONTRACT_ROLE, address(vault), MultipliVault.removeFunds.selector, true
        );
        authority.setRoleCapability(
            FUND_MANAGER_CONTRACT_ROLE, address(vault), MultipliVault.fulfillRedeem.selector, true
        );
        authority.setRoleCapability(
            FUND_MANAGER_CONTRACT_ROLE, address(vault), MultipliVault.flashRedeem.selector, true
        );

        if (isFromTest) {
            vm.stopPrank();
        } else {
            vm.stopBroadcast();
        }

        // =============== ENDS HERE ================================

        (
            VariableVaultFee.FeeConfig memory wConfig,
            VariableVaultFee.FeeConfig memory dConfig,
            VariableVaultFee.FeeConfig memory iwConfig, 
            VariableVaultFee.FeeConfig memory frConfig, 
            address ffeeRecipient
          ) = feeContract.assetFee(ASSET);

        console.log("\nVault data:");
        console.log("Underlying asset:", address(vault.asset()));
        console.log("Name:", vault.name());
        console.log("Symbol:", vault.symbol());
        console.log("Owner:", vault.owner());
        console.log("Total Supply:", vault.totalSupply());
        console.log("Proxy address:", proxy);
        console.log("Implementation address:", Upgrades.getImplementationAddress(proxy));
        console.log("Proxy admin:", Upgrades.getAdminAddress(proxy));
        console.log("Authority:", address(vault.authority()));
        console.log("Authority owner:", authority.owner());
        console.log("Fund Manager Contract: ", address(fundManager));
        console.log("VariableVaultFee Contract: ", address(vault.feeContract()));
        console.log("VariableVaultFee owner : ", feeContract.owner());
        console.log("FeeRecipient:", vault.getFeeRecipient());
        console.log("MinDepositAmount:", vault.minDepositAmount());
        console.log("Deposit Fee Config\n\tFee type: %s \n\tFee amount: %s", uint8(dConfig.feeType), dConfig.feeAmount);
        console.log("Withdraw Fee Config\n\tFee type: %s\n\tFee amount: %s", uint8(wConfig.feeType), wConfig.feeAmount);
        console.log("Instant Withdraw Fee Config\n\tFee type: %s\n\tFee amount: %s", uint8(iwConfig.feeType), iwConfig.feeAmount);
        console.log("Flash Redeem Fee Config\n\tFee type: %s\n\tFee amount: %s", uint8(frConfig.feeType), frConfig.feeAmount);
    }
}