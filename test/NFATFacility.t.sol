// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.24;

import "dss-test/DssTest.sol";
import { NFATFacility } from "src/NFATFacility.sol";
import { NFATDeploy } from "deploy/NFATDeploy.sol";
import { NFATInit, NFATConfig } from "deploy/NFATInit.sol";
import { IERC721Errors } from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";

interface SUsdsLike {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external;
}

contract IdentityNetworkMock {
    mapping(address => bool) public members;
    function setMember(address account, bool status) external { members[account] = status; }
    function isMember(address account) external view returns (bool) { return members[account]; }
}

contract ERC721ReceiverMock {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract BadReceiverMock {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0xdeadbeef;
    }
}

contract NFATFacilityTest is DssTest {
    DssInstance           dss;
    NFATFacility          facility;
    SUsdsLike             susds;
    IdentityNetworkMock   idNet;
    ERC721ReceiverMock    receiver;
    BadReceiverMock       badReceiver;

    address almProxy   = address(0xA1);
    address pauseProxy;
    address operator   = address(0xC1);
    address freezer    = address(0xC2);
    address prime1     = address(0xB1);
    address prime2     = address(0xB2);

    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event AddFreezer(address indexed usr);
    event RemoveFreezer(address indexed usr);
    event Stop();
    event Start();
    event Subscribe(address indexed depositor, uint256 amount);
    event Withdraw(address indexed depositor, uint256 amount);
    event Issue(address indexed target, uint256 indexed tokenId, uint256 amount);
    event Fund(uint256 indexed tokenId, address indexed funder, uint256 amount);
    event Redeem(uint256 indexed tokenId, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        dss        = MCD.loadFromChainlog(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
        pauseProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");

        idNet       = new IdentityNetworkMock();
        receiver    = new ERC721ReceiverMock();
        badReceiver = new BadReceiverMock();

        // Deploy via NFATDeploy (owner = pauseProxy)
        address facility_ = NFATDeploy.deploy(address(this), pauseProxy, almProxy, "Non-Fungible Allocation Token - Halo1", "NFAT-HALO1");
        facility = NFATFacility(facility_);
        susds    = SUsdsLike(address(facility.gem()));

        // Init via NFATInit as pauseProxy
        address[] memory _freezers = new address[](1);
        _freezers[0] = freezer;
        NFATConfig memory cfg = NFATConfig({
            facilityKey:     "NFAT_FAC_HALO1",
            almProxy:        almProxy,
            identityNetwork: address(0),
            operator:        operator,
            freezers:        _freezers
        });
        vm.startPrank(pauseProxy);
        NFATInit.init(dss, facility_, cfg);
        vm.stopPrank();

        // Fund primes
        deal(address(susds), prime1, 1000 ether);
        deal(address(susds), prime2, 1000 ether);
        vm.prank(prime1); susds.approve(address(facility), type(uint256).max);
        vm.prank(prime2); susds.approve(address(facility), type(uint256).max);
    }

    // --- Helpers ---

    function _subscribe(address who, uint256 amount) internal {
        vm.prank(who); facility.subscribe(amount);
    }

    function _issue(address target, uint256 amount) internal returns (uint256 tokenId) {
        tokenId = vm.randomUint();
        vm.prank(operator); facility.issue(target, amount, tokenId);
    }

    function _fundToken(uint256 tokenId, uint256 amount) internal {
        deal(address(susds), address(this), susds.balanceOf(address(this)) + amount);
        susds.approve(address(facility), amount);
        facility.fund(tokenId, amount);
    }

    // --- Deploy & Init ---

    function testDeployAndInit() public view {
        assertEq(facility.wards(pauseProxy), 1);

        // Freezer configured by init
        assertEq(facility.cops(freezer), 1);

        // Operator configured by init
        assertEq(facility.buds(operator), 1);

        // Chainlog entry
        assertEq(dss.chainlog.getAddress("NFAT_FAC_HALO1"), address(facility));
    }

    // --- Access Control ---

    function testAuth() public {
        checkAuth(address(facility), "NFATFacility");
    }

    function testFile() public {
        checkFileAddress(address(facility), "NFATFacility", ["identityNetwork"]);
    }

    function testModifiers() public {
        vm.startPrank(address(0xBEEF));
        checkModifier(address(facility), "NFATFacility/not-authorized", [
            facility.kiss.selector,
            facility.diss.selector,
            facility.addFreezer.selector,
            facility.removeFreezer.selector,
            facility.start.selector
        ]);
        vm.stopPrank();

        checkModifier(address(facility), "NFATFacility/not-operator", [
            facility.issue.selector
        ]);
        checkModifier(address(facility), "NFATFacility/not-freezer", [
            facility.stop.selector
        ]);
    }

    function testKissDiss() public {
        address who = address(0xb0b);
        assertEq(facility.buds(who), 0);

        vm.expectEmit(true, true, true, true);
        emit Kiss(who);
        vm.prank(pauseProxy); facility.kiss(who);
        assertEq(facility.buds(who), 1);

        vm.expectEmit(true, true, true, true);
        emit Diss(who);
        vm.prank(pauseProxy); facility.diss(who);
        assertEq(facility.buds(who), 0);
    }

    function testAddRemoveFreezer() public {
        address who = address(0xb0b);
        assertEq(facility.cops(who), 0);

        vm.expectEmit(true, true, true, true);
        emit AddFreezer(who);
        vm.prank(pauseProxy); facility.addFreezer(who);
        assertEq(facility.cops(who), 1);

        vm.expectEmit(true, true, true, true);
        emit RemoveFreezer(who);
        vm.prank(pauseProxy); facility.removeFreezer(who);
        assertEq(facility.cops(who), 0);
    }

    function testStopStart() public {
        _subscribe(prime1, 100 ether);

        // issue works before stop
        vm.prank(operator); facility.issue(prime1, 25 ether, 0);

        // stop
        vm.expectEmit(true, true, true, true);
        emit Stop();
        vm.prank(freezer); facility.stop();
        assertTrue(facility.stopped());

        // issue reverts while stopped
        vm.expectRevert("NFATFacility/stopped");
        vm.prank(operator); facility.issue(prime1, 25 ether, 1);

        // start
        vm.expectEmit(true, true, true, true);
        emit Start();
        vm.prank(pauseProxy); facility.start();
        assertTrue(!facility.stopped());

        // issue works again after start
        vm.prank(operator); facility.issue(prime1, 25 ether, 1);
    }

    // --- Queue ---

    function testSubscribe() public {
        vm.expectEmit(true, true, true, true);
        emit Subscribe(prime1, 100 ether);
        _subscribe(prime1, 100 ether);

        assertEq(facility.deposits(prime1), 100 ether);
        assertEq(susds.balanceOf(address(facility)), 100 ether);
    }

    function testRevertSubscribeZeroAmount() public {
        vm.expectRevert("NFATFacility/zero-amount");
        vm.prank(prime1); facility.subscribe(0);
    }

    function testWithdraw() public {
        _subscribe(prime1, 100 ether);

        // Partial withdraw
        vm.expectEmit(true, true, true, true);
        emit Withdraw(prime1, 40 ether);
        vm.prank(prime1); facility.withdraw(40 ether);

        assertEq(facility.deposits(prime1), 60 ether);
        assertEq(susds.balanceOf(prime1), 940 ether);

        // Withdraw remainder
        vm.prank(prime1); facility.withdraw(60 ether);

        assertEq(facility.deposits(prime1), 0);
        assertEq(susds.balanceOf(prime1), 1000 ether);
    }

    function testRevertWithdrawZeroAmount() public {
        vm.expectRevert("NFATFacility/zero-amount");
        vm.prank(prime1); facility.withdraw(0);
    }

    function testRevertWithdrawInsufficientDeposits() public {
        _subscribe(prime1, 100 ether);

        vm.expectRevert("NFATFacility/insufficient-deposits");
        vm.prank(prime1); facility.withdraw(101 ether);
    }

    // --- Issue ---

    function testIssue() public {
        _subscribe(prime1, 100 ether);

        // First issue
        uint256 tokenId0 = _issue(prime1, 60 ether);

        assertEq(facility.ownerOf(tokenId0), prime1);
        assertEq(facility.balanceOf(prime1), 1);
        assertEq(facility.deposits(prime1), 40 ether);
        assertEq(susds.balanceOf(almProxy), 60 ether);

        // Second issue
        uint256 tokenId1 = _issue(prime1, 30 ether);

        assertEq(facility.ownerOf(tokenId1), prime1);
        assertEq(facility.balanceOf(prime1), 2);
        assertEq(facility.deposits(prime1), 10 ether);
    }

    function testIssueZeroAmount() public {
        uint256 depositsBefore = facility.deposits(prime1);
        uint256 almBalBefore   = susds.balanceOf(almProxy);

        vm.prank(operator); facility.issue(prime1, 0, 0);

        assertEq(facility.ownerOf(0), prime1);
        assertEq(facility.deposits(prime1), depositsBefore);
        assertEq(susds.balanceOf(almProxy), almBalBefore);
    }

    function testRevertIssueInsufficientDeposits() public {
        _subscribe(prime1, 100 ether);

        vm.expectRevert("NFATFacility/insufficient-deposits");
        vm.prank(operator); facility.issue(prime1, 101 ether, 0);
    }

    function testRevertIssueStopped() public {
        _subscribe(prime1, 100 ether);
        vm.prank(pauseProxy); facility.stop();

        vm.expectRevert("NFATFacility/stopped");
        vm.prank(operator); facility.issue(prime1, 50 ether, 0);
    }

    function testIssueWithIdentityNetwork() public {
        vm.prank(pauseProxy); facility.file("identityNetwork", address(idNet));
        idNet.setMember(prime1, true);

        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 50 ether);

        assertEq(facility.ownerOf(tokenId), prime1);
    }

    function testRevertIssueTargetNotMember() public {
        vm.prank(pauseProxy); facility.file("identityNetwork", address(idNet));

        _subscribe(prime1, 100 ether);

        vm.expectRevert("NFATFacility/not-member");
        vm.prank(operator); facility.issue(prime1, 50 ether, 0);
    }

    // --- Fund ---

    function testFund() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        // First fund
        deal(address(susds), address(this), 50 ether);
        susds.approve(address(facility), 50 ether);

        vm.expectEmit(true, true, true, true);
        emit Fund(tokenId, address(this), 50 ether);
        facility.fund(tokenId, 50 ether);

        assertEq(facility.funded(tokenId), 50 ether);

        // Second fund accumulates
        _fundToken(tokenId, 20 ether);

        assertEq(facility.funded(tokenId), 70 ether);
    }

    function testRevertFundInvalidToken() public {
        vm.expectRevert("NFATFacility/invalid-token");
        facility.fund(999, 1 ether);
    }

    function testRevertFundZeroAmount() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        vm.expectRevert("NFATFacility/zero-amount");
        facility.fund(tokenId, 0);
    }

    // --- Redeem ---

    function testRedeem() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);
        _fundToken(tokenId, 80 ether);

        uint256 balBefore = susds.balanceOf(prime1);

        // Partial redeem
        vm.expectEmit(true, true, true, true);
        emit Redeem(tokenId, 30 ether);
        vm.prank(prime1); facility.redeem(tokenId, 30 ether);

        assertEq(facility.funded(tokenId), 50 ether);
        assertEq(susds.balanceOf(prime1), balBefore + 30 ether);

        // Redeem remainder
        vm.prank(prime1); facility.redeem(tokenId, 50 ether);

        assertEq(facility.funded(tokenId), 0);
        assertEq(susds.balanceOf(prime1), balBefore + 80 ether);
    }

    function testRevertRedeemZeroAmount() public {
        vm.expectRevert("NFATFacility/zero-amount");
        vm.prank(prime1); facility.redeem(0, 0);
    }

    function testRevertRedeemInsufficientFunded() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);
        _fundToken(tokenId, 10 ether);

        vm.expectRevert("NFATFacility/insufficient-funded");
        vm.prank(prime1); facility.redeem(tokenId, 11 ether);
    }

    function testRevertRedeemNotMember() public {
        vm.prank(pauseProxy); facility.file("identityNetwork", address(idNet));
        idNet.setMember(prime1, true);

        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);
        _fundToken(tokenId, 50 ether);

        // prime1 gets de-whitelisted after funding
        idNet.setMember(prime1, false);

        vm.expectRevert("NFATFacility/not-member");
        vm.prank(prime1); facility.redeem(tokenId, 50 ether);
    }

    function testRevertRedeemNotOwner() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);
        _fundToken(tokenId, 50 ether);

        vm.expectRevert("NFATFacility/not-owner");
        vm.prank(prime2); facility.redeem(tokenId, 50 ether);
    }

    // --- ERC-721 ---

    function testTransferFrom() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        vm.expectEmit(true, true, true, true);
        emit Transfer(prime1, prime2, tokenId);
        vm.prank(prime1); facility.transferFrom(prime1, prime2, tokenId);

        assertEq(facility.ownerOf(tokenId), prime2);
        assertEq(facility.balanceOf(prime1), 0);
        assertEq(facility.balanceOf(prime2), 1);
    }

    function testTransferFromWithApproval() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        vm.prank(prime1); facility.approve(prime2, tokenId);
        assertEq(facility.getApproved(tokenId), prime2);

        vm.prank(prime2); facility.transferFrom(prime1, prime2, tokenId);

        assertEq(facility.ownerOf(tokenId), prime2);
        assertEq(facility.getApproved(tokenId), address(0)); // approval cleared
    }

    function testTransferFromWithOperatorApproval() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        vm.prank(prime1); facility.setApprovalForAll(prime2, true);
        vm.prank(prime2); facility.transferFrom(prime1, prime2, tokenId);

        assertEq(facility.ownerOf(tokenId), prime2);
    }

    function testRevertTransferFromNotAuthorized() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, prime2, tokenId));
        vm.prank(prime2); facility.transferFrom(prime1, prime2, tokenId);
    }

    function testRevertTransferFromWrongFrom() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721IncorrectOwner.selector, prime2, tokenId, prime1));
        vm.prank(prime1); facility.transferFrom(prime2, prime2, tokenId);
    }

    function testRevertTransferFromZeroAddress() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(0)));
        vm.prank(prime1); facility.transferFrom(prime1, address(0), tokenId);
    }

    function testTransferFromWithIdentityNetwork() public {
        vm.prank(pauseProxy); facility.file("identityNetwork", address(idNet));
        idNet.setMember(prime1, true);
        idNet.setMember(prime2, true);

        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        // Reverts when `to` is not a member
        idNet.setMember(prime2, false);
        vm.expectRevert("NFATFacility/not-member");
        vm.prank(prime1); facility.transferFrom(prime1, prime2, tokenId);

        // Succeeds when `to` is a member
        idNet.setMember(prime2, true);
        vm.prank(prime1); facility.transferFrom(prime1, prime2, tokenId);
        assertEq(facility.ownerOf(tokenId), prime2);

        // Sender membership is not checked
        idNet.setMember(prime2, false);
        vm.prank(prime2); facility.transferFrom(prime2, prime1, tokenId);
        assertEq(facility.ownerOf(tokenId), prime1);
    }

    function testSafeTransferFrom() public {
        _subscribe(prime1, 100 ether);

        // To EOA
        uint256 tokenId0 = _issue(prime1, 50 ether);
        vm.prank(prime1); facility.safeTransferFrom(prime1, prime2, tokenId0);
        assertEq(facility.ownerOf(tokenId0), prime2);

        // To contract implementing onERC721Received
        uint256 tokenId1 = _issue(prime1, 50 ether);
        vm.prank(prime1); facility.safeTransferFrom(prime1, address(receiver), tokenId1, "test data");
        assertEq(facility.ownerOf(tokenId1), address(receiver));
    }

    function testRevertSafeTransferFromUnsafeRecipient() public {
        _subscribe(prime1, 100 ether);

        // Bad return value
        uint256 tokenId0 = _issue(prime1, 50 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(badReceiver)));
        vm.prank(prime1); facility.safeTransferFrom(prime1, address(badReceiver), tokenId0);

        // No onERC721Received at all
        uint256 tokenId1 = _issue(prime1, 50 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(facility)));
        vm.prank(prime1); facility.safeTransferFrom(prime1, address(facility), tokenId1);
    }

    function testApprove() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        // Owner approves
        vm.expectEmit(true, true, true, true);
        emit Approval(prime1, prime2, tokenId);
        vm.prank(prime1); facility.approve(prime2, tokenId);
        assertEq(facility.getApproved(tokenId), prime2);

        // Operator approves
        vm.prank(prime1); facility.setApprovalForAll(prime2, true);
        vm.prank(prime2); facility.approve(operator, tokenId);
        assertEq(facility.getApproved(tokenId), operator);
    }

    function testRevertApproveNotAuthorized() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidApprover.selector, prime2));
        vm.prank(prime2); facility.approve(prime2, tokenId);
    }

    function testSetApprovalForAll() public {
        vm.expectEmit(true, true, true, true);
        emit ApprovalForAll(prime1, prime2, true);
        vm.prank(prime1); facility.setApprovalForAll(prime2, true);

        assertTrue(facility.isApprovedForAll(prime1, prime2));
    }

    function testRevertSetApprovalForAllZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidOperator.selector, address(0)));
        vm.prank(prime1); facility.setApprovalForAll(address(0), true);
    }

    function testRevertOwnerOfInvalidToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999)));
        facility.ownerOf(999);
    }

    function testRevertBalanceOfZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidOwner.selector, address(0)));
        facility.balanceOf(address(0));
    }

    function testRevertGetApprovedInvalidToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999)));
        facility.getApproved(999);
    }

    // --- Metadata & ERC-165 ---

    function testMetadataAndERC165() public view {
        assertEq(facility.name(), "Non-Fungible Allocation Token - Halo1");
        assertEq(facility.symbol(), "NFAT-HALO1");
        assertTrue(facility.supportsInterface(0x01ffc9a7));  // ERC-165
        assertTrue(facility.supportsInterface(0x80ac58cd));  // ERC-721
        assertTrue(!facility.supportsInterface(0xdeadbeef)); // random
    }
}
