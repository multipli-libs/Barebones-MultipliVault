// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

interface ITransientSetterFacet {
    function setShared(uint256 value) external;
    function callReadSharedViaDiamond() external view returns (uint256 value);
}

interface ITransientReaderFacet {
    function readShared() external view returns (uint256 value);
    function clearShared() external;
}

contract TransientSetterFacet is ITransientSetterFacet {
    uint256 internal constant SHARED_SLOT =
        0x7d996c9da983bfadffa3d150cf84d08183cdb73d1b203bd9b1a659452acb4e82;

    function setShared(uint256 value) external {
        assembly {
            tstore(SHARED_SLOT, value)
        }
    }

    function callReadSharedViaDiamond() external view returns (uint256 value) {
        value = ITransientReaderFacet(address(this)).readShared();
    }
}

contract TransientReaderFacet is ITransientReaderFacet {
    uint256 internal constant SHARED_SLOT =
        0x7d996c9da983bfadffa3d150cf84d08183cdb73d1b203bd9b1a659452acb4e82;

    function readShared() external view returns (uint256 value) {
        assembly {
            value := tload(SHARED_SLOT)
        }
    }

    function clearShared() external {
        assembly {
            tstore(SHARED_SLOT, 0)
        }
    }
}

contract TransientDiamondHarness {
    error TransientDiamondHarness__MissingFacet(bytes4 selector);

    mapping(bytes4 selector => address facet) internal sFacets;

    constructor(address setterFacet, address readerFacet) {
        sFacets[ITransientSetterFacet.setShared.selector] = setterFacet;
        sFacets[ITransientSetterFacet.callReadSharedViaDiamond.selector] = setterFacet;
        sFacets[ITransientReaderFacet.readShared.selector] = readerFacet;
        sFacets[ITransientReaderFacet.clearShared.selector] = readerFacet;
    }

    receive() external payable {}

    fallback() external payable {
        address facet = sFacets[msg.sig];
        if (facet == address(0)) revert TransientDiamondHarness__MissingFacet(msg.sig);

        assembly {
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())

            switch ok
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}

contract TransientDiamondHarnessTest is Test {
    TransientSetterFacet internal setterFacet;
    TransientReaderFacet internal readerFacet;
    TransientDiamondHarness internal diamond;

    function setUp() public {
        setterFacet = new TransientSetterFacet();
        readerFacet = new TransientReaderFacet();
        diamond = new TransientDiamondHarness(address(setterFacet), address(readerFacet));
    }

    function test_DirectFacetCalls_DoNotShareTransientState() public {
        setterFacet.setShared(111);

        assertEq(readerFacet.readShared(), 0);
    }

    function test_DiamondCalls_ShareTransientStateAcrossFacets() public {
        ITransientSetterFacet(address(diamond)).setShared(222);

        assertEq(ITransientReaderFacet(address(diamond)).readShared(), 222);
    }

    function test_DiamondCrossFacetCall_SharesTransientState() public {
        ITransientSetterFacet(address(diamond)).setShared(333);

        assertEq(ITransientSetterFacet(address(diamond)).callReadSharedViaDiamond(), 333);
    }

    function test_DiamondReaderFacet_CanClearSharedTransientState() public {
        ITransientSetterFacet(address(diamond)).setShared(444);
        ITransientReaderFacet(address(diamond)).clearShared();

        assertEq(ITransientReaderFacet(address(diamond)).readShared(), 0);
    }

    function test_DirectFacetState_DoesNotLeakIntoDiamondContext() public {
        setterFacet.setShared(555);

        assertEq(ITransientReaderFacet(address(diamond)).readShared(), 0);
    }
}