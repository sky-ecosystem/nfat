// SPDX-FileCopyrightText: © 2026 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.24;

interface GemLike {
    function transferFrom(address from, address to, uint256 amount) external;
    function transfer(address to, uint256 amount) external;
}

interface IdentityNetworkLike {
    function isMember(address account) external view returns (bool);
}

interface ERC721ReceiverLike {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

/// @title NFATFacility
/// @notice Non-Fungible Allocation Token Facility for bespoke capital deployment deals
/// @dev Implements queue-based deposits and ERC-721 NFAT minting
contract NFATFacility {

    // --- Immutables ---

    GemLike public immutable gem;        // Underlying asset
    address public immutable almProxy;   // Custody destination for claimed funds

    // --- Access Control Storage ---

    mapping(address usr => uint256 allowed)   public wards;
    mapping(address usr => bytes32 rolesData) public userRoles;
    mapping(bytes4  sig => bytes32 rolesData) public actionsRoles;
    bool    public stopped;
    address public identityNetwork;

    // --- Queue Storage ---

    mapping(address depositor => uint256 amount) public deposits;

    // --- Redeem Storage ---

    mapping(uint256 tokenId => uint256 amount) public funded;

    // --- NFAT Storage ---

    mapping(uint256 tokenId => address owner)           internal _owners;
    mapping(address owner => uint256 count)             internal _balances;
    mapping(uint256 tokenId => address approved)        internal _tokenApprovals;
    mapping(address owner => mapping(address operator => bool approved)) internal _operatorApprovals;
    uint256 public nextTokenId;

    // --- Events: Access Control ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event SetUserRole(address indexed who, uint8 indexed role, bool enabled);
    event SetRoleAction(uint8 indexed role, bytes4 sig, bool enabled);
    event Stop();
    event Start();
    event File(bytes32 indexed what, address data);

    // --- Events: Queue ---

    event Subscribe(address indexed depositor, uint256 amount);
    event Withdraw(address indexed depositor, uint256 amount);
    event Claim(address indexed target, uint256 indexed tokenId, uint256 amount);

    // --- Events: Redeem ---

    event Fund(uint256 indexed tokenId, address indexed funder, uint256 amount);
    event Redeem(uint256 indexed tokenId, uint256 amount);

    // --- Events: ERC-721 ---

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // --- Modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "NFATFacility/not-authorized");
        _;
    }

    modifier roleAuth() {
        require(
            userRoles[msg.sender] & actionsRoles[msg.sig] != bytes32(0) ||
            wards[msg.sender] == 1,
            "NFATFacility/role-not-authorized"
        );
        _;
    }

    modifier notStopped() {
        require(!stopped, "NFATFacility/stopped");
        _;
    }

    // --- Constructor ---

