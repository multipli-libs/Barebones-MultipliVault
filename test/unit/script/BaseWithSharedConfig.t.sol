// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IVariableVaultFee} from "../../../src/interfaces/IVariableVaultFee.sol";
import {VariableVaultFee} from "../../../src/fees/VariableVaultFee.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {MultipliVault} from "../../../src/vault/MultipliVault.sol";
import {VaultFundManager} from "../../../src/managers/VaultFundManager.sol";
import {BaseWithSharedConfig} from "../../../script/deployment/BaseWithSharedConfig.s.sol";
import {BaseDeployment} from "../../../script/deployment/Base.s.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MockERC20} from "../../../test/mocks/MockERC20.sol";
import {Constants} from "../../utils/Constants.sol";
import {ConfigLib} from "../../utils/ConfigLib.sol";


contract BrokenAssetScript is BaseWithSharedConfig {
    constructor(ConfigLib.NetworkConfig memory config){
        INITIAL_LOCK_DEPOSIT_AMOUNT = config.tokenConfig.initialLockDepositAmount;
        MIN_DEPOSIT_AMOUNT = config.tokenConfig.minDepositAmount;
        SHARE_NAME = config.tokenConfig.vaultSymbol;
        SHARE_SYMBOL = config.tokenConfig.vaultSymbol;
    }

    function setDeploymentConfig() public override {
        OWNER = msg.sender;
        ASSET = address(0); 
        MULTIPLI_FUND_MANAGER_WALLET = address(0x123);
    }
}

contract ZeroDepositScript is BaseWithSharedConfig {
    constructor(ConfigLib.NetworkConfig memory config){
        MIN_DEPOSIT_AMOUNT = config.tokenConfig.minDepositAmount;
        SHARE_NAME = config.tokenConfig.vaultSymbol;
        SHARE_SYMBOL = config.tokenConfig.vaultSymbol;
        ASSET = address(config.tokenConfig.token);
    }

    function setDeploymentConfig() public override {
        OWNER = msg.sender;
        INITIAL_LOCK_DEPOSIT_AMOUNT = 0; // Invalid deposit
        MULTIPLI_FUND_MANAGER_WALLET = address(0x123);
    }
}

contract EmptyNameScript is BaseWithSharedConfig {
    constructor(ConfigLib.NetworkConfig memory config){
        MIN_DEPOSIT_AMOUNT = config.tokenConfig.minDepositAmount;
        SHARE_SYMBOL = config.tokenConfig.vaultSymbol;
        ASSET = address(config.tokenConfig.token);
    }
    function setDeploymentConfig() public override {
        OWNER = msg.sender;
        INITIAL_LOCK_DEPOSIT_AMOUNT = 0; // Invalid deposit
        SHARE_NAME = "";
        MULTIPLI_FUND_MANAGER_WALLET = address(0x123);
    }
}

contract EmptySymbolScript is BaseWithSharedConfig {
    constructor(ConfigLib.NetworkConfig memory config){
        INITIAL_LOCK_DEPOSIT_AMOUNT = config.tokenConfig.initialLockDepositAmount;
        MIN_DEPOSIT_AMOUNT = config.tokenConfig.minDepositAmount;
        SHARE_NAME = config.tokenConfig.vaultSymbol;
        ASSET = address(config.tokenConfig.token);
    }

    function setDeploymentConfig() public override {
        OWNER = msg.sender;
        SHARE_SYMBOL = ""; // 
        MULTIPLI_FUND_MANAGER_WALLET = address(0x123);
    }
}
contract ZeroMinDepositScript is BaseWithSharedConfig {
    constructor(ConfigLib.NetworkConfig memory config){
        INITIAL_LOCK_DEPOSIT_AMOUNT = config.tokenConfig.initialLockDepositAmount;
        SHARE_NAME = config.tokenConfig.vaultSymbol;
        SHARE_SYMBOL = config.tokenConfig.vaultSymbol;
        ASSET = address(config.tokenConfig.token);
    }

    function setDeploymentConfig() public override {
        OWNER = msg.sender;
        MIN_DEPOSIT_AMOUNT = 0; 
        MULTIPLI_FUND_MANAGER_WALLET = address(0x123);
    }
}

