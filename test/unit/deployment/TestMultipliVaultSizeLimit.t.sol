// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {MultipliVault} from "src/vault/MultipliVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract TestMultipliVaultSizeLimit is Test {
    // Ethereum mainnet contract size limit (EIP-170)
    uint256 constant SPURIOUS_DRAGON_SIZE_LIMIT = 24576; // 24KB
    
    // Recommended limits for good practices
    uint256 constant RECOMMENDED_LIMIT = 20480; // 20KB
    uint256 constant WARNING_LIMIT = 22528; // 22KB
    uint256 constant CONSERVATIVE_LIMIT = 18432; // 18KB (75% of hard limit)
    
    // Contract deployment parameters
    address constant OWNER = address(0x1234567890123456789012345678901234567890);
    string constant SHARE_NAME = "MultipliUSDCVault";
    string constant SHARE_SYMBOL = "xUSDC";
    
    MockERC20 asset;
    
    function setUp() public {
        // Deploy mock asset for testing
        asset = new MockERC20("USDC", "USDC", 6);
        vm.label(address(asset), "USDC");
        vm.label(OWNER, "Owner");
    }
    
    function test_MultipliVault_ContractSizeAnalysis() public {
        console.log("=== MULTIPLI VAULT SIZE ANALYSIS ===");
        console.log("");
        
        // Deploy using the exact same pattern as the deployment script
        console.log("Deploying MultipliVault...");
        bytes memory data = abi.encodeWithSelector(
            MultipliVault.initialize.selector, 
            IERC20(address(asset)), 
            OWNER, 
            SHARE_NAME, 
            SHARE_SYMBOL
        );
        
        address proxy = Upgrades.deployUUPSProxy("MultipliVault.sol", data);
        MultipliVault vault = MultipliVault(payable(address(proxy)));
        
        console.log("Multipli proxy deployed at: %s", address(vault));
        console.log("");
        
        // Get the implementation address
        address implementation = _getImplementationAddress(address(vault));
        console.log("Implementation address: %s", implementation);
        
        // Analyze sizes
        uint256 proxySize = _getContractSize(address(vault));
        uint256 implSize = _getContractSize(implementation);
        
        _analyzeContractSize("MultipliVault Proxy", address(vault), proxySize);
        _analyzeContractSize("MultipliVault Implementation", implementation, implSize);
        
        console.log("");
        console.log("=== DEPLOYMENT SUMMARY ===");
        console.log("Total Deployment Size:   %d bytes (Proxy + Implementation)", proxySize + implSize);
        console.log("Proxy Size:              %d bytes", proxySize);
        console.log("Implementation Size:     %d bytes", implSize);
        console.log("");
        
        // Test contract functionality to ensure it's working
        _testBasicVaultFunctionality(vault);
        
        // Assertions
        assertTrue(implSize < SPURIOUS_DRAGON_SIZE_LIMIT, "MultipliVault implementation exceeds Ethereum size limit");
        assertTrue(proxySize < SPURIOUS_DRAGON_SIZE_LIMIT, "MultipliVault proxy exceeds Ethereum size limit");
        
        // Warnings
        if (implSize > WARNING_LIMIT) {
            console.log("WARNING: Implementation size is very close to the limit!");
            console.log("Consider optimization before adding more features.");
        } else if (implSize > RECOMMENDED_LIMIT) {
            console.log("NOTICE: Implementation size exceeds recommended best practices.");
            console.log("Consider code optimization for future scalability.");
        } else if (implSize > CONSERVATIVE_LIMIT) {
            console.log("INFO: Implementation size is approaching recommended limits.");
            console.log("Monitor size growth in future upgrades.");
        } else {
            console.log("GOOD: Contract sizes are well within safe limits.");
        }
    }
    
    function test_MultipliVault_SizeGrowthProjection() public {
        console.log("=== SIZE GROWTH PROJECTION ===");
        console.log("");
        
        // Deploy vault
        bytes memory data = abi.encodeWithSelector(
            MultipliVault.initialize.selector, 
            IERC20(address(asset)), 
            OWNER, 
            SHARE_NAME, 
            SHARE_SYMBOL
        );
        
        address proxy = Upgrades.deployUUPSProxy("MultipliVault.sol", data);
        address implementation = _getImplementationAddress(proxy);
        uint256 currentSize = _getContractSize(implementation);
        
        console.log("Current Implementation Size: %d bytes", currentSize);
        console.log("");
        console.log("Growth Capacity Analysis:");
        console.log("- Conservative Limit:  %d bytes (%x bytes remaining)", CONSERVATIVE_LIMIT, CONSERVATIVE_LIMIT > currentSize ? CONSERVATIVE_LIMIT - currentSize: 0);
        console.log("- Recommended Limit:   %d bytes (%s bytes remaining)", RECOMMENDED_LIMIT, RECOMMENDED_LIMIT > currentSize? RECOMMENDED_LIMIT - currentSize: 0);
        console.log("- Warning Threshold:   %d bytes (%s bytes remaining)", WARNING_LIMIT, WARNING_LIMIT > currentSize? WARNING_LIMIT - currentSize: 0);
        console.log("- Hard Limit:          %d bytes (%s bytes remaining)", SPURIOUS_DRAGON_SIZE_LIMIT, SPURIOUS_DRAGON_SIZE_LIMIT > currentSize? SPURIOUS_DRAGON_SIZE_LIMIT - currentSize: 0);
        console.log("");

        assertLt(currentSize, SPURIOUS_DRAGON_SIZE_LIMIT, string(abi.encodePacked("Cannot deploy contract with current size. Current size: ", currentSize)));
        
        // Estimate bytes per function (rough approximation)
        uint256 avgBytesPerFunction = 200; // Conservative estimate
        uint256 functionsRemaining = (SPURIOUS_DRAGON_SIZE_LIMIT - currentSize) / avgBytesPerFunction;
        
        console.log("Estimated Functions Remaining: ~%d (at %d bytes per function)", functionsRemaining, avgBytesPerFunction);
        console.log("");
        
        // Future upgrade recommendations
        if (currentSize > CONSERVATIVE_LIMIT) {
            console.log("RECOMMENDATION: Consider splitting functionality before next major upgrade");
        } else if (currentSize > (CONSERVATIVE_LIMIT * 90) / 100) {
            console.log("RECOMMENDATION: Plan for potential contract splitting in future versions");
        } else {
            console.log("RECOMMENDATION: Current size allows for significant feature additions");
        }
    }
    
    function _analyzeContractSize(string memory name, address contractAddr, uint256 size) internal view {
        console.log("%s Analysis:", name);
        console.log("- Address:              %s", contractAddr);
        console.log("- Size:                 %d bytes", size);
        console.log("- Size (KB):            %d.%d KB", size / 1024, (size % 1024) / 102);
        console.log("- Percentage of Limit:  %d.%d%%", (size * 100) / SPURIOUS_DRAGON_SIZE_LIMIT, ((size * 1000) / SPURIOUS_DRAGON_SIZE_LIMIT) % 10);
        console.log("- Remaining Capacity:   %d bytes", SPURIOUS_DRAGON_SIZE_LIMIT - size);
        
        // Status indicator
        string memory status;
        string memory indicator;
        if (size > SPURIOUS_DRAGON_SIZE_LIMIT) {
            status = "CRITICAL - EXCEEDS LIMIT";
            indicator = "[CRITICAL]";
        } else if (size > WARNING_LIMIT) {
            status = "WARNING - NEAR LIMIT";
            indicator = "[WARNING]";
        } else if (size > RECOMMENDED_LIMIT) {
            status = "CAUTION - ABOVE RECOMMENDED";
            indicator = "[CAUTION]";
        } else {
            status = "GOOD - WITHIN LIMITS";
            indicator = "[GOOD]";
        }
        
        console.log("- Status:              %s %s", indicator, status);
        console.log("");
    }
    
    function _getContractSize(address contractAddr) internal view returns (uint256) {
        return contractAddr.code.length;
    }
    
    function _getImplementationAddress(address proxy) internal view returns (address) {
        // EIP-1967 implementation slot
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 slot = vm.load(proxy, IMPLEMENTATION_SLOT);
        return address(uint160(uint256(slot)));
    }
    
    function _testBasicVaultFunctionality(MultipliVault vault) internal {
        console.log("Testing basic vault functionality...");
        
        // Test basic view functions
        assertEq(vault.name(), SHARE_NAME);
        assertEq(vault.symbol(), SHARE_SYMBOL);
        assertEq(address(vault.asset()), address(asset));
        assertEq(vault.owner(), OWNER);
        
        // Test initial state
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.aggregatedUnderlyingBalances(), 0);
        
        console.log("[PASS] Basic functionality test passed");
        console.log("");
    }
}