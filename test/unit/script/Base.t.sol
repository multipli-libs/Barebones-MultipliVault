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
import {BaseDeployment} from "../../../script/deployment/common/Base.s.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MockERC20} from "../../../test/mocks/MockERC20.sol";
import {Constants} from "../../utils/Constants.sol";
import {ConfigLib} from "../../utils/ConfigLib.sol";

contract BrokenAssetScript is BaseDeployment {
    constructor(ConfigLib.NetworkConfig memory config){
        INITIAL_LOCK_DEPOSIT_AMOUNT = 100*(10**config.tokenConfig.decimals);
        MIN_DEPOSIT_AMOUNT = 10*(10**config.tokenConfig.decimals);
        SHARE_NAME = config.tokenConfig.vaultSymbol;
        SHARE_SYMBOL = config.tokenConfig.vaultSymbol;
    }

    function setDeploymentConfig() public override {
        OWNER = msg.sender;
        ASSET = address(0); 
        MULTIPLI_FUND_MANAGER_WALLET = address(0x123);
    }
}

contract ZeroDepositScript is BaseDeployment {
    constructor(ConfigLib.NetworkConfig memory config) {
        INITIAL_LOCK_DEPOSIT_AMOUNT = 0; // still invalid deposit
        MIN_DEPOSIT_AMOUNT = 10 * (10 ** config.tokenConfig.decimals);
        SHARE_NAME = config.tokenConfig.vaultSymbol;
        SHARE_SYMBOL = config.tokenConfig.vaultSymbol;
    }

    function setDeploymentConfig() public override {
        OWNER = msg.sender;
        ASSET = address(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
        MULTIPLI_FUND_MANAGER_WALLET = address(0x123);
    }
}

contract EmptyNameScript is BaseDeployment {
    constructor(ConfigLib.NetworkConfig memory config) {
        MIN_DEPOSIT_AMOUNT = 10 * (10 ** config.tokenConfig.decimals);
        SHARE_SYMBOL = config.tokenConfig.vaultSymbol;
    }

    function setDeploymentConfig() public override {
        OWNER = msg.sender;
        ASSET = address(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
        SHARE_NAME = "";
        INITIAL_LOCK_DEPOSIT_AMOUNT = 0;
        MULTIPLI_FUND_MANAGER_WALLET = address(0x123);
    }
}

contract EmptySymbolScript is BaseDeployment {
    constructor(ConfigLib.NetworkConfig memory config) {
        INITIAL_LOCK_DEPOSIT_AMOUNT = 100 * (10 ** config.tokenConfig.decimals);
        MIN_DEPOSIT_AMOUNT = 10 * (10 ** config.tokenConfig.decimals);
        SHARE_NAME = config.tokenConfig.vaultSymbol;
    }

    function setDeploymentConfig() public override {
        OWNER = msg.sender;
        ASSET = address(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
         SHARE_SYMBOL = ""; 
        MULTIPLI_FUND_MANAGER_WALLET = address(0x123);
    }
}

contract ZeroMinDepositScript is BaseDeployment {
    constructor(ConfigLib.NetworkConfig memory config) {
        INITIAL_LOCK_DEPOSIT_AMOUNT = 100 * (10 ** config.tokenConfig.decimals);
        SHARE_NAME = config.tokenConfig.vaultSymbol;
        SHARE_SYMBOL = config.tokenConfig.vaultSymbol;
    }

    function setDeploymentConfig() public override {
        OWNER = msg.sender;
        ASSET = address(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
        MIN_DEPOSIT_AMOUNT = 0;
        MULTIPLI_FUND_MANAGER_WALLET = address(0x123);
    }
}

contract ZeroFundManagerScript is BaseDeployment {
    constructor(ConfigLib.NetworkConfig memory config) {
        INITIAL_LOCK_DEPOSIT_AMOUNT = 100 * (10 ** config.tokenConfig.decimals);
        MIN_DEPOSIT_AMOUNT = 10 * (10 ** config.tokenConfig.decimals);
        SHARE_NAME = config.tokenConfig.vaultSymbol;
        SHARE_SYMBOL = config.tokenConfig.vaultSymbol;
    }

    function setDeploymentConfig() public override {
        OWNER = msg.sender;
        ASSET = address(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
        MULTIPLI_FUND_MANAGER_WALLET = address(0); // intentionally invalid
    }
}

contract BaseDeploymentScriptStub is BaseDeployment {
    address public overrideAsset;
    address public overrideOwner;

    constructor(ConfigLib.NetworkConfig memory config) {
        INITIAL_LOCK_DEPOSIT_AMOUNT = 100 * (10 ** config.tokenConfig.decimals);
        MIN_DEPOSIT_AMOUNT = 10 * (10 ** config.tokenConfig.decimals);
        SHARE_NAME = config.tokenConfig.vaultSymbol;
        SHARE_SYMBOL = config.tokenConfig.vaultSymbol;
    }

    function setDeploymentConfig() public override {
        ASSET = overrideAsset != address(0)
            ? overrideAsset
            : address(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E); // fallback to mainnet
        OWNER = msg.sender;
        MULTIPLI_FUND_MANAGER_WALLET = address(0x123);
    }

    function setMockAsset(address asset) public {
        overrideAsset = asset;
    }

    function callSetDeploymentConfig() public {
        setDeploymentConfig();
    }

    function setOwner(address owner_) public {
        overrideOwner = owner_;
    }
}

abstract contract DeployXUSDCBaseTest is Test, Constants {
    BaseDeployment public deploymentScript;
    MultipliVault public vault;
    VariableVaultFee public feeContract;
    RolesAuthority public authority;
    IERC20 public asset;
    address public owner;
    VaultFundManager public fundManager;

    address public TOKEN_ADDRESS;
    uint256 EXPECTED_MIN_DEPOSIT_AMOUNT;
    ConfigLib.NetworkConfig config;

    function _initializeVault(ConfigLib.NetworkConfig memory _config) internal {
        config=_config;
        TOKEN_ADDRESS = _config.tokenConfig.token;
        EXPECTED_MIN_DEPOSIT_AMOUNT = 10*(10**_config.tokenConfig.decimals);
        vm.setEnv("IS_TEST", "true");

        if (!config.tokenConfig.isMock) {
            uint256 forkId = vm.createFork(config.rpcUrl);
            vm.selectFork(forkId);
        }

        // Ensure deployment config is populated before reading from script
        deploymentScript.setDeploymentConfig(); 
        owner = deploymentScript.OWNER();

        if (!_config.tokenConfig.isMock) {
            deal(TOKEN_ADDRESS, owner, 1000*(10 ** _config.tokenConfig.decimals)); // Fund owner on fork
        }

        vm.startPrank(owner);
        deploymentScript.run();
        vm.stopPrank();

        vault = MultipliVault(deploymentScript.vault());
        feeContract = VariableVaultFee(address(vault.feeContract()));
        authority = RolesAuthority(address(vault.authority()));
        asset = IERC20(vault.asset());
        fundManager = VaultFundManager(BaseDeployment(address(deploymentScript)).fundManager());
    }

    function testVaultMetadata() public view {
        assertEq(vault.name(), deploymentScript.SHARE_NAME());
        assertEq(vault.symbol(), deploymentScript.SHARE_SYMBOL());
        assertEq(vault.name(), config.tokenConfig.vaultSymbol);
        assertEq(vault.symbol(), config.tokenConfig.vaultSymbol);
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
        assertEq(token.symbol(), config.tokenConfig.assetSymbol);
        assertEq(token.decimals(), config.tokenConfig.decimals);
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
        assertEq(withdrawFee.feeAmount, 1e15);

        assertEq(uint8(instantWithdrawFee.feeType), uint8(IVariableVaultFee.FeeType.PERCENTAGE));
        assertEq(instantWithdrawFee.feeAmount, 5e15);

        assertEq(uint8(flashRedeemFee.feeType), uint8(IVariableVaultFee.FeeType.PERCENTAGE));
        assertEq(flashRedeemFee.feeAmount, 1e15);
        
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
     
        BrokenAssetScript script = new BrokenAssetScript(config);
        vm.expectRevert("ASSET cannot be empty");
        script.run();

    }

    function testRevertsIfInitialDepositIsZero() public {
        vm.setEnv("IS_TEST", "true");

        ZeroDepositScript script = new ZeroDepositScript(config);
        vm.expectRevert("INITIAL_LOCK_DEPOSIT_AMOUNT must be greater than 0");
        script.run();
    }

    function testRevertIfShareNameEmpty() public {
        EmptyNameScript script = new EmptyNameScript(config);
        vm.expectRevert("SHARE_NAME cannot be empty");
        script.run();
    }

    function testRevertIfShareSymbolEmpty() public {
        EmptySymbolScript script = new EmptySymbolScript(config);
        vm.expectRevert("SHARE_SYMBOL cannot be empty");
        script.run();
    }

    function testRevertIfMinDepositAmountIsZero() public {
        ZeroMinDepositScript script = new ZeroMinDepositScript(config);
        vm.expectRevert("MIN_DEPOSIT_AMOUNT must be greater than 0");
        script.run();
    }

    function testRevertIfFundManagerAddressIsZero() public {
        ZeroFundManagerScript script = new ZeroFundManagerScript(config);
        vm.expectRevert("MULTIPLI_FUND_MANAGER_WALLET cannot be empty");
        script.run();
    }

   function testValidateDeploymentConfigDirectly() public {
        BaseDeploymentScriptStub script = new BaseDeploymentScriptStub(config);
        script.callSetDeploymentConfig(); // sets config
        script.validateDeploymentConfig(); // now hits the public function directly
    }

    function testDeployWithBroadcast_False() public {
        vm.setEnv("IS_TEST", "true");

        address deployer = makeAddr("random");
        vm.startPrank(deployer);

        // Setup mock token
        MockERC20 mockToken = new MockERC20(config.tokenConfig.assetSymbol, config.tokenConfig.assetSymbol, config.tokenConfig.decimals);
        mockToken.mint(deployer, 1_000*(10 ** config.tokenConfig.decimals));

        // Use stub
        BaseDeploymentScriptStub script = new BaseDeploymentScriptStub(config);
        script.setMockAsset(address(mockToken));
        script.setOwner(deployer);
        script.callSetDeploymentConfig();
        script.run();

        // Validate vault deployed
        MultipliVault vault = MultipliVault(script.vault());
        assertEq(vault.totalSupply(), 100 * (10 ** config.tokenConfig.decimals));

        vm.stopPrank();
    }

    function testRevertsIfSenderNotDeployer() public {
        BaseDeploymentScriptStub script = new BaseDeploymentScriptStub(config);
        
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