contract ZeroFundManagerScript is BaseWithSharedConfig {
    constructor(ConfigLib.NetworkConfig memory config){
        INITIAL_LOCK_DEPOSIT_AMOUNT = config.tokenConfig.initialLockDepositAmount;
        SHARE_NAME = config.tokenConfig.vaultSymbol;
        ASSET = address(config.tokenConfig.token);
        MIN_DEPOSIT_AMOUNT = config.tokenConfig.minDepositAmount;
        SHARE_SYMBOL = config.tokenConfig.vaultSymbol;
    }

    function setDeploymentConfig() public override {
        OWNER = msg.sender;
        MULTIPLI_FUND_MANAGER_WALLET = address(0); 
    }
}

contract BaseDeploymentScriptStub is BaseWithSharedConfig {
    address public overrideOwner;

    constructor(ConfigLib.NetworkConfig memory config){
        INITIAL_LOCK_DEPOSIT_AMOUNT = config.tokenConfig.initialLockDepositAmount;
        SHARE_NAME = config.tokenConfig.vaultSymbol;
        ASSET = address(config.tokenConfig.token); // fallback to mainnet address(config.tokenConfig.token);
        MIN_DEPOSIT_AMOUNT = config.tokenConfig.minDepositAmount;
        SHARE_SYMBOL = config.tokenConfig.vaultSymbol;
    }

    function setDeploymentConfig() public override {
        OWNER = msg.sender;
        MULTIPLI_FUND_MANAGER_WALLET = address(0x123);
    }

    function setMockAsset(address asset) public {
        ASSET = asset;
    }

    function callSetDeploymentConfig() public {
        setDeploymentConfig();
    }

     function setOwner(address owner_) public {
        overrideOwner = owner_;
    }
}

// todo: Values Used below are speicifc to the token only and shouild be fixed once the test architecture PR is merged

