// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {SovereignAccount} from "src/sovereign/SovereignAccount.sol";
import {IAccount, PackedUserOperation} from "src/interfaces/erc4337/IAccount.sol";
import {SovereignFactory} from "src/sovereign/SovereignFactory.sol";

/*//////////////////////////////////////////////////////////////
                    MOCK ENTRYPOINT
//////////////////////////////////////////////////////////////*/

contract MockEntryPoint {
    function handleOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) external {
        uint256 validation = IAccount(userOp.sender).validateUserOp(userOp, userOpHash, 0);
        if (uint160(validation) != 0) revert("validation failed");

        (bool ok, bytes memory ret) = userOp.sender.call(userOp.callData);
        if (!ok) {
            assembly { revert(add(ret, 0x20), mload(ret)) }
        }
    }

    function hashOp(PackedUserOperation calldata userOp) external view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256(abi.encode(
                userOp.sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.accountGasLimits,
                userOp.preVerificationGas,
                userOp.gasFees,
                keccak256(userOp.paymasterAndData)
            )),
            address(this),
            block.chainid
        ));
    }

    function depositTo(address) external payable {}
}

/*//////////////////////////////////////////////////////////////
                    TEST TARGET CONTRACTS
//////////////////////////////////////////////////////////////*/

contract Target {
    uint256 public value;

    function setValue(uint256 v) external payable {
        value = v;
    }

    function failAlways() external pure {
        revert("intentional");
    }
}

contract GreeterHandler {
    function greet() external pure returns (string memory) {
        return "sovereign";
    }
}

/*//////////////////////////////////////////////////////////////
                        MAIN TEST SUITE
//////////////////////////////////////////////////////////////*/

