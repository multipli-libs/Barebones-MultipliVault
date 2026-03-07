// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

import { Authority } from "@solmate/auth/Auth.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {Users} from "../../utils/Types.sol";
import {Utils} from "../../utils/Utils.sol";
import {Events} from "../../utils/Events.sol";
import {Constants} from "../../utils/Constants.sol";
import {MockAuthority} from "../../mocks/MockAuthority.sol";

import {MultipliVault} from "src/vault/MultipliVault.sol";

import {VariableVaultFee} from "src/fees/VariableVaultFee.sol";

import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";

import {BaseNetworkTokenConfig} from "test/BaseNetworkTokenConfig.t.sol";

import {ConfigLib} from "test/utils/ConfigLib.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";

/// @notice Base test contract with common logic needd by all tests.

abstract contract BaseTest is Test, Events, Utils, Constants, BaseNetworkTokenConfig {
    using Math for uint256;
     struct TestCase {
        string network;
        string env;
        string token;
    }

    // ========================================= VARIABLES =========================================
    Users internal users;
    TestCase[] internal testCases;

    // ====================================== TEST CONTRACTS =======================================
    IERC20 internal token;
    MultipliVault internal depositVault;
    Authority internal authority;
    VariableVaultFee internal feeContract;

    // ====================================== SET-UP FUNCTION ======================================
    function setUp() public virtual {
        super.setTokenNetworkConfig();

        uint256 forkId = vm.createFork({
            urlOrAlias: config.rpcUrl
        });
        vm.selectFork(forkId);

        if(config.env !=  ConfigLib.NetworkEnv.MAINNET){
            token = new MockERC20(config.tokenConfig.name, config.tokenConfig.assetSymbol, config.tokenConfig.decimals);
        } else{
            token = IERC20(config.tokenConfig.token);
        }

       

        //Label the base test contracts.
        vm.label(address(token), "xTOKEN");

        // Create fee recipient user
        (users.feeRecipient, users.feeRecipientKey) = makeAddrAndKey("feeRecipient");

        // Create the vault admin.
        users.admin = payable(makeAddr({name: "Admin"}));
        vm.startPrank({msgSender: users.admin});

        deployDepositVault();

        // Create users for testing.
        (users.bob, users.bobKey) = createUser("Bob");
        (users.alice, users.aliceKey) = createUser("Alice");
    }

    // ====================================== HELPERS =======================================

    /// @dev Approves the protocol contracts to spend the user's token.
    function approveProtocol(address from) internal {
        resetPrank({msgSender: from});
        token.approve({spender: address(depositVault), value: UINT256_MAX});
        depositVault.approve({spender: address(depositVault), value: UINT256_MAX});
    }

    /// @dev Generates a user, labels its address, funds it with test assets, and approves the protocol contracts.
    function createUser(string memory name) internal returns (address payable, uint256) {
        (address user, uint256 key) = makeAddrAndKey(name);
        vm.deal({account: user, newBalance: 100 ether});
        uint256 decimals = config.tokenConfig.decimals;
        deal(address(token), user, 1_000_000 * (10 ** decimals), true);

        approveProtocol({from: user});
        vm.label(user, name);
        return (payable(user), key);
    }

    /// @dev Deploys the MultipliVault
    function deployDepositVault() internal {
        bytes memory data = abi.encodeWithSelector(
            MultipliVault.initialize.selector,
            token,
            users.admin,
            config.tokenConfig.vaultName,
            config.tokenConfig.vaultSymbol
        );

        address proxy = Upgrades.deployUUPSProxy("MultipliVault.sol", data);
        depositVault = MultipliVault(payable(address(proxy)));

        feeContract = new VariableVaultFee(users.admin);
        uint8 decimals = config.tokenConfig.decimals;
        feeContract.registerAsset(
            address(token),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({
                    feeType: IVariableVaultFee.FeeType.FLAT,
                    feeAmount: 10 ** decimals
                }),
                instantWithdrawalFee: IVariableVaultFee.FeeConfig({
                    feeType: IVariableVaultFee.FeeType.PERCENTAGE,
                    feeAmount: 5e15
                }),
                depositFee: IVariableVaultFee.FeeConfig({
                    feeType: IVariableVaultFee.FeeType.FLAT,
                    feeAmount: 0
                }),
                flashRedeemFee: IVariableVaultFee.FeeConfig({
                    feeType: IVariableVaultFee.FeeType.PERCENTAGE,
                    feeAmount: 1e15
                }),
                feeRecipient: users.feeRecipient
            })
        );
        depositVault.setFeeContract(feeContract);

        authority = new MockAuthority(users.admin, Authority(address(0)));
        depositVault.setAuthority({newAuthority: authority});

        MockAuthority(address(authority)).setUserRole(users.admin, ADMIN_ROLE, true);

        vm.label({account: address(depositVault), newLabel: config.tokenConfig.vaultName});
    }

    function moveAssetsFromVault(uint256 assets) internal {
        vm.startPrank({msgSender: users.admin});
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, users.admin, assets);

        MockAuthority(address(depositVault.authority())).setRoleCapability(
            ADMIN_ROLE, address(token), IERC20.transfer.selector, true
        );

        depositVault.manage(address(token), data, 0);

        vm.stopPrank();
    }

    function updateUnderlyingBalance(uint256 assets) internal {
        vm.startPrank({msgSender: users.admin});
        depositVault.onUnderlyingBalanceUpdate(assets);
        vm.stopPrank();
    }

    function unpauseVault() internal {
        vm.startPrank(users.admin);
        depositVault.unpause();
        vm.stopPrank();
    }
}