    constructor(address gem_, address almProxy_) {
        gem = GemLike(gem_);
        almProxy = almProxy_;
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Access Control Functions ---

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function setUserRole(address who, uint8 role, bool enabled) external auth {
        bytes32 mask = bytes32(uint256(1) << role);
        if (enabled) {
            userRoles[who] |= mask;
        } else {
            userRoles[who] &= ~mask;
        }
        emit SetUserRole(who, role, enabled);
    }

    function setRoleAction(uint8 role, bytes4 sig, bool enabled) external auth {
        bytes32 mask = bytes32(uint256(1) << role);
        if (enabled) {
            actionsRoles[sig] |= mask;
        } else {
            actionsRoles[sig] &= ~mask;
        }
        emit SetRoleAction(role, sig, enabled);
    }

    function stop() external roleAuth {
        stopped = true;
        emit Stop();
    }

    function start() external auth {
        stopped = false;
        emit Start();
    }

    function file(bytes32 what, address data) external auth {
        if (what == "identityNetwork") identityNetwork = data;
        else revert("NFATFacility/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Queue Functions ---

    /// @notice Prime deposits gem into the queue
    /// @param amount The amount of gem to deposit
    function subscribe(uint256 amount) external {
        require(amount > 0, "NFATFacility/zero-amount");

        // Effects
        deposits[msg.sender] += amount;

        // Interactions
        gem.transferFrom(msg.sender, address(this), amount);

        emit Subscribe(msg.sender, amount);
    }

    /// @notice Prime withdraws gem from the queue
    /// @param amount The amount of gem to withdraw
    function withdraw(uint256 amount) external {
        require(amount > 0, "NFATFacility/zero-amount");
        require(deposits[msg.sender] >= amount, "NFATFacility/insufficient-deposits");

        // Effects
        unchecked { deposits[msg.sender] -= amount; }

        // Interactions
        gem.transfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    /// @notice Sentinel claims from queue, mints NFAT to target
    /// @param target The Prime address to mint the NFAT to
    /// @param amount The amount of gem to claim
    function claim(address target, uint256 amount) external roleAuth notStopped {
        require(amount > 0, "NFATFacility/zero-amount");
        require(deposits[target] >= amount, "NFATFacility/insufficient-deposits");

        require(identityNetwork == address(0) || IdentityNetworkLike(identityNetwork).isMember(target), "NFATFacility/target-not-member");

        uint256 tokenId = nextTokenId++;

        // Effects - Queue
        unchecked { deposits[target] -= amount; }

        // Effects - NFAT
        _owners[tokenId] = target;
        _balances[target] += 1;

        // Interactions
        gem.transfer(almProxy, amount);

        emit Claim(target, tokenId, amount);
        emit Transfer(address(0), target, tokenId);
    }

    // --- Redeem Functions ---

    /// @notice Deposit funds for NFAT redemption
    /// @param tokenId The NFAT to fund
    /// @param amount The amount of gem to deposit
    function fund(uint256 tokenId, uint256 amount) external {
        require(_owners[tokenId] != address(0), "NFATFacility/invalid-token");
        require(amount > 0, "NFATFacility/zero-amount");

        // Effects
        funded[tokenId] += amount;

        // Interactions
        gem.transferFrom(msg.sender, address(this), amount);

        emit Fund(tokenId, msg.sender, amount);
    }

    /// @notice NFAT holder claims specified amount from funded balance
    /// @param tokenId The NFAT to redeem from
    /// @param amount The amount of gem to claim
    function redeem(uint256 tokenId, uint256 amount) external {
        require(amount > 0, "NFATFacility/zero-amount");
        require(funded[tokenId] >= amount, "NFATFacility/insufficient-funded");

        address owner = _owners[tokenId];
        require(msg.sender == owner, "NFATFacility/not-owner");

        // Effects
        unchecked { funded[tokenId] -= amount; }

        // Interactions
        gem.transfer(owner, amount);

        emit Redeem(tokenId, amount);
    }

    // --- ERC-721 Functions ---

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "NFATFacility/invalid-token");
        return owner;
    }

    function balanceOf(address owner) external view returns (uint256) {
        require(owner != address(0), "NFATFacility/zero-address");
        return _balances[owner];
    }

    function approve(address to, uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        require(msg.sender == owner || _operatorApprovals[owner][msg.sender], "NFATFacility/not-authorized");
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        require(_owners[tokenId] != address(0), "NFATFacility/invalid-token");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        require(operator != msg.sender, "NFATFacility/self-approval");
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "NFATFacility/not-authorized");
        require(ownerOf(tokenId) == from, "NFATFacility/wrong-from");
        require(to != address(0), "NFATFacility/zero-address");

        require(identityNetwork == address(0) || IdentityNetworkLike(identityNetwork).isMember(to), "NFATFacility/to-not-member");

        // Clear approval
        _tokenApprovals[tokenId] = address(0);

        // Effects
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, data), "NFATFacility/unsafe-recipient");
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || _tokenApprovals[tokenId] == spender || _operatorApprovals[owner][spender]);
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data) internal returns (bool) {
        if (to.code.length == 0) {
            return true;
        }
        try ERC721ReceiverLike(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
            return retval == ERC721ReceiverLike.onERC721Received.selector;
        } catch {
            return false;
        }
    }

    // --- View Functions ---

    // --- Roles  ---

    /// @notice Check if a user has a specific role
    /// @param usr The address to check
    /// @param role The role ID
    /// @return has Whether the user has the role
    function hasUserRole(address usr, uint8 role) external view returns (bool has) {
        has = userRoles[usr] & bytes32(uint256(1) << role) != bytes32(0);
    }

    /// @notice Check if an action is assigned to a role
    /// @param sig The function signature
    /// @param role The role ID
    /// @return has Whether the action is in the role
    function isActionInRole(bytes4 sig, uint8 role) external view returns (bool has) {
        has = actionsRoles[sig] & bytes32(uint256(1) << role) != bytes32(0);
    }

    // --- ERC-721 Metadata  ---

    function name() external pure returns (string memory) {
        return "Non-Fungible Allocation Token";
    }

    function symbol() external pure returns (string memory) {
        return "NFAT";
    }

    // --- ERC-165 ---

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC-165
            interfaceId == 0x80ac58cd;   // ERC-721
    }
}