contract SovereignAccountTest is Test {
    SovereignAccount account;
    SovereignFactory factory;
    MockEntryPoint   ep;
    Target           target;

    uint256 constant OWNER_KEY   = 0xA11CE;
    uint256 constant SIGNER_KEY  = 0xB0B;
    uint256 constant SESSION_KEY = 0xCAFE;

    address owner;
    address signer;
    address sessionAddr;

    function setUp() public {
        owner       = vm.addr(OWNER_KEY);
        signer      = vm.addr(SIGNER_KEY);
        sessionAddr = vm.addr(SESSION_KEY);

        ep      = new MockEntryPoint();
        factory = new SovereignFactory(address(ep));
        account = factory.createAccount(owner, 0);
        target  = new Target();

        vm.deal(address(account), 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                              HELPERS
    //////////////////////////////////////////////////////////////*/

    function _buildUserOp(
        bytes memory callData,
        bytes memory signature
    ) internal view returns (PackedUserOperation memory) {
        return PackedUserOperation({
            sender:             address(account),
            nonce:              0,
            initCode:           "",
            callData:           callData,
            accountGasLimits:   bytes32(0),
            preVerificationGas: 0,
            gasFees:            bytes32(0),
            paymasterAndData:   "",
            signature:          signature
        });
    }

    function _signAsOwner(bytes32 hash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_KEY, _ethHash(hash));
        return abi.encodePacked(uint8(0x00), r, s, v);
    }

    function _signAsRoleSigner(bytes32 hash) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, _ethHash(hash));
        return abi.encodePacked(uint8(0x01), signer, r, s, v);
    }

    function _signAsSessionKey(bytes32 hash) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SESSION_KEY, _ethHash(hash));
        return abi.encodePacked(uint8(0x02), sessionAddr, r, s, v);
    }

    function _ethHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    /*//////////////////////////////////////////////////////////////
                          FACTORY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_factoryDeterministicAddress() public view {
        assertEq(factory.getAddress(owner, 0), address(account));
    }

    function test_factoryReturnsExistingAccount() public {
        assertEq(address(factory.createAccount(owner, 0)), address(account));
    }

    function test_factoryDifferentSalt() public {
        assertTrue(address(factory.createAccount(owner, 1)) != address(account));
    }

    /*//////////////////////////////////////////////////////////////
                    OWNER VALIDATION & EXECUTION
    //////////////////////////////////////////////////////////////*/

    function test_ownerExecute() public {
        bytes memory cd = abi.encodeCall(
            SovereignAccount.execute,
            (address(target), 0, abi.encodeCall(Target.setValue, (42)))
        );
        PackedUserOperation memory userOp = _buildUserOp(cd, "");
        bytes32 h = ep.hashOp(userOp);
        userOp.signature = _signAsOwner(h);

        ep.handleOp(userOp, h);
        assertEq(target.value(), 42);
    }

    function test_ownerExecuteWithValue() public {
        bytes memory cd = abi.encodeCall(
            SovereignAccount.execute,
            (address(target), 1 ether, abi.encodeCall(Target.setValue, (99)))
        );
        PackedUserOperation memory userOp = _buildUserOp(cd, "");
        bytes32 h = ep.hashOp(userOp);
        userOp.signature = _signAsOwner(h);

        ep.handleOp(userOp, h);
        assertEq(target.value(), 99);
        assertEq(address(target).balance, 1 ether);
    }

    function test_invalidSignatureReverts() public {
        bytes memory cd = abi.encodeCall(
            SovereignAccount.execute,
            (address(target), 0, abi.encodeCall(Target.setValue, (1)))
        );
        PackedUserOperation memory userOp = _buildUserOp(cd, "");
        bytes32 h = ep.hashOp(userOp);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, _ethHash(h));
        userOp.signature = abi.encodePacked(uint8(0x00), r, s, v);

        vm.expectRevert("validation failed");
        ep.handleOp(userOp, h);
    }

    /*//////////////////////////////////////////////////////////////
                            ROLE SIGNER
    //////////////////////////////////////////////////////////////*/

    function test_roleSignerExecute() public {
        vm.startPrank(owner);
        account.setRole(signer, account.PERM_EXECUTE());
        vm.stopPrank();

        bytes memory cd = abi.encodeCall(
            SovereignAccount.execute,
            (address(target), 0, abi.encodeCall(Target.setValue, (7)))
        );
        PackedUserOperation memory userOp = _buildUserOp(cd, "");
        bytes32 h = ep.hashOp(userOp);
        userOp.signature = _signAsRoleSigner(h);

        ep.handleOp(userOp, h);
        assertEq(target.value(), 7);
    }

    function test_roleSignerWithoutPermissionFails() public {
        bytes memory cd = abi.encodeCall(
            SovereignAccount.execute,
            (address(target), 0, abi.encodeCall(Target.setValue, (7)))
        );
        PackedUserOperation memory userOp = _buildUserOp(cd, "");
        bytes32 h = ep.hashOp(userOp);
        userOp.signature = _signAsRoleSigner(h);

        vm.expectRevert("validation failed");
        ep.handleOp(userOp, h);
    }

    /*//////////////////////////////////////////////////////////////
                            SESSION KEYS
    //////////////////////////////////////////////////////////////*/

    function test_sessionKeyExecute() public {
        vm.startPrank(owner);
        account.createSessionKey(
            sessionAddr,
            account.PERM_EXECUTE(),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 hours),
            10 ether
        );
        vm.stopPrank();

        bytes memory cd = abi.encodeCall(
            SovereignAccount.execute,
            (address(target), 0, abi.encodeCall(Target.setValue, (123)))
        );
        PackedUserOperation memory userOp = _buildUserOp(cd, "");
        bytes32 h = ep.hashOp(userOp);
        userOp.signature = _signAsSessionKey(h);

        ep.handleOp(userOp, h);
        assertEq(target.value(), 123);
    }

    function test_sessionKeySpendLimit() public {
        vm.startPrank(owner);
        account.createSessionKey(
            sessionAddr,
            account.PERM_EXECUTE(),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 hours),
            0.5 ether
        );
        vm.stopPrank();

        bytes memory cd = abi.encodeCall(
            SovereignAccount.execute,
            (address(target), 1 ether, abi.encodeCall(Target.setValue, (1)))
        );
        PackedUserOperation memory userOp = _buildUserOp(cd, "");
        bytes32 h = ep.hashOp(userOp);
        userOp.signature = _signAsSessionKey(h);

        vm.expectRevert();
        ep.handleOp(userOp, h);
    }

    /*//////////////////////////////////////////////////////////////
                            KARMA SYSTEM
    //////////////////////////////////////////////////////////////*/

    function test_karmaIncreasesOnSuccess() public {
        vm.startPrank(owner);
        account.setRole(signer, account.PERM_EXECUTE());
        vm.stopPrank();

        bytes memory cd = abi.encodeCall(
            SovereignAccount.execute,
            (address(target), 0, abi.encodeCall(Target.setValue, (1)))
        );
        PackedUserOperation memory userOp = _buildUserOp(cd, "");
        bytes32 h = ep.hashOp(userOp);
        userOp.signature = _signAsRoleSigner(h);
        ep.handleOp(userOp, h);

        (uint64 score, uint32 successes,) = account.getKarma(signer);
        assertEq(score, 10);
        assertEq(successes, 1);
    }

    function test_karmaDecreasesOnFailure() public {
        vm.startPrank(owner);
        account.setRole(signer, account.PERM_EXECUTE());
        vm.stopPrank();

        for (uint256 i; i < 5; i++) {
            bytes memory cd = abi.encodeCall(
                SovereignAccount.execute,
                (address(target), 0, abi.encodeCall(Target.setValue, (i)))
            );
            PackedUserOperation memory userOp = _buildUserOp(cd, "");
            userOp.nonce = i;
            bytes32 h = ep.hashOp(userOp);
            userOp.signature = _signAsRoleSigner(h);
            ep.handleOp(userOp, h);
        }

        (uint64 scoreBefore,,) = account.getKarma(signer);
        assertEq(scoreBefore, 50);

        bytes memory failCd = abi.encodeCall(
            SovereignAccount.execute,
            (address(target), 0, abi.encodeCall(Target.failAlways, ()))
        );
        PackedUserOperation memory failOp = _buildUserOp(failCd, "");
        failOp.nonce = 5;
        bytes32 failH = ep.hashOp(failOp);
        failOp.signature = _signAsRoleSigner(failH);

        ep.handleOp(failOp, failH);

        (uint64 scoreAfter,,) = account.getKarma(signer);
        assertEq(scoreAfter, 25);
    }

    function test_karmaLimitsSpending() public {
        vm.startPrank(owner);
        account.setRole(signer, account.PERM_EXECUTE());
        vm.stopPrank();

        bytes memory cd = abi.encodeCall(
            SovereignAccount.execute,
            (address(target), 0.2 ether, abi.encodeCall(Target.setValue, (1)))
        );
        PackedUserOperation memory userOp = _buildUserOp(cd, "");
        bytes32 h = ep.hashOp(userOp);
        userOp.signature = _signAsRoleSigner(h);

        vm.expectRevert();
        ep.handleOp(userOp, h);
    }

    /*//////////////////////////////////////////////////////////////
                          VELOCITY LIMITER
    //////////////////////////////////////////////////////////////*/

    function _grantRoleAndBuildKarma(uint256 txCount) internal {
        vm.startPrank(owner);
        account.setRole(signer, account.PERM_EXECUTE());
        vm.stopPrank();

        for (uint256 i; i < txCount; i++) {
            bytes memory cd = abi.encodeCall(
                SovereignAccount.execute,
                (address(target), 0, abi.encodeCall(Target.setValue, (i)))
            );
            PackedUserOperation memory op = _buildUserOp(cd, "");
            op.nonce = i;
            bytes32 h = ep.hashOp(op);
            op.signature = _signAsRoleSigner(h);
            ep.handleOp(op, h);
        }
    }

    function test_velocityLimiter() public {
        _grantRoleAndBuildKarma(10);

        vm.prank(owner);
        account.configureVelocity(0.5 ether, 1 hours);

        bytes memory cd1 = abi.encodeCall(
            SovereignAccount.execute,
            (address(target), 0.3 ether, abi.encodeCall(Target.setValue, (1)))
        );
        PackedUserOperation memory op1 = _buildUserOp(cd1, "");
        op1.nonce = 10;
        bytes32 h1 = ep.hashOp(op1);
        op1.signature = _signAsRoleSigner(h1);
        ep.handleOp(op1, h1);

        bytes memory cd2 = abi.encodeCall(
            SovereignAccount.execute,
            (address(target), 0.3 ether, abi.encodeCall(Target.setValue, (2)))
        );
        PackedUserOperation memory op2 = _buildUserOp(cd2, "");
        op2.nonce = 11;
        bytes32 h2 = ep.hashOp(op2);
        op2.signature = _signAsRoleSigner(h2);

        vm.expectRevert();
        ep.handleOp(op2, h2);
    }

    function test_velocityWindowResets() public {
        _grantRoleAndBuildKarma(10);

        vm.prank(owner);
        account.configureVelocity(0.5 ether, 1 hours);

        bytes memory cd1 = abi.encodeCall(
            SovereignAccount.execute,
            (address(target), 0.4 ether, abi.encodeCall(Target.setValue, (1)))
        );
        PackedUserOperation memory op1 = _buildUserOp(cd1, "");
        op1.nonce = 10;
        bytes32 h1 = ep.hashOp(op1);
        op1.signature = _signAsRoleSigner(h1);
        ep.handleOp(op1, h1);

        vm.warp(block.timestamp + 2 hours);

        bytes memory cd2 = abi.encodeCall(
            SovereignAccount.execute,
            (address(target), 0.4 ether, abi.encodeCall(Target.setValue, (2)))
        );
        PackedUserOperation memory op2 = _buildUserOp(cd2, "");
        op2.nonce = 11;
        bytes32 h2 = ep.hashOp(op2);
        op2.signature = _signAsRoleSigner(h2);
        ep.handleOp(op2, h2);

        assertEq(target.value(), 2);
    }

    /*//////////////////////////////////////////////////////////////
                    DEAD MAN'S SWITCH & RECOVERY
    //////////////////////////////////////////////////////////////*/

    function test_deadManSwitchRecovery() public {
        address guardian1 = makeAddr("guardian1");
        address guardian2 = makeAddr("guardian2");
        address guardian3 = makeAddr("guardian3");
        address newOwner  = makeAddr("newOwner");

        vm.startPrank(owner);
        account.addGuardian(guardian1);
        account.addGuardian(guardian2);
        account.addGuardian(guardian3);
        account.setRecoveryThreshold(2);
        account.configureDeadMan(30 days);
        vm.stopPrank();

        assertFalse(account.isDeadManTriggered());

        vm.warp(block.timestamp + 31 days);
        assertTrue(account.isDeadManTriggered());

        vm.prank(guardian1);
        account.initiateRecovery(newOwner);
        assertEq(account.recoveryApprovals(), 1);

        vm.prank(guardian2);
        account.approveRecovery(newOwner);

        assertEq(account.owner(), newOwner);
    }

    function test_ownerCancelsRecovery() public {
        address guardian = makeAddr("guardian");
        address newOwner = makeAddr("newOwner");

        vm.startPrank(owner);
        account.addGuardian(guardian);
        account.setRecoveryThreshold(1);
        account.configureDeadMan(30 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        vm.prank(guardian);
        account.initiateRecovery(newOwner);

        vm.prank(owner);
        account.cancelRecovery();

        assertEq(account.activeRecoveryHash(), bytes32(0));
        assertFalse(account.isDeadManTriggered());
    }

    function test_deadManNotTriggeredReverts() public {
        address guardian = makeAddr("guardian");

        vm.prank(owner);
        account.addGuardian(guardian);

        vm.prank(guardian);
        vm.expectRevert(SovereignAccount.SovereignAccount__DeadManNotTriggered.selector);
        account.initiateRecovery(makeAddr("newOwner"));
    }

    /*//////////////////////////////////////////////////////////////
                              ERC-1271
    //////////////////////////////////////////////////////////////*/

    function test_erc1271OwnerSignature() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_KEY, _ethHash(hash));

        assertEq(account.isValidSignature(hash, abi.encodePacked(r, s, v)), bytes4(0x1626ba7e));
    }

    function test_erc1271RoleSignerSignature() public {
        vm.startPrank(owner);
        account.setRole(signer, account.PERM_EXECUTE());
        vm.stopPrank();

        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, _ethHash(hash));

        assertEq(account.isValidSignature(hash, abi.encodePacked(r, s, v)), bytes4(0x1626ba7e));
    }

    function test_erc1271InvalidSignature() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, _ethHash(hash));

        assertEq(account.isValidSignature(hash, abi.encodePacked(r, s, v)), bytes4(0xffffffff));
    }

    /*//////////////////////////////////////////////////////////////
                          FALLBACK HANDLERS
    //////////////////////////////////////////////////////////////*/

    function test_fallbackHandler() public {
        GreeterHandler handler = new GreeterHandler();

        vm.prank(owner);
        account.setFallbackHandler(GreeterHandler.greet.selector, address(handler));

        (bool ok, bytes memory data) = address(account).call(
            abi.encodeCall(GreeterHandler.greet, ())
        );

        assertTrue(ok);
        assertEq(abi.decode(data, (string)), "sovereign");
    }

    function test_fallbackNoHandlerReverts() public {
        vm.expectRevert(SovereignAccount.SovereignAccount__Unauthorized.selector);
        address(account).call(abi.encodeWithSignature("nonexistent()"));
    }

    /*//////////////////////////////////////////////////////////////
                          BATCH EXECUTION
    //////////////////////////////////////////////////////////////*/

    function test_batchExecute() public {
        Target target2 = new Target();

        SovereignAccount.Call[] memory calls = new SovereignAccount.Call[](2);
        calls[0] = SovereignAccount.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(Target.setValue, (111))
        });
        calls[1] = SovereignAccount.Call({
            target: address(target2),
            value: 0,
            data: abi.encodeCall(Target.setValue, (222))
        });

        bytes memory cd = abi.encodeCall(SovereignAccount.executeBatch, (calls));
        PackedUserOperation memory userOp = _buildUserOp(cd, "");
        bytes32 h = ep.hashOp(userOp);
        userOp.signature = _signAsOwner(h);

        ep.handleOp(userOp, h);

        assertEq(target.value(), 111);
        assertEq(target2.value(), 222);
    }

    /*//////////////////////////////////////////////////////////////
                      DIRECT OWNER CALLS
    //////////////////////////////////////////////////////////////*/

    function test_ownerDirectExecute() public {
        vm.prank(owner);
        account.execute(address(target), 0, abi.encodeCall(Target.setValue, (77)));
        assertEq(target.value(), 77);
    }

    /*//////////////////////////////////////////////////////////////
                          RECEIVE ETH
    //////////////////////////////////////////////////////////////*/

    function test_receiveEth() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(account).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(account).balance, 101 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        OWNERSHIP TRANSFER
    //////////////////////////////////////////////////////////////*/

    function test_transferOwnership() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        account.transferOwnership(newOwner);
        assertEq(account.owner(), newOwner);
    }

    function test_nonOwnerCannotTransfer() public {
        vm.prank(signer);
        vm.expectRevert(SovereignAccount.SovereignAccount__Unauthorized.selector);
        account.transferOwnership(signer);
    }

    /*//////////////////////////////////////////////////////////////
                    SECURITY EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_transferOwnershipZeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert(SovereignAccount.SovereignAccount__ZeroAddress.selector);
        account.transferOwnership(address(0));
    }

    function test_configureDeadManBelowMinReverts() public {
        vm.prank(owner);
        vm.expectRevert(SovereignAccount.SovereignAccount__InvalidThreshold.selector);
        account.configureDeadMan(0);
    }

    function test_configureDeadManAtMinimum() public {
        vm.prank(owner);
        account.configureDeadMan(1 days);
        assertEq(account.inactivityThreshold(), 1 days);
    }

    function test_initiateRecoveryZeroAddressReverts() public {
        address guardian = makeAddr("guardian");

        vm.startPrank(owner);
        account.addGuardian(guardian);
        account.setRecoveryThreshold(1);
        account.configureDeadMan(30 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        vm.prank(guardian);
        vm.expectRevert(SovereignAccount.SovereignAccount__ZeroAddress.selector);
        account.initiateRecovery(address(0));
    }

    function test_initiateRecoveryOverwriteReverts() public {
        address guardian1 = makeAddr("guardian1");
        address guardian2 = makeAddr("guardian2");
        address newOwner  = makeAddr("newOwner");
        address newOwner2 = makeAddr("newOwner2");

        vm.startPrank(owner);
        account.addGuardian(guardian1);
        account.addGuardian(guardian2);
        account.setRecoveryThreshold(2);
        account.configureDeadMan(30 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        vm.prank(guardian1);
        account.initiateRecovery(newOwner);

        vm.prank(guardian2);
        vm.expectRevert(SovereignAccount.SovereignAccount__RecoveryAlreadyActive.selector);
        account.initiateRecovery(newOwner2);
    }

    function test_approveRecoveryExpiresAfter7Days() public {
        address guardian1 = makeAddr("guardian1");
        address guardian2 = makeAddr("guardian2");
        address newOwner  = makeAddr("newOwner");

        vm.startPrank(owner);
        account.addGuardian(guardian1);
        account.addGuardian(guardian2);
        account.setRecoveryThreshold(2);
        account.configureDeadMan(30 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        vm.prank(guardian1);
        account.initiateRecovery(newOwner);

        vm.warp(block.timestamp + 8 days);

        vm.prank(guardian2);
        vm.expectRevert(SovereignAccount.SovereignAccount__RecoveryExpired.selector);
        account.approveRecovery(newOwner);
    }

    function test_removeGuardianBelowThresholdReverts() public {
        address guardian1 = makeAddr("guardian1");
        address guardian2 = makeAddr("guardian2");

        vm.startPrank(owner);
        account.addGuardian(guardian1);
        account.addGuardian(guardian2);
        account.setRecoveryThreshold(2);
        vm.stopPrank();

        vm.prank(owner);
        vm.expectRevert(SovereignAccount.SovereignAccount__InvalidGuardianConfig.selector);
        account.removeGuardian(guardian1);
    }

    function test_removeGuardianAboveThresholdSucceeds() public {
        address guardian1 = makeAddr("guardian1");
        address guardian2 = makeAddr("guardian2");
        address guardian3 = makeAddr("guardian3");

        vm.startPrank(owner);
        account.addGuardian(guardian1);
        account.addGuardian(guardian2);
        account.addGuardian(guardian3);
        account.setRecoveryThreshold(2);
        vm.stopPrank();

        vm.prank(owner);
        account.removeGuardian(guardian3);
        assertEq(account.guardianCount(), 2);
    }

    function test_batchExecuteWithValue() public {
        Target target2 = new Target();

        SovereignAccount.Call[] memory calls = new SovereignAccount.Call[](2);
        calls[0] = SovereignAccount.Call({
            target: address(target),
            value: 1 ether,
            data: abi.encodeCall(Target.setValue, (111))
        });
        calls[1] = SovereignAccount.Call({
            target: address(target2),
            value: 2 ether,
            data: abi.encodeCall(Target.setValue, (222))
        });

        bytes memory cd = abi.encodeCall(SovereignAccount.executeBatch, (calls));
        PackedUserOperation memory userOp = _buildUserOp(cd, "");
        bytes32 h = ep.hashOp(userOp);
        userOp.signature = _signAsOwner(h);

        ep.handleOp(userOp, h);

        assertEq(target.value(), 111);
        assertEq(target2.value(), 222);
        assertEq(address(target).balance, 1 ether);
        assertEq(address(target2).balance, 2 ether);
    }

    /*//////////////////////////////////////////////////////////////
                          FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_karmaSpendLimitTiers(uint64 score) public view {
        score = uint64(bound(score, 0, 1200));
        uint256 limit = account.karmaSpendLimit(score);

        if (score >= 1000) {
            assertEq(limit, type(uint256).max);
        } else if (score >= 600) {
            assertEq(limit, 100 ether);
        } else if (score >= 300) {
            assertEq(limit, 10 ether);
        } else if (score >= 100) {
            assertEq(limit, 1 ether);
        } else {
            assertEq(limit, 0.1 ether);
        }
    }

    function testFuzz_karmaScoreNeverExceedsMax(uint8 successCount) public {
        vm.startPrank(owner);
        account.setRole(signer, account.PERM_EXECUTE());
        vm.stopPrank();

        uint256 runs = bound(successCount, 1, 120);

        for (uint256 i; i < runs; i++) {
            bytes memory cd = abi.encodeCall(
                SovereignAccount.execute,
                (address(target), 0, abi.encodeCall(Target.setValue, (i)))
            );
            PackedUserOperation memory op = _buildUserOp(cd, "");
            op.nonce = i;
            bytes32 h = ep.hashOp(op);
            op.signature = _signAsRoleSigner(h);
            ep.handleOp(op, h);
        }

        (uint64 score,,) = account.getKarma(signer);
        assertLe(score, 1000, "karma must never exceed KARMA_MAX");
    }

    function testFuzz_velocityEnforcedWithinWindow(uint128 maxPerWindow, uint128 txValue) public {
        maxPerWindow = uint128(bound(maxPerWindow, 0.1 ether, 10 ether));
        txValue = uint128(bound(txValue, 0, maxPerWindow));

        _grantRoleAndBuildKarma(10);

        vm.prank(owner);
        account.configureVelocity(maxPerWindow, 1 hours);

        bytes memory cd = abi.encodeCall(
            SovereignAccount.execute,
            (address(target), txValue, abi.encodeCall(Target.setValue, (1)))
        );
        PackedUserOperation memory op = _buildUserOp(cd, "");
        op.nonce = 10;
        bytes32 h = ep.hashOp(op);
        op.signature = _signAsRoleSigner(h);

        if (txValue > account.karmaSpendLimit(karma(signer))) {
            vm.expectRevert();
        }
        ep.handleOp(op, h);
    }

    function karma(address s) internal view returns (uint64) {
        (uint64 score,,) = account.getKarma(s);
        return score;
    }

    function testFuzz_sessionKeySpendLimit(uint128 limit, uint128 txValue) public {
        limit = uint128(bound(limit, 0.01 ether, 10 ether));
        txValue = uint128(bound(txValue, 0, 0.1 ether));

        vm.startPrank(owner);
        account.createSessionKey(
            sessionAddr,
            account.PERM_EXECUTE(),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 hours),
            limit
        );
        vm.stopPrank();

        bytes memory cd = abi.encodeCall(
            SovereignAccount.execute,
            (address(target), txValue, abi.encodeCall(Target.setValue, (1)))
        );
        PackedUserOperation memory userOp = _buildUserOp(cd, "");
        bytes32 h = ep.hashOp(userOp);
        userOp.signature = _signAsSessionKey(h);

        if (txValue > limit) {
            vm.expectRevert();
        }
        ep.handleOp(userOp, h);
    }
}
