// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {Authority} from "src/base/AuthUpgradeable.sol";
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


/// @notice Base test contract with common logic needed by all tests.

abstract contract BaseTest is Test, Events, Utils, Constants {
    using Math for uint256;

    // ========================================= VARIABLES =========================================
    Users internal users;

    // ====================================== TEST CONTRACTS =======================================
    IERC20 internal usdc;
    MultipliVault internal depositVault;
    Authority internal authority;
    VariableVaultFee internal feeContract;

    // ====================================== SET-UP FUNCTION ======================================
    function setUp() public virtual {
        vm.createSelectFork({
            blockNumber: 62_181_442, // May-17-2025 02:21:00 AM UTC
            urlOrAlias: vm.envOr("AVAX_C_RPC_URL", string("https://api.avax.network/ext/bc/C/rpc"))
        });

        // USDC (https://subnets.avax.network/c-chain/token/0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E)
        usdc = IERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);

        // Label the base test contracts.
        vm.label({account: address(usdc), newLabel: "USDC"});

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

    /// @dev Approves the protocol contracts to spend the user's USDC.
    function approveProtocol(address from) internal {
        resetPrank({msgSender: from});
        usdc.approve({spender: address(depositVault), value: UINT256_MAX});
        depositVault.approve({spender: address(depositVault), value: UINT256_MAX});
    }

    /// @dev Generates a user, labels its address, funds it with test assets, and approves the protocol contracts.
    function createUser(string memory name) internal returns (address payable, uint256) {
        (address user, uint256 key) = makeAddrAndKey(name);
        vm.deal({account: user, newBalance: 100 ether});
        deal({token: address(usdc), to: user, give: 1_000_000e6, adjust: true});
        approveProtocol({from: user});
        return (payable(user), key);
        vm.label(user, "name");
    }

    /// @dev Deploys the MultipliVault
    function deployDepositVault() internal {
        bytes memory data =
            abi.encodeWithSelector(MultipliVault.initialize.selector, usdc, users.admin, "MultipliUSDCVault", "xUSDC");

        address proxy = Upgrades.deployUUPSProxy("MultipliVault.sol", data);
        depositVault = MultipliVault(payable(address(proxy)));

        feeContract = new VariableVaultFee(users.admin);
        feeContract.registerAsset(
            address(usdc),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 1e6}),
                instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 5e15}),
                depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
                flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e15}),
                feeRecipient: address(users.feeRecipient)
            })
        );
        depositVault.setFeeContract(feeContract);

        authority = new MockAuthority(users.admin, Authority(address(0)));
        depositVault.setAuthority({newAuthority: authority});

        MockAuthority(address(authority)).setUserRole(users.admin, ADMIN_ROLE, true);

        vm.label({account: address(depositVault), newLabel: "MultipliUSDCVault"});
    }

    function moveAssetsFromVault(uint256 assets) internal {
        vm.startPrank({msgSender: users.admin});
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, users.admin, assets);

        MockAuthority(address(depositVault.authority())).setRoleCapability(
            ADMIN_ROLE, address(usdc), IERC20.transfer.selector, true
        );

        depositVault.manage(address(usdc), data, 0);

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
