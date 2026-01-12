// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {Users} from "../../utils/Types.sol";
import {Utils} from "../../utils/Utils.sol";
import {Events} from "../../utils/Events.sol";
import {Constants} from "../../utils/Constants.sol";
import {MockAuthority} from "../../mocks/MockAuthority.sol";

import {MultipliVault} from "../../../src/vault/MultipliVault.sol";
import {VaultFundManager} from "../../../src/managers/VaultFundManager.sol";
import {VariableVaultFee} from "../../../src/fees/VariableVaultFee.sol";
import {IVariableVaultFee} from "../../../src/interfaces/IVariableVaultFee.sol";
import {Authority} from "../../../src/base/AuthUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {ConfigLib} from "test/utils/ConfigLib.sol";
import {BaseNetworkTokenConfig} from "test/BaseNetworkTokenConfig.t.sol";

/// @notice Base test contract for VaultFundManager tests
abstract contract VaultFundManagerBase is Test, Events, Utils, Constants, BaseNetworkTokenConfig {
    using Math for uint256;

    // ========================================= VARIABLES =========================================
    Users internal users;

    // ====================================== TEST CONTRACTS =======================================
    IERC20 internal token;
    MultipliVault internal vault;
    VaultFundManager internal fundManager;
    Authority internal authority;
    VariableVaultFee internal feeContract;

    // Test addresses
    address internal recipient1;
    address internal recipient2;
    address internal nonWhitelistedRecipient;

    // Test amounts
    uint256 internal INITIAL_DEPOSIT;
    uint256 internal TEST_TRANSFER_AMOUNT;
    // ====================================== SET-UP FUNCTION ======================================
    function setUp() public virtual {
        super.setTokenNetworkConfig();
        INITIAL_DEPOSIT = getQuantizedValue(100_000); // 100K
        TEST_TRANSFER_AMOUNT = getQuantizedValue(50_000); // 50K
        uint256 forkId = vm.createFork({
            urlOrAlias: vm.envOr("TOKEN_RPC_URL", string(config.rpcUrl))
        });

        vm.selectFork(forkId);
        // USDC (https://subnets.avax.network/c-chain/token/0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E)

        if(config.env !=  ConfigLib.NetworkEnv.MAINNET){
            token = new MockERC20(config.tokenConfig.name, config.tokenConfig.assetSymbol, config.tokenConfig.decimals);
        } else {
            token = IERC20(config.tokenConfig.token);
        }


        // Label the base test contracts
        vm.label({account: address(token), newLabel: config.tokenConfig.assetSymbol});

        // Create fee recipient user
        (users.feeRecipient, users.feeRecipientKey) = makeAddrAndKey("feeRecipient");

        // Create test recipients
        recipient1 = makeAddr("recipient1");
        recipient2 = makeAddr("recipient2");
        nonWhitelistedRecipient = makeAddr("nonWhitelistedRecipient");

        // Create the vault admin
        users.admin = payable(makeAddr({name: "Admin"}));
        deal(address(token), address(users.admin), getQuantizedValue(1_000_000));

        vm.startPrank({msgSender: users.admin});
        deployVaultAndFundManager();

        // Create users for testing
        (users.bob, users.bobKey) = createUser("Bob");
        (users.alice, users.aliceKey) = createUser("Alice");

        // Setup permissions for fund manager operations
        setupFundManagerPermissions();

        vm.stopPrank();
    }

    // ====================================== HELPERS =======================================

    /// @dev Approves the protocol contracts to spend the user's tokens
    function approveProtocol(address from) internal {
        resetPrank({msgSender: from});
        token.approve({spender: address(vault), value: UINT256_MAX});
        vault.approve({spender: address(vault), value: UINT256_MAX});
    }

    /// @dev Generates a user, labels its address, funds it with test assets, and approves the protocol contracts
    function createUser(string memory name) internal returns (address payable, uint256) {
        (address user, uint256 key) = makeAddrAndKey(name);
        vm.deal({account: user, newBalance: 100 ether});
        deal({token: address(token), to: user, give: getQuantizedValue(1_000_000), adjust: true});
        approveProtocol({from: user});
        return (payable(user), key);
    }

    /// @dev Deploys the MultipliVault and VaultFundManager
    function deployVaultAndFundManager() internal {
        MultipliVault vaultImpl = new MultipliVault();

        bytes memory data =
            abi.encodeWithSelector(MultipliVault.initialize.selector, token, users.admin, config.tokenConfig.vaultName, config.tokenConfig.vaultSymbol);

        address proxy = Upgrades.deployUUPSProxy("MultipliVault.sol", data);
        vault = MultipliVault(payable(address(proxy)));

        // Deploy fee contract
        feeContract = new VariableVaultFee(users.admin);
        feeContract.registerAsset(
            address(token),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(1)}),
                instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 5e15}),
                depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
                flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e15}),
                feeRecipient: address(users.feeRecipient)
            })
        );
        vault.setFeeContract(feeContract);

        // Deploy authority
        authority = new MockAuthority(users.admin, Authority(address(0)));
        vault.setAuthority({newAuthority: authority});

        // Set admin role
        MockAuthority(address(authority)).setUserRole(users.admin, ADMIN_ROLE, true);

        // Deploy fund manager
        fundManager = new VaultFundManager(payable(address(vault)));

        // Whitelist recipients for fund transfers
        vault.whitelistFundTransferRecipient(recipient1, true);
        vault.whitelistFundTransferRecipient(recipient2, true);

        // Fund the fund manager for redemption tests
        deal({token: address(token), to: address(fundManager), give: INITIAL_DEPOSIT, adjust: true});

        vm.label({account: address(vault), newLabel: "MultipliVault"});
        vm.label({account: address(fundManager), newLabel: "VaultFundManager"});
        vm.label({account: address(feeContract), newLabel: "VariableVaultFee"});
        vm.label({account: address(authority), newLabel: "MockAuthority"});
    }

    /// @dev Sets up permissions for fund manager operations
    function setupFundManagerPermissions() internal {
        MockAuthority auth = MockAuthority(address(authority));

        vm.startPrank(users.admin);
        MockAuthority(address(authority)).setUserRole(users.alice, FUND_MANAGER_ROLE, true);
        MockAuthority(address(authority)).setUserRole(address(fundManager), FUND_MANAGER_CONTRACT_ROLE, true);

        // permissions for fund manager to call fund manager methods via manage
        auth.setRoleCapability(
            FUND_MANAGER_ROLE, address(vault), bytes4(abi.encodeWithSignature("manage(address,bytes,uint256)")), true
        ); // there are two manage methods, so manually adding in the signature
        auth.setRoleCapability(FUND_MANAGER_ROLE, address(fundManager), fundManager.removeFundsFromVault.selector, true);
        auth.setRoleCapability(
            FUND_MANAGER_ROLE, address(fundManager), fundManager.updateUnderlyingBalance.selector, true
        );
        auth.setRoleCapability(
            FUND_MANAGER_ROLE, address(fundManager), fundManager.addFundsAndFulfillRedeem.selector, true
        );

        // Fund manager contract permissions to call vault methods
        auth.setRoleCapability(
            FUND_MANAGER_CONTRACT_ROLE, address(vault), vault.onUnderlyingBalanceUpdate.selector, true
        );
        auth.setRoleCapability(FUND_MANAGER_CONTRACT_ROLE, address(vault), vault.removeFunds.selector, true);
        auth.setRoleCapability(FUND_MANAGER_CONTRACT_ROLE, address(vault), vault.fulfillRedeem.selector, true);

        vm.stopPrank();
    }

    /// @dev Creates a redemption request for testing
    function createRedemptionRequest(address user, uint256 shares) internal {
        resetPrank({msgSender: user});
        vault.requestRedeem(shares, user, user);
    }

    /// @dev Calls fund manager methods via vault's manage function
    function callViaManage(address target, bytes memory data) internal {
        resetPrank({msgSender: users.admin});
        vault.manage(target, data, 0);
    }

    /// @dev Moves assets from vault to create aggregated balance
    function moveAssetsFromVault(uint256 assets) internal {
        resetPrank({msgSender: users.admin});
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, users.admin, assets);

        MockAuthority(address(vault.authority())).setRoleCapability(
            ADMIN_ROLE, address(token), IERC20.transfer.selector, true
        );

        vault.manage(address(token), data, 0);
    }

    /// @dev Updates underlying balance directly
    function updateUnderlyingBalance(uint256 assets) internal {
        resetPrank({msgSender: users.admin});
        vault.onUnderlyingBalanceUpdate(assets);
    }

    /// @dev Deposits assets into vault for a user
    function depositForUser(address user, uint256 amount) internal {
        resetPrank({msgSender: user});
        vault.deposit(amount, user);
    }

    function unpauseVault() internal {
        resetPrank({msgSender: users.admin});
        vault.unpause();
    }
}
