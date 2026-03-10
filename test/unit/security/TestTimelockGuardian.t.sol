// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {TimelockGuardian} from "src/security/TimelockGuardian.sol";

/// @notice Mock vault that records calls and supports pause
contract MockVault {
    bool public paused;
    address public newAuthority;
    address public newOwnerAddr;

    function pause() external {
        paused = true;
    }

    function setAuthority(address _authority) external {
        newAuthority = _authority;
    }

    function transferOwnership(address _owner) external {
        newOwnerAddr = _owner;
    }
}

contract TestTimelockGuardian is Test {
    TimelockGuardian internal guardian;
    MockVault internal mockVault;

    address internal admin;
    address internal guardianAddr;
    address internal attacker;

    uint256 internal constant TIMELOCK_DELAY = 48 hours;
    uint256 internal constant GRACE_PERIOD = 14 days;

    event OperationProposed(bytes32 indexed opHash, address indexed target, uint256 executeAfter);
    event OperationExecuted(bytes32 indexed opHash);
    event OperationCancelled(bytes32 indexed opHash);
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);
    event AdminTransferProposed(address indexed currentAdmin, address indexed newAdmin);
    event GuardianTransferred(address indexed oldGuardian, address indexed newGuardian);

    function setUp() public {
        admin = makeAddr("admin");
        guardianAddr = makeAddr("guardian");
        attacker = makeAddr("attacker");

        mockVault = new MockVault();
        guardian = new TimelockGuardian(address(mockVault), admin, guardianAddr);
    }

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    function test_constructor_SetsImmutables() public view {
        assertEq(guardian.vault(), address(mockVault));
        assertEq(guardian.admin(), admin);
        assertEq(guardian.guardian(), guardianAddr);
    }

    function test_constructor_RevertsOnZeroVault() public {
        vm.expectRevert(TimelockGuardian.TimelockGuardian__ZeroAddress.selector);
        new TimelockGuardian(address(0), admin, guardianAddr);
    }

    function test_constructor_RevertsOnZeroAdmin() public {
        vm.expectRevert(TimelockGuardian.TimelockGuardian__ZeroAddress.selector);
        new TimelockGuardian(address(mockVault), address(0), guardianAddr);
    }

    function test_constructor_RevertsOnZeroGuardian() public {
        vm.expectRevert(TimelockGuardian.TimelockGuardian__ZeroAddress.selector);
        new TimelockGuardian(address(mockVault), admin, address(0));
    }

    function test_constructor_Constants() public view {
        assertEq(guardian.TIMELOCK_DELAY(), TIMELOCK_DELAY);
        assertEq(guardian.GRACE_PERIOD(), GRACE_PERIOD);
    }

    // ──────────────────────────────────────────────
    //  Propose
    // ──────────────────────────────────────────────

    function test_propose_Success() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));

        vm.prank(admin);
        bytes32 opHash = guardian.propose(data);

        (uint256 executeAfter, bool exists) = guardian.pendingOps(opHash);
        assertTrue(exists);
        assertEq(executeAfter, block.timestamp + TIMELOCK_DELAY);
    }

    function test_propose_EmitsEvent() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));

        bytes32 expectedHash = keccak256(abi.encode(address(mockVault), data, block.timestamp));
        uint256 expectedExecuteAfter = block.timestamp + TIMELOCK_DELAY;

        vm.expectEmit(true, true, true, true);
        emit OperationProposed(expectedHash, address(mockVault), expectedExecuteAfter);

        vm.prank(admin);
        guardian.propose(data);
    }

    function test_propose_RevertsWhenNotAdmin() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));

        vm.prank(attacker);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OnlyAdmin.selector);
        guardian.propose(data);
    }

    function test_propose_RevertsWhenGuardianCalls() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));

        vm.prank(guardianAddr);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OnlyAdmin.selector);
        guardian.propose(data);
    }

    function test_propose_RevertsOnDuplicateInSameBlock() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));

        vm.startPrank(admin);
        guardian.propose(data);

        vm.expectRevert(TimelockGuardian.TimelockGuardian__OperationAlreadyPending.selector);
        guardian.propose(data);
        vm.stopPrank();
    }

    function test_propose_AllowsSameDataAtDifferentTimestamps() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));

        vm.prank(admin);
        bytes32 hash1 = guardian.propose(data);

        // Different block.timestamp produces different hash
        vm.warp(block.timestamp + 1);

        vm.prank(admin);
        bytes32 hash2 = guardian.propose(data);

        assertNotEq(hash1, hash2);
    }

    // ──────────────────────────────────────────────
    //  Execute
    // ──────────────────────────────────────────────

    function test_execute_SuccessAfterDelay() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));
        uint256 proposedAt = block.timestamp;

        vm.prank(admin);
        bytes32 opHash = guardian.propose(data);

        // Warp past timelock
        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.prank(admin);
        guardian.execute(data, proposedAt);

        // Verify the call went through
        assertEq(mockVault.newAuthority(), address(0xBEEF));

        // Op should be deleted
        (, bool exists) = guardian.pendingOps(opHash);
        assertFalse(exists);
    }

    function test_execute_EmitsEvent() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));
        uint256 proposedAt = block.timestamp;

        vm.prank(admin);
        bytes32 opHash = guardian.propose(data);

        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.expectEmit(true, true, true, true);
        emit OperationExecuted(opHash);

        vm.prank(admin);
        guardian.execute(data, proposedAt);
    }

    function test_execute_RevertsBeforeDelay() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));
        uint256 proposedAt = block.timestamp;

        vm.prank(admin);
        guardian.propose(data);

        // Warp to 1 second before timelock expires
        vm.warp(block.timestamp + TIMELOCK_DELAY - 1);

        vm.prank(admin);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__TimelockNotReady.selector);
        guardian.execute(data, proposedAt);
    }

    function test_execute_RevertsAfterGracePeriod() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));
        uint256 proposedAt = block.timestamp;

        vm.prank(admin);
        guardian.propose(data);

        // Warp past grace period
        vm.warp(block.timestamp + TIMELOCK_DELAY + GRACE_PERIOD + 1);

        vm.prank(admin);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OperationExpired.selector);
        guardian.execute(data, proposedAt);
    }

    function test_execute_SuccessAtExactGraceBoundary() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));
        uint256 proposedAt = block.timestamp;

        vm.prank(admin);
        guardian.propose(data);

        // Warp to exact end of grace period (still valid)
        vm.warp(block.timestamp + TIMELOCK_DELAY + GRACE_PERIOD);

        vm.prank(admin);
        guardian.execute(data, proposedAt);

        assertEq(mockVault.newAuthority(), address(0xBEEF));
    }

    function test_execute_RevertsWhenNotAdmin() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));
        uint256 proposedAt = block.timestamp;

        vm.prank(admin);
        guardian.propose(data);

        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.prank(attacker);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OnlyAdmin.selector);
        guardian.execute(data, proposedAt);
    }

    function test_execute_RevertsWhenNotPending() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));

        vm.prank(admin);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OperationNotPending.selector);
        guardian.execute(data, block.timestamp);
    }

    function test_execute_RevertsOnReplay() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));
        uint256 proposedAt = block.timestamp;

        vm.prank(admin);
        guardian.propose(data);

        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.startPrank(admin);
        guardian.execute(data, proposedAt);

        // Second execute with same params should fail
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OperationNotPending.selector);
        guardian.execute(data, proposedAt);
        vm.stopPrank();
    }

    function test_execute_TransferOwnership() public {
        address newOwner = makeAddr("newOwner");
        bytes memory data = abi.encodeWithSelector(MockVault.transferOwnership.selector, newOwner);
        uint256 proposedAt = block.timestamp;

        vm.prank(admin);
        guardian.propose(data);

        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.prank(admin);
        guardian.execute(data, proposedAt);

        assertEq(mockVault.newOwnerAddr(), newOwner);
    }

    // ──────────────────────────────────────────────
    //  Cancel
    // ──────────────────────────────────────────────

    function test_cancel_Success() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));

        vm.prank(admin);
        bytes32 opHash = guardian.propose(data);

        vm.prank(guardianAddr);
        guardian.cancel(opHash);

        (, bool exists) = guardian.pendingOps(opHash);
        assertFalse(exists);
    }

    function test_cancel_EmitsEvent() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));

        vm.prank(admin);
        bytes32 opHash = guardian.propose(data);

        vm.expectEmit(true, true, true, true);
        emit OperationCancelled(opHash);

        vm.prank(guardianAddr);
        guardian.cancel(opHash);
    }

    function test_cancel_RevertsWhenNotGuardian() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));

        vm.prank(admin);
        bytes32 opHash = guardian.propose(data);

        vm.prank(admin);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OnlyGuardian.selector);
        guardian.cancel(opHash);
    }

    function test_cancel_RevertsWhenAttackerCalls() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));

        vm.prank(admin);
        bytes32 opHash = guardian.propose(data);

        vm.prank(attacker);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OnlyGuardian.selector);
        guardian.cancel(opHash);
    }

    function test_cancel_RevertsWhenNotPending() public {
        bytes32 fakeHash = keccak256("nonexistent");

        vm.prank(guardianAddr);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OperationNotPending.selector);
        guardian.cancel(fakeHash);
    }

    function test_cancel_PreventsExecution() public {
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));
        uint256 proposedAt = block.timestamp;

        vm.prank(admin);
        guardian.propose(data);

        // Guardian cancels
        vm.prank(guardianAddr);
        bytes32 opHash = keccak256(abi.encode(address(mockVault), data, proposedAt));
        guardian.cancel(opHash);

        // Admin tries to execute after delay
        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.prank(admin);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OperationNotPending.selector);
        guardian.execute(data, proposedAt);

        // Vault state unchanged
        assertEq(mockVault.newAuthority(), address(0));
    }

    // ──────────────────────────────────────────────
    //  Emergency Pause
    // ──────────────────────────────────────────────

    function test_emergencyPause_Success() public {
        vm.prank(guardianAddr);
        guardian.emergencyPause();

        assertTrue(mockVault.paused());
    }

    function test_emergencyPause_RevertsWhenNotGuardian() public {
        vm.prank(admin);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OnlyGuardian.selector);
        guardian.emergencyPause();
    }

    function test_emergencyPause_RevertsWhenAttackerCalls() public {
        vm.prank(attacker);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OnlyGuardian.selector);
        guardian.emergencyPause();
    }

    function test_emergencyPause_NoTimelockRequired() public {
        // Pause is instant — no propose/wait needed
        assertFalse(mockVault.paused());

        vm.prank(guardianAddr);
        guardian.emergencyPause();

        assertTrue(mockVault.paused());
    }

    // ──────────────────────────────────────────────
    //  Admin Transfer (timelocked propose/accept)
    // ──────────────────────────────────────────────

    function test_transferAdmin_ProposeSetsPendingAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        guardian.transferAdmin(newAdmin);

        // Admin should NOT change yet
        assertEq(guardian.admin(), admin);
        assertEq(guardian.pendingAdmin(), newAdmin);
        assertGt(guardian.adminTransferExecuteAfter(), block.timestamp);
    }

    function test_transferAdmin_EmitsProposedEvent() public {
        address newAdmin = makeAddr("newAdmin");

        vm.expectEmit(true, true, true, true);
        emit AdminTransferProposed(admin, newAdmin);

        vm.prank(admin);
        guardian.transferAdmin(newAdmin);
    }

    function test_transferAdmin_RevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__ZeroAddress.selector);
        guardian.transferAdmin(address(0));
    }

    function test_transferAdmin_RevertsWhenNotAdmin() public {
        vm.prank(attacker);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OnlyAdmin.selector);
        guardian.transferAdmin(attacker);
    }

    function test_acceptAdminTransfer_Success() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        guardian.transferAdmin(newAdmin);

        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.prank(admin);
        guardian.acceptAdminTransfer();

        assertEq(guardian.admin(), newAdmin);
        assertEq(guardian.pendingAdmin(), address(0));
        assertEq(guardian.adminTransferExecuteAfter(), 0);
    }

    function test_acceptAdminTransfer_EmitsEvent() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        guardian.transferAdmin(newAdmin);

        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.expectEmit(true, true, true, true);
        emit AdminTransferred(admin, newAdmin);

        vm.prank(admin);
        guardian.acceptAdminTransfer();
    }

    function test_acceptAdminTransfer_PendingAdminCanAccept() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        guardian.transferAdmin(newAdmin);

        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.prank(newAdmin);
        guardian.acceptAdminTransfer();

        assertEq(guardian.admin(), newAdmin);
    }

    function test_acceptAdminTransfer_RevertsBeforeDelay() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        guardian.transferAdmin(newAdmin);

        vm.warp(block.timestamp + TIMELOCK_DELAY - 1);

        vm.prank(admin);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__AdminTransferNotReady.selector);
        guardian.acceptAdminTransfer();
    }

    function test_acceptAdminTransfer_RevertsWhenNoPending() public {
        vm.prank(admin);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__NoAdminTransferPending.selector);
        guardian.acceptAdminTransfer();
    }

    function test_acceptAdminTransfer_RevertsWhenUnauthorized() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        guardian.transferAdmin(newAdmin);

        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.prank(attacker);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OnlyAdmin.selector);
        guardian.acceptAdminTransfer();
    }

    function test_cancelAdminTransfer_Success() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        guardian.transferAdmin(newAdmin);

        vm.prank(guardianAddr);
        guardian.cancelAdminTransfer();

        assertEq(guardian.pendingAdmin(), address(0));
        assertEq(guardian.adminTransferExecuteAfter(), 0);
    }

    function test_cancelAdminTransfer_RevertsWhenNotGuardian() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        guardian.transferAdmin(newAdmin);

        vm.prank(admin);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OnlyGuardian.selector);
        guardian.cancelAdminTransfer();
    }

    function test_cancelAdminTransfer_RevertsWhenNoPending() public {
        vm.prank(guardianAddr);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__NoAdminTransferPending.selector);
        guardian.cancelAdminTransfer();
    }

    function test_cancelAdminTransfer_PreventsAccept() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        guardian.transferAdmin(newAdmin);

        vm.prank(guardianAddr);
        guardian.cancelAdminTransfer();

        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.prank(admin);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__NoAdminTransferPending.selector);
        guardian.acceptAdminTransfer();
    }

    function test_transferAdmin_OldAdminLosesAccess() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        guardian.transferAdmin(newAdmin);

        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.prank(admin);
        guardian.acceptAdminTransfer();

        // Old admin can no longer propose
        bytes memory data = abi.encodeWithSelector(MockVault.pause.selector);

        vm.prank(admin);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OnlyAdmin.selector);
        guardian.propose(data);

        // New admin can propose
        vm.prank(newAdmin);
        guardian.propose(data);
    }

    // ──────────────────────────────────────────────
    //  Guardian Transfer
    // ──────────────────────────────────────────────

    function test_transferGuardian_Success() public {
        address newGuardian = makeAddr("newGuardian");

        vm.prank(guardianAddr);
        guardian.transferGuardian(newGuardian);

        assertEq(guardian.guardian(), newGuardian);
    }

    function test_transferGuardian_EmitsEvent() public {
        address newGuardian = makeAddr("newGuardian");

        vm.expectEmit(true, true, true, true);
        emit GuardianTransferred(guardianAddr, newGuardian);

        vm.prank(guardianAddr);
        guardian.transferGuardian(newGuardian);
    }

    function test_transferGuardian_RevertsOnZeroAddress() public {
        vm.prank(guardianAddr);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__ZeroAddress.selector);
        guardian.transferGuardian(address(0));
    }

    function test_transferGuardian_RevertsWhenNotGuardian() public {
        vm.prank(admin);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OnlyGuardian.selector);
        guardian.transferGuardian(admin);
    }

    function test_transferGuardian_OldGuardianLosesAccess() public {
        address newGuardian = makeAddr("newGuardian");

        vm.prank(guardianAddr);
        guardian.transferGuardian(newGuardian);

        // Old guardian can no longer cancel
        bytes memory data = abi.encodeWithSelector(MockVault.setAuthority.selector, address(0xBEEF));
        vm.prank(admin);
        bytes32 opHash = guardian.propose(data);

        vm.prank(guardianAddr);
        vm.expectRevert(TimelockGuardian.TimelockGuardian__OnlyGuardian.selector);
        guardian.cancel(opHash);

        // New guardian can cancel
        vm.prank(newGuardian);
        guardian.cancel(opHash);
    }

    // ──────────────────────────────────────────────
    //  Integration: Full propose → cancel → re-propose → execute
    // ──────────────────────────────────────────────

    function test_fullLifecycle_ProposeCancel_RePropose_Execute() public {
        address newOwner = makeAddr("newOwner");
        bytes memory data = abi.encodeWithSelector(MockVault.transferOwnership.selector, newOwner);

        // 1. Propose
        uint256 proposedAt1 = block.timestamp;
        vm.prank(admin);
        bytes32 opHash1 = guardian.propose(data);

        // 2. Guardian cancels (maybe compromise detected)
        vm.prank(guardianAddr);
        guardian.cancel(opHash1);

        // 3. After investigation, re-propose at new timestamp
        vm.warp(block.timestamp + 1 hours);
        uint256 proposedAt2 = block.timestamp;

        vm.prank(admin);
        guardian.propose(data);

        // 4. Wait the full delay and execute
        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.prank(admin);
        guardian.execute(data, proposedAt2);

        assertEq(mockVault.newOwnerAddr(), newOwner);
    }
}
