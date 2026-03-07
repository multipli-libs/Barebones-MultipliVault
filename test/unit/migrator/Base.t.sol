// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

import { Authority } from "@solmate/auth/Auth.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {Users} from "../../utils/Types.sol";
import {Utils} from "../../utils/Utils.sol";
import {Events} from "../../utils/Events.sol";
import {Constants} from "../../utils/Constants.sol";
import {MockAuthority} from "../../mocks/MockAuthority.sol";

import {MultipliVault} from "src/vault/MultipliVault.sol";
import {MultipliMigrator} from "src/migrator/MultipliMigrator.sol";

import {VariableVaultFee} from "src/fees/VariableVaultFee.sol";
import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";
import {ConfigLib} from "test/utils/ConfigLib.sol";
import {BaseNetworkTokenConfig} from "test/BaseNetworkTokenConfig.t.sol";

/// @notice Base test contract for MultipliMigrator tests
abstract contract MigratorBaseTest is Test, Events, Utils, Constants, BaseNetworkTokenConfig {
    using Math for uint256;

    // ========================================= VARIABLES =========================================
    Users internal users;
    address operator; // user performing the actions on the migrator contract

    // ====================================== TEST CONTRACTS =======================================
    IERC20 internal token;
    MultipliVault internal vault;
    MultipliMigrator internal migrator;
    Authority internal authority;
    VariableVaultFee internal feeContract;

    // ====================================== SET-UP FUNCTION ======================================
    function setUp() public virtual {
        super.setTokenNetworkConfig();

        uint256 forkId = vm.createFork({
            urlOrAlias: config.rpcUrl
        });
        vm.selectFork(forkId);

        // Token
         if(config.env !=  ConfigLib.NetworkEnv.MAINNET){
            token = new MockERC20(config.tokenConfig.name, config.tokenConfig.assetSymbol, config.tokenConfig.decimals);
        } else {
            token = IERC20(config.tokenConfig.token);
        }

        vm.label({account: address(token), newLabel: "xTOKEN"});

        // Create fee recipient user
        (users.feeRecipient, users.feeRecipientKey) = makeAddrAndKey("feeRecipient");

        // Create the vault admin.
        users.admin = payable(makeAddr({name: "Admin"}));
        deal(address(token), users.admin, getQuantizedValue(1_000_000));
        vm.startPrank({msgSender: users.admin});

        deployVault();
        deployMigrator();

        // Create users for testing.
        (users.bob, users.bobKey) = createUser("Bob");
        (users.alice, users.aliceKey) = createUser("Alice");
        
        // Create operator user for migrator
        (operator, ) = createUser("Operator");
        
        vm.stopPrank();
    }

    // ====================================== HELPERS =======================================

    function approveProtocol(address from) internal {
        resetPrank({msgSender: from});
        token.approve({spender: address(vault), value: UINT256_MAX});
        vault.approve({spender: address(vault), value: UINT256_MAX});
    }

    function createUser(string memory name) internal returns (address payable, uint256) {
        (address user, uint256 key) = makeAddrAndKey(name);
        vm.deal({account: user, newBalance: 100 ether});
        deal({token: address(token), to: user, give: getQuantizedValue(1_000_000), adjust: true});
        approveProtocol({from: user});
        vm.label(user, name);
        return (payable(user), key);
    }

    function deployVault() internal {
        bytes memory data = abi.encodeWithSelector(
            MultipliVault.initialize.selector,
            token,
            users.admin,
            config.tokenConfig.vaultName,
            config.tokenConfig.vaultSymbol
        );

        address proxy = Upgrades.deployUUPSProxy("MultipliVault.sol", data);
        vault = MultipliVault(payable(address(proxy)));

        feeContract = new VariableVaultFee(users.admin);
        uint8 decimals = config.tokenConfig.decimals;
        feeContract.registerAsset(
            address(token),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 10 ** decimals}),
                instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 5e15}),
                depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
                flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e15}),
                feeRecipient: address(users.feeRecipient)
            })
        );
        vault.setFeeContract(feeContract);

        authority = new MockAuthority(users.admin, Authority(address(0)));
        vault.setAuthority({newAuthority: authority});

        MockAuthority(address(authority)).setUserRole(users.admin, ADMIN_ROLE, true);

        vm.label({account: address(vault), newLabel: config.tokenConfig.vaultName});
    }

    function deployMigrator() internal {
        migrator = new MultipliMigrator(users.admin, address(vault));
        
        // Give migrator admin permissions on vault
        MockAuthority(address(authority)).setUserRole(address(migrator), ADMIN_ROLE, true);
        MockAuthority(address(authority)).setRoleCapability(ADMIN_ROLE,
            address(vault),
            vault.onUnderlyingBalanceUpdate.selector,
            true
        );
        MockAuthority(address(authority)).setRoleCapability(ADMIN_ROLE,
            address(vault),
            vault.adminMint.selector,
            true
        );
        
        vm.label({account: address(migrator), newLabel: "MultipliMigrator"});
    }

    /// @dev Sets up the vault with some initial underlying balance
    function setupVaultWithUnderlyingBalance(uint256 underlyingBalance) internal {
        vm.startPrank(users.admin);
        vault.onUnderlyingBalanceUpdate(underlyingBalance);
        vm.stopPrank();
    }

    /// @dev Adds user to migrator allowlist
    function addToAllowList(address user) internal {
        vm.startPrank(users.admin);
        migrator.updateAllowList(user, true);
        vm.stopPrank();
    }

    /// @dev Removes user from migrator allowlist
    function removeFromAllowList(address user) internal {
        vm.startPrank(users.admin);
        migrator.updateAllowList(user, false);
        vm.stopPrank();
    }

    /// @dev Moves assets from vault for testing
    function moveAssetsFromVault(uint256 assets) internal {
        vm.startPrank({msgSender: users.admin});
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, users.admin, assets);

        MockAuthority(address(vault.authority())).setRoleCapability(
            ADMIN_ROLE, address(token), IERC20.transfer.selector, true
        );
        vault.manage(address(token), data, 0);
        vm.stopPrank();
    }

    function updateUnderlyingBalance(uint256 assets) internal {
        vm.startPrank({msgSender: users.admin});
        vault.onUnderlyingBalanceUpdate(assets);
        vm.stopPrank();
    }

    function unpauseVault() internal {
        vm.startPrank(users.admin);
        vault.unpause();
        vm.stopPrank();
    }
}
