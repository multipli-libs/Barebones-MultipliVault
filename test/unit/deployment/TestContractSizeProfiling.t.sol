// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Import base contracts to measure their individual contributions
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AuthUpgradeable, Authority} from "src/base/AuthUpgradeable.sol";
import {VaultFeeUpgradeable} from "src/base/VaultFeeUpgradeable.sol";
import {FundMovementHelperUpgradeable} from "src/base/FundMovementHelperUpgradeable.sol";

import {MultipliVault} from "src/vault/MultipliVault.sol";
import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";



contract TestContractSizeProfiling is Test {
    uint256 constant SIZE_LIMIT = 24576; // 24KB

    function test_ProfileContractSizeContributions() public {
        console.log("=== CONTRACT SIZE PROFILING ===");
        console.log("");
        
        // Create mock asset for testing
        MockERC20 asset = new MockERC20("USDC", "USDC", 6);
        
        // Deploy and analyze each component
        _analyzeBaseContractSizes();
        _analyzeMultipliVaultSize();
        _suggestOptimizations();
    }
    
    function _analyzeBaseContractSizes() internal {
        console.log("=== BASE CONTRACTS ANALYSIS ===");
        
        // Create minimal contracts to measure base sizes
        MinimalERC4626 erc4626 = new MinimalERC4626();
        MinimalPausable pausable = new MinimalPausable();
        MinimalAuth auth = new MinimalAuth();
        MinimalVaultFee vaultFee = new MinimalVaultFee();
        MinimalFundMovement fundMovement = new MinimalFundMovement();
        
        console.log("ERC4626Upgradeable base:           %d bytes", address(erc4626).code.length);
        console.log("PausableUpgradeable base:          %d bytes", address(pausable).code.length);
        console.log("AuthUpgradeable base:              %d bytes", address(auth).code.length);
        console.log("VaultFeeUpgradeable base:          %d bytes", address(vaultFee).code.length);
        console.log("FundMovementHelperUpgradeable:     %d bytes", address(fundMovement).code.length);
        console.log("");
    }
    
    function _analyzeMultipliVaultSize() internal {
        console.log("=== MULTIPLI VAULT DETAILED BREAKDOWN ===");
        
        // Deploy the actual vault
        MultipliVault vault = new MultipliVault();
        uint256 totalSize = address(vault).code.length;
        
        console.log("Total MultipliVault Size:          %d bytes", totalSize);
        console.log("Size Limit:                        %d bytes", SIZE_LIMIT);
        console.log("Over Limit By:                     %d bytes", totalSize > SIZE_LIMIT ? totalSize - SIZE_LIMIT : 0);
        console.log("Percentage of Limit:               %d%%", (totalSize * 100) / SIZE_LIMIT);
        console.log("");
        
        // Estimate function contributions (rough approximation)
        _estimateFunctionContributions(totalSize);
    }
    
    function _estimateFunctionContributions(uint256 totalSize) internal view {
        console.log("=== ESTIMATED FUNCTION CONTRIBUTIONS ===");
        console.log("(Note: These are rough estimates based on typical function sizes)");
        console.log("");
        
        // Rough estimates based on function complexity
        uint256 erc4626Functions = 2000;    // deposit, mint, withdraw, redeem, preview functions
        uint256 redeemFunctions = 3000;     // requestRedeem, fulfillRedeem, cancelRedeem variants
        uint256 manageFunctions = 1500;     // manage single/multiple, authority checks
        uint256 feeCalculations = 1200;     // all fee calculation overrides
        uint256 balanceUpdates = 800;       // onUnderlyingBalanceUpdate, percentage calculations
        uint256 accessControl = 1000;       // pause, unpause, whitelisting functions
        uint256 viewFunctions = 600;        // pendingRedeemRequest, totalAssets, getters
        uint256 initAndUpgrade = 800;       // initialize, upgrade functions
        uint256 baseContracts = totalSize - (erc4626Functions + redeemFunctions + manageFunctions + 
                                           feeCalculations + balanceUpdates + accessControl + 
                                           viewFunctions + initAndUpgrade);
        
        console.log("ERC4626 Functions (~):             %d bytes", erc4626Functions);
        console.log("Redeem Functions (~):              %d bytes", redeemFunctions);
        console.log("Manage Functions (~):              %d bytes", manageFunctions);
        console.log("Fee Calculations (~):              %d bytes", feeCalculations);
        console.log("Balance Updates (~):               %d bytes", balanceUpdates);
        console.log("Access Control (~):                %d bytes", accessControl);
        console.log("View Functions (~):                %d bytes", viewFunctions);
        console.log("Init & Upgrade (~):                %d bytes", initAndUpgrade);
        console.log("Base Contracts & Overhead (~):    %d bytes", baseContracts);
        console.log("");
    }
    
    function _suggestOptimizations() internal view {
        console.log("=== OPTIMIZATION SUGGESTIONS ===");
        console.log("");
        console.log("HIGH IMPACT (will significantly reduce size):");
        console.log("1. Consolidate redeem functions using enum pattern");
        console.log("2. Extract common validation logic into internal functions");
        console.log("3. Use custom errors instead of string error messages");
        console.log("4. Consider removing or simplifying less critical functions");
        console.log("");
        console.log("MEDIUM IMPACT:");
        console.log("5. Optimize fee calculation functions (combine similar logic)");
        console.log("6. Simplify manage function overloads");
        console.log("7. Review if all inherited contract features are needed");
        console.log("");
        console.log("LOW IMPACT (fine-tuning):");
        console.log("8. Increase compiler optimization runs");
        console.log("9. Pack struct variables more efficiently");
        console.log("10. Use smaller data types where possible");
        console.log("");
    }
    
    function test_CompareOptimizedVsUnoptimized() public {
        console.log("=== OPTIMIZATION IMPACT ANALYSIS ===");
        console.log("");
        
        // Test with different compiler settings
        MultipliVault vault = new MultipliVault();
        uint256 currentSize = address(vault).code.length;
        
        console.log("Current Size:                      %d bytes", currentSize);
        console.log("Target Size (90%% of limit):        %d bytes", (SIZE_LIMIT * 90) / 100);
        console.log("Bytes to Remove:                   %d bytes", currentSize < ((SIZE_LIMIT * 90) / 100) ? 0 : currentSize - ((SIZE_LIMIT * 90) / 100));
        console.log("");
        
        // Suggest specific reductions needed
        uint256 targetReduction = currentSize > SIZE_LIMIT ? currentSize - SIZE_LIMIT + 1000 : 0;
        assertEq(targetReduction, 0, string(abi.encodePacked("CRITICAL: To deploy, must reduce by at least: ", targetReduction, " bytes")));
    }
}

// Minimal contracts to measure base sizes
contract MinimalERC4626 is ERC4626Upgradeable {
    function initialize() external initializer {
        __ERC4626_init(IERC20(address(0)));
    }
}

contract MinimalPausable is PausableUpgradeable {
    function initialize() external initializer {
        __Pausable_init();
    }
}

contract MinimalAuth is AuthUpgradeable {
    function initialize() external initializer {
        __Auth_init(address(0), Authority(address(0)));
    }
}

contract MinimalVaultFee is VaultFeeUpgradeable {
    function initialize() external initializer {
        __VaultFeeUpgreadable_init(IVariableVaultFee(address(0)));
    }
}

contract MinimalFundMovement is FundMovementHelperUpgradeable {
    function initialize() external initializer {
        __FundMovementHelper_init();
    }
}