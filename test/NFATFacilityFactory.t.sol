// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.24;

import "dss-test/DssTest.sol";
import { NFATFacility }                      from "src/NFATFacility.sol";
import { NFATFacilityFactory, INFATFacilityFactory } from "src/NFATFacilityFactory.sol";

contract NFATFacilityFactoryTest is DssTest {
    DssInstance dss;
    address     gem;        // real SUSDS, used as the facility's underlying asset

    NFATFacilityFactory factory;

    address recipient = makeAddr("recipient");
    address idNet     = makeAddr("identityNetwork");
    address ward1     = makeAddr("ward1");
    address ward2     = makeAddr("ward2");
    address bud1      = makeAddr("bud1");
    address bud2      = makeAddr("bud2");
    address cop1      = makeAddr("cop1");
    address cop2      = makeAddr("cop2");

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        dss = MCD.loadFromChainlog(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
        gem = dss.chainlog.getAddress("SUSDS");

        factory = new NFATFacilityFactory();
    }

    // --- Helpers ---

    function _arr(address a) internal pure returns (address[] memory out) {
        out = new address[](1);
        out[0] = a;
    }

    function _arr(address a, address b) internal pure returns (address[] memory out) {
        out = new address[](2);
        out[0] = a;
        out[1] = b;
    }

    function _predictFacility() internal view returns (address) {
        return vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));
    }

    // --- Deploy: happy path ---

    function testDeploy() public {
        address[] memory wards = _arr(ward1, ward2);
        address[] memory buds  = _arr(bud1, bud2);
        address[] memory cops  = _arr(cop1, cop2);

        address predicted = _predictFacility();

        vm.expectEmit(address(factory));
        emit INFATFacilityFactory.FacilityDeployed(
            predicted, "Halo", "HALO", "ipfs://base/", gem, recipient, idNet, wards, buds, cops
        );

        address facility_ = factory.deploy(
            "Halo", "HALO", "ipfs://base/", gem, recipient, idNet, wards, buds, cops
        );

        assertEq(facility_, predicted);

        NFATFacility facility = NFATFacility(facility_);

        // Underlying + metadata.
        assertEq(address(facility.gem()),             gem);
        assertEq(facility.name(),                     "Halo");
        assertEq(facility.symbol(),                   "HALO");
        assertEq(facility.baseURI(),                  "ipfs://base/");
        assertEq(facility.recipient(),                recipient);
        assertEq(address(facility.identityNetwork()), idNet);

        // Wards relied (and the factory denied itself).
        assertEq(facility.wards(ward1),            1);
        assertEq(facility.wards(ward2),            1);
        assertEq(facility.wards(address(factory)), 0);

        // Buds kissed.
        assertEq(facility.buds(bud1), 1);
        assertEq(facility.buds(bud2), 1);

        // Cops added as freezers.
        assertEq(facility.cops(cop1), 1);
        assertEq(facility.cops(cop2), 1);
    }

    function testDeployEmptyBaseURISkipped() public {
        address facility_ = factory.deploy(
            "Halo", "HALO", "", gem, recipient, idNet, _arr(ward1), _arr(bud1), _arr(cop1)
        );

        assertEq(NFATFacility(facility_).baseURI(), "");
    }

    function testDeployZeroIdentityNetworkSkipped() public {
        address facility_ = factory.deploy(
            "Halo", "HALO", "ipfs://base/", gem, recipient, address(0), _arr(ward1), _arr(bud1), _arr(cop1)
        );

        assertEq(address(NFATFacility(facility_).identityNetwork()), address(0));
    }

    function testDeployEmptyBudsAndCops() public {
        // Buds and cops are optional; only wards are required.
        address facility_ = factory.deploy(
            "Halo", "HALO", "", gem, recipient, idNet, _arr(ward1), new address[](0), new address[](0)
        );

        NFATFacility facility = NFATFacility(facility_);

        assertEq(facility.wards(ward1),            1);
        assertEq(facility.wards(address(factory)), 0);
        assertEq(facility.buds(bud1),              0);
        assertEq(facility.cops(cop1),              0);
    }

    // --- Deploy: reverts ---

    function testDeployRevertNoWards() public {
        vm.expectRevert("NFATFacilityFactory/no-wards");
        factory.deploy(
            "Halo", "HALO", "", gem, recipient, idNet, new address[](0), _arr(bud1), _arr(cop1)
        );
    }

    function testDeployRevertRecipientZero() public {
        vm.expectRevert("NFATFacilityFactory/recipient-zero-address");
        factory.deploy(
            "Halo", "HALO", "", gem, address(0), idNet, _arr(ward1), _arr(bud1), _arr(cop1)
        );
    }

    function testDeployRevertWardZero() public {
        vm.expectRevert("NFATFacilityFactory/ward-zero-address");
        factory.deploy(
            "Halo", "HALO", "", gem, recipient, idNet, _arr(ward1, address(0)), _arr(bud1), _arr(cop1)
        );
    }

    function testDeployRevertBudZero() public {
        vm.expectRevert("NFATFacilityFactory/bud-zero-address");
        factory.deploy(
            "Halo", "HALO", "", gem, recipient, idNet, _arr(ward1), _arr(bud1, address(0)), _arr(cop1)
        );
    }

    function testDeployRevertCopZero() public {
        vm.expectRevert("NFATFacilityFactory/cop-zero-address");
        factory.deploy(
            "Halo", "HALO", "", gem, recipient, idNet, _arr(ward1), _arr(bud1), _arr(cop1, address(0))
        );
    }

    // --- Interface conformance ---

    // Calling through the published INFATFacilityFactory interface must wire the facility identically to a
    // direct call — i.e. the interface's argument order matches the implementation (no gem/recipient
    // swap, no wards/buds/cops rotation).
    function testDeployViaInterface() public {
        address facility_ = INFATFacilityFactory(address(factory)).deploy(
            "Halo", "HALO", "ipfs://base/", gem, recipient, idNet, _arr(ward1), _arr(bud1), _arr(cop1)
        );

        NFATFacility facility = NFATFacility(facility_);

        assertEq(address(facility.gem()),             gem);       // not the recipient
        assertEq(facility.recipient(),                recipient); // not the gem
        assertEq(address(facility.identityNetwork()), idNet);
        assertEq(facility.wards(ward1), 1);
        assertEq(facility.buds(bud1),   1);
        assertEq(facility.cops(cop1),   1);
    }
}