abstract contract DeployXTokenBaseTest is Test, Constants {
    BaseWithSharedConfig public deploymentScript;
    VariableVaultFee existingFeeContract;
    BaseDeployment public deploymentXUSDCScript;
    MultipliVault public vault;
    VariableVaultFee public feeContract;
    RolesAuthority public authority;
    IERC20 public asset;
    address public owner;
    VaultFundManager public fundManager;
    bool public isLocal = false;
    ConfigLib.NetworkEnv public env;


    address public TOKEN_ADDRESS;
    uint256 public EXPECTED_MIN_DEPOSIT_AMOUNT;
    ConfigLib.NetworkConfig public _config;

    function _initializeVault(
        ConfigLib.NetworkConfig memory config
    ) internal {
        vm.setEnv("IS_TEST", "true");
        EXPECTED_MIN_DEPOSIT_AMOUNT = config.tokenConfig.minDepositAmount;
        _config = config;

        if(config.env ==  ConfigLib.NetworkEnv.ANVIL){
            isLocal = true;
        }
        
        env = config.env;

        if (!isLocal) {
           
            uint256 forkId = vm.createFork(config.rpcUrl);
            vm.selectFork(forkId);
        }

        deploymentScript.setDeploymentConfig(); 
        owner = deploymentScript.OWNER();

        if (isLocal) {
            deploymentXUSDCScript.setDeploymentConfig();
            owner = deploymentXUSDCScript.OWNER();

            vm.startPrank(owner);
            deploymentXUSDCScript.run();

            MultipliVault xusdcVault = MultipliVault(deploymentXUSDCScript.vault());
            existingFeeContract = VariableVaultFee(address(xusdcVault.feeContract()));
            deploymentScript.setVariableVaultFeeContract(address(existingFeeContract));
            vm.stopPrank();
        } else if (env == ConfigLib.NetworkEnv.MAINNET) {
            TOKEN_ADDRESS = config.tokenConfig.token;
            deal(TOKEN_ADDRESS, owner, 100e8);
        }

        vm.startPrank(owner);
        deploymentScript.run();
        vm.stopPrank();

        vault = MultipliVault(deploymentScript.vault());
        feeContract = VariableVaultFee(address(vault.feeContract()));
        authority = RolesAuthority(address(vault.authority()));
        asset = IERC20(vault.asset());
        fundManager = VaultFundManager(BaseWithSharedConfig(address(deploymentScript)).fundManager());
    }

    function testVaultMetadata() public view {
        assertEq(vault.name(), deploymentScript.SHARE_NAME());
        assertEq(vault.symbol(), deploymentScript.SHARE_SYMBOL());
        assertEq(vault.name(), _config.tokenConfig.vaultSymbol);
        assertEq(vault.symbol(), _config.tokenConfig.vaultSymbol);
    }

    function testOwners() public view {
        assertEq(vault.owner(), owner);
        assertEq(feeContract.owner(), owner);
        assertEq(authority.owner(), owner);
    }

    function testVaultMinDepositAmount() public view {
        assertEq(vault.minDepositAmount(), deploymentScript.MIN_DEPOSIT_AMOUNT());
    }

    function testAssetProperties() public view {
        IERC20Metadata token = IERC20Metadata(address(asset));
        assertEq(token.symbol(), _config.tokenConfig.assetSymbol);
        assertEq(token.decimals(), 8);
        if(env == ConfigLib.NetworkEnv.MAINNET) {
          assertEq(VARIABLE_VAULT_FEE_CONTRACT_ADDRESS, address(feeContract));
        } else if(env == ConfigLib.NetworkEnv.TESTNET){
          assertEq(0x64B88690e88d3A72F45899E804f1805B8e45a6F2, address(feeContract));
        }
    }

    function testVaultAssetAddressCheck() public view {
        assertEq(address(asset), deploymentScript.ASSET());
    }

    function testVaultInitialSupply() public view {
        assertEq(vault.totalSupply(), deploymentScript.INITIAL_LOCK_DEPOSIT_AMOUNT());
        assertEq(vault.balanceOf(owner), deploymentScript.INITIAL_LOCK_DEPOSIT_AMOUNT());
    }

    function testFeeConfigValidation() public view {
        (
            IVariableVaultFee.FeeConfig memory withdrawFee,
            IVariableVaultFee.FeeConfig memory depositFee,
            IVariableVaultFee.FeeConfig memory instantWithdrawFee,
            IVariableVaultFee.FeeConfig memory flashRedeemFee,
            address recipient
        ) = feeContract.assetFee(address(asset));
        

        assertEq(uint8(depositFee.feeType), uint8(IVariableVaultFee.FeeType.FLAT));
        assertEq(depositFee.feeAmount, 0);

        assertEq(uint8(withdrawFee.feeType), uint8(IVariableVaultFee.FeeType.PERCENTAGE));
        assertEq(withdrawFee.feeAmount, 2e14);

        assertEq(uint8(instantWithdrawFee.feeType), uint8(IVariableVaultFee.FeeType.PERCENTAGE));
        assertEq(instantWithdrawFee.feeAmount, 5e15);

        assertEq(uint8(flashRedeemFee.feeType), uint8(IVariableVaultFee.FeeType.PERCENTAGE));
        assertEq(flashRedeemFee.feeAmount, 2e14);
        
        assertEq(recipient, owner);
    }

    function testProxyAndAdmin() public view {
        address proxy = address(vault);
        address impl = Upgrades.getImplementationAddress(proxy);
        address admin = Upgrades.getAdminAddress(proxy);

        assertTrue(impl != address(0), "Implementation should not be zero");
        assertEq(admin, address(0), "UUPS admin should be 0");
    }

    function testEOAFundManagerRoleAndPermissions() public view {
        address eoaFundManager = deploymentScript.MULTIPLI_FUND_MANAGER_WALLET();
        // Role checks
        assertTrue(authority.doesUserHaveRole(eoaFundManager, FUND_MANAGER_ROLE), "EOA should have FUND_MANAGER_ROLE");
        // EOA permission check: `manage` on vault
        assertTrue(
            authority.canCall(
                eoaFundManager,
                address(vault),
                bytes4(keccak256("manage(address,bytes,uint256)"))
            ),
            "EOA should be able to call manage on vault"
        );

        // FUND_MANAGER_ROLE -> VaultFundManager methods
        assertTrue(
            authority.canCall(eoaFundManager, address(fundManager), fundManager.removeFundsFromVault.selector),
            "EOA should be able to call removeFundsFromVault"
        );
        assertTrue(
            authority.canCall(eoaFundManager, address(fundManager), fundManager.updateUnderlyingBalance.selector),
            "EOA should be able to call updateUnderlyingBalance"
        );
        assertTrue(
            authority.canCall(eoaFundManager, address(fundManager), fundManager.addFundsAndFulfillRedeem.selector),
            "EOA should be able to call addFundsAndFulfillRedeem"
        );

        // pause/unpause permissions
        assertTrue(
            authority.canCall(eoaFundManager, address(vault), vault.pause.selector),
            "Contract should call pause"
        );
        assertTrue(
            authority.canCall(eoaFundManager, address(vault), vault.unpause.selector),
            "Contract should call unpause"
        );
    }
    
    function testFundManagerContractRoleAndVaultPermissions() public view {
        address fundManagerContract = address(fundManager);

        assertTrue(authority.doesUserHaveRole(fundManagerContract, FUND_MANAGER_CONTRACT_ROLE), "Contract should have FUND_MANAGER_CONTRACT_ROLE");

        // Contract permissions: Vault -> fundManagerContract
        assertTrue(
            authority.canCall(fundManagerContract, address(vault), vault.onUnderlyingBalanceUpdate.selector),
            "Contract should call onUnderlyingBalanceUpdate"
        );
        assertTrue(
            authority.canCall(fundManagerContract, address(vault), vault.removeFunds.selector),
            "Contract should call removeFunds"
        );
        assertTrue(
            authority.canCall(fundManagerContract, address(vault), vault.fulfillRedeem.selector),
            "Contract should call fulfillRedeem"
        );
        assertTrue(
            authority.canCall(fundManagerContract, address(vault), vault.flashRedeem.selector),
            "Contract should call flashRedeem"
        );
    }

    function testAdminRoleCanUpdateUserOperatorWhitelist() public view {
        address admin = owner; // Assuming OWNER has ADMIN_ROLE
        address fundManagerContract = address(fundManager);

        assertTrue(
            authority.doesUserHaveRole(admin, ADMIN_ROLE),
            "OWNER should have ADMIN_ROLE"
        );

        assertTrue(
            authority.canCall(owner, fundManagerContract, VaultFundManager.updateUserOperatorWhitelist.selector),
            "ADMIN_ROLE should be able to call updateUserOperatorWhitelist on fundManager"
        );
    }

    function testDeployScriptHasNoRoles() public view {
        address deployer = address(deploymentScript);
        assertFalse(authority.doesUserHaveRole(deployer, FUND_MANAGER_ROLE));
        assertFalse(authority.doesUserHaveRole(deployer, FUND_MANAGER_CONTRACT_ROLE));
    }

    function testRandomUserHasNoPermissions() public {
        address random = makeAddr("random");
        assertFalse(authority.doesUserHaveRole(random, ADMIN_ROLE));
        assertFalse(authority.canCall(random, address(vault), bytes4(keccak256("manage(address,bytes,uint256)"))));
    }

    function testUnusedRolesUnassigned() public view {
        assertFalse(authority.doesUserHaveRole(owner, ORACLE_ROLE));
        assertFalse(authority.doesUserHaveRole(owner, EXTERNAL_CURATOR_ROLE));
    }

    function testRevertsIfAssetIsZero() public {
        vm.setEnv("IS_TEST", "true");
     
        BrokenAssetScript script = new BrokenAssetScript(_config);
        vm.expectRevert("ASSET cannot be empty");
        script.run();

    }

    function testRevertsIfInitialDepositIsZero() public {
        vm.setEnv("IS_TEST", "true");

        ZeroDepositScript script = new ZeroDepositScript(_config);
        vm.expectRevert("INITIAL_LOCK_DEPOSIT_AMOUNT must be greater than 0");
        script.run();
    }

    function testRevertIfShareNameEmpty() public {
        EmptyNameScript script = new EmptyNameScript(_config);
        vm.expectRevert("SHARE_NAME cannot be empty");
        script.run();
    }

    function testRevertIfShareSymbolEmpty() public {
        EmptySymbolScript script = new EmptySymbolScript(_config);
        vm.expectRevert("SHARE_SYMBOL cannot be empty");
        script.run();
    }

    function testRevertIfMinDepositAmountIsZero() public {
        ZeroMinDepositScript script = new ZeroMinDepositScript(_config);
        vm.expectRevert("MIN_DEPOSIT_AMOUNT must be greater than 0");
        script.run();
    }

    function testRevertIfFundManagerAddressIsZero() public {
        ZeroFundManagerScript script = new ZeroFundManagerScript(_config);
        vm.expectRevert("MULTIPLI_FUND_MANAGER_WALLET cannot be empty");
        script.run();
    }

   function testValidateDeploymentConfigDirectly() public {
        BaseDeploymentScriptStub script = new BaseDeploymentScriptStub(_config);
        if(isLocal){
           script.setVariableVaultFeeContract(address(existingFeeContract));
        }else{
           script.setVariableVaultFeeContract(deploymentScript.VARIABLE_VAULT_FEE());
        }
        script.callSetDeploymentConfig(); // sets config
        script.validateDeploymentConfig(); // now hits the public function directly
    }

    function testDeployWithBroadcast_False() public {

        vm.setEnv("IS_TEST", "true");
        
        // address deployer = DEPLOYER_ADDRESS;

        // if(env == ConfigLib.NetworkEnv.MAINNET) {
        //     deployer = DEPLOYER_ADDRESS;
        // }else{
        //     deployer = owner;
        // }

        address deployer = owner;

        vm.startPrank(deployer);

        // Setup mock token
        MockERC20 mockToken = new MockERC20(_config.tokenConfig.assetSymbol, _config.tokenConfig.assetSymbol, _config.tokenConfig.decimals);
        mockToken.mint(deployer,  _config.tokenConfig.initialLockDepositAmount); // 0.005 tokens

        // Use stub
        BaseDeploymentScriptStub script = new BaseDeploymentScriptStub(_config);
        script.setMockAsset(address(mockToken));
        script.setOwner(deployer);
         if(isLocal){
           script.setVariableVaultFeeContract(address(existingFeeContract));
        }else{
           script.setVariableVaultFeeContract(deploymentScript.VARIABLE_VAULT_FEE());
        }
        script.callSetDeploymentConfig();
       
        script.run();

        // Validate vault deployed
        MultipliVault vault = MultipliVault(script.vault());
        assertEq(vault.totalSupply(),  _config.tokenConfig.initialLockDepositAmount); 

        vm.stopPrank();
    }

    function testRevertsIfSenderNotDeployer() public {
        BaseDeploymentScriptStub script = new BaseDeploymentScriptStub(_config);
        if(isLocal){
           script.setVariableVaultFeeContract(address(existingFeeContract));
        }else{
           script.setVariableVaultFeeContract(deploymentScript.VARIABLE_VAULT_FEE());
        }
        script.callSetDeploymentConfig();
        address actualOwner = script.OWNER(); 
        
        address fakeOwner = makeAddr("FAKE_OWNER");
        
        // Build the complete expected error message
        string memory expectedError = string(abi.encodePacked(
            "Only deployer can call this: sender mismatch. Owner=",
            script._convertAddressToString(actualOwner),
            " msg.sender=",
            script._convertAddressToString(fakeOwner)
        ));
        // bytes() conversion is required because:
        // 1. Solidity stores revert messages internally as bytes, not strings
        // 2. vm.expectRevert() expects bytes parameter to match the raw revert data
        // 3. There's no vm.expectRevert(string) overload - only vm.expectRevert(bytes)
        vm.expectRevert(bytes(expectedError));
        vm.prank(fakeOwner);
        script.validateDeploymentConfig();
    }
}
