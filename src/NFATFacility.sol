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

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title NFATFacility
/// @notice Non-Fungible Allocation Token Facility for bespoke capital deployment deals
/// @dev Implements queue-based deposits, ERC-721 NFAT minting, and redemption mechanics
contract NFATFacility {

    // --- Immutables ---

    IERC20  public immutable sUSDS;      // Underlying asset
    address public immutable almProxy;   // Custody destination for claimed funds

    // --- Access Control Storage ---

    mapping(address usr => uint256 allowed)   public wards;
    mapping(address usr => bytes32 rolesData) public userRoles;
    mapping(bytes4  sig => bytes32 rolesData) public actionsRoles;
    bool public stopped;

    // --- Queue Storage ---

    uint256 public totalDeposits;
    mapping(address depositor => uint256 amount) public deposits;

    // --- NFAT Storage ---

    uint256 public nextTokenId;

    struct NFATData {
        uint256 principal;   // Current principal (mutable via spend)
        address depositor;   // Original Prime address (immutable)
        uint40  mintedAt;    // Mint timestamp
    }

    mapping(uint256 tokenId => NFATData data)           internal _nfats;
    mapping(uint256 tokenId => address owner)           internal _owners;
    mapping(address owner => uint256 count)             internal _balances;
    mapping(uint256 tokenId => address approved)        internal _tokenApprovals;
    mapping(address owner => mapping(address operator => bool approved)) internal _operatorApprovals;

    // --- Redeemer Storage ---

    address public redeemer;

    // --- Whitelist Storage ---

    bool public whitelistEnabled;
    mapping(address account => bool allowed) public whitelist;

    // --- Events: Access Control ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event SetUserRole(address indexed who, uint8 indexed role, bool enabled);
    event SetRoleAction(uint8 indexed role, bytes4 sig, bool enabled);
    event Stop();
    event Start();

    // --- Events: Queue ---

    event Subscribe(address indexed depositor, uint256 amount);
    event Withdraw(address indexed depositor, uint256 amount);
    event Claim(address indexed target, uint256 indexed tokenId, uint256 amount);

    // --- Events: ERC-721 ---

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // --- Events: Redeemer ---

    event SetRedeemer(address indexed redeemer);

    // --- Events: Whitelist ---

    event WhitelistEnabled(bool enabled);
    event WhitelistUpdated(address indexed account, bool allowed);

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

    constructor(address sUSDS_, address almProxy_) {
        sUSDS = IERC20(sUSDS_);
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

    function stop() external auth {
        stopped = true;
        emit Stop();
    }

    function start() external auth {
        stopped = false;
        emit Start();
    }

    // --- Queue Functions ---

    /// @notice Prime deposits sUSDS into the queue
    /// @param amount The amount of sUSDS to deposit
    function subscribe(uint256 amount) external notStopped {
        require(amount > 0, "NFATFacility/zero-amount");

        // Effects
        deposits[msg.sender] += amount;
        totalDeposits += amount;

        // Interactions
        require(sUSDS.transferFrom(msg.sender, address(this), amount), "NFATFacility/transfer-failed");

        emit Subscribe(msg.sender, amount);
    }

    /// @notice Prime withdraws all deposited sUSDS (full exit from queue)
    function withdraw() external notStopped {
        uint256 amount = deposits[msg.sender];
        require(amount > 0, "NFATFacility/no-deposits");

        // Effects
        deposits[msg.sender] = 0;
        totalDeposits -= amount;

        // Interactions
        require(sUSDS.transfer(msg.sender, amount), "NFATFacility/transfer-failed");

        emit Withdraw(msg.sender, amount);
    }

    /// @notice Sentinel claims from queue, mints NFAT to target
    /// @param target The Prime address to mint the NFAT to
    /// @param amount The amount of sUSDS to claim
    function claim(address target, uint256 amount) external roleAuth notStopped {
        require(amount > 0, "NFATFacility/zero-amount");
        require(deposits[target] >= amount, "NFATFacility/insufficient-deposits");

        uint256 tokenId = nextTokenId++;

        // Effects - Queue
        deposits[target] -= amount;
        totalDeposits -= amount;

        // Effects - NFAT
        _nfats[tokenId] = NFATData({
            principal: amount,
            depositor: target,
            mintedAt: uint40(block.timestamp)
        });
        _owners[tokenId] = target;
        _balances[target] += 1;

        // Interactions
        require(sUSDS.transfer(almProxy, amount), "NFATFacility/transfer-failed");

        emit Claim(target, tokenId, amount);
        emit Transfer(address(0), target, tokenId);
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

    function transferFrom(address from, address to, uint256 tokenId) public notStopped {
        require(_isApprovedOrOwner(msg.sender, tokenId), "NFATFacility/not-authorized");
        require(ownerOf(tokenId) == from, "NFATFacility/wrong-from");
        require(to != address(0), "NFATFacility/zero-address");

        if (whitelistEnabled) {
            require(whitelist[to], "NFATFacility/not-whitelisted");
        }

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
        try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
            return retval == IERC721Receiver.onERC721Received.selector;
        } catch {
            return false;
        }
    }

    // --- Redeemer Functions ---

    /// @notice Set the redeemer contract address
    /// @param redeemer_ The address of the redeemer contract
    function setRedeemer(address redeemer_) external auth {
        redeemer = redeemer_;
        emit SetRedeemer(redeemer_);
    }

    /// @notice Burns an NFAT token (only callable by redeemer)
    /// @param tokenId The NFAT to burn
    function burn(uint256 tokenId) external {
        require(msg.sender == redeemer, "NFATFacility/not-redeemer");

        address owner = _owners[tokenId];
        require(owner != address(0), "NFATFacility/invalid-token");

        // Effects - Burn NFAT
        _tokenApprovals[tokenId] = address(0);
        _balances[owner] -= 1;
        delete _owners[tokenId];
        delete _nfats[tokenId];

        emit Transfer(owner, address(0), tokenId);
    }

    /// @notice Reduces principal of an NFAT (only callable by redeemer)
    /// @param tokenId The NFAT to modify
    /// @param amount The amount to reduce principal by
    function reducePrincipal(uint256 tokenId, uint256 amount) external {
        require(msg.sender == redeemer, "NFATFacility/not-redeemer");
        require(_owners[tokenId] != address(0), "NFATFacility/invalid-token");

        NFATData storage nfat = _nfats[tokenId];
        require(nfat.principal >= amount, "NFATFacility/exceeds-principal");

        nfat.principal -= amount;
    }

    /// @notice Check if an address is approved or owner of a token
    /// @param spender The address to check
    /// @param tokenId The token to check
    /// @return Whether the spender is approved or owner
    function isApprovedOrOwner(address spender, uint256 tokenId) external view returns (bool) {
        return _isApprovedOrOwner(spender, tokenId);
    }

    // --- Whitelist Functions ---

    /// @notice Enable or disable transfer restrictions
    /// @param enabled Whether to enable the whitelist
    function setWhitelistEnabled(bool enabled) external roleAuth {
        whitelistEnabled = enabled;
        emit WhitelistEnabled(enabled);
    }

    /// @notice Add or remove an address from the whitelist
    /// @param account The address to update
    /// @param allowed Whether the address is allowed
    function setWhitelist(address account, bool allowed) external roleAuth {
        whitelist[account] = allowed;
        emit WhitelistUpdated(account, allowed);
    }

    // --- View Functions ---

    /// @notice Get a depositor's balance in the queue
    /// @param depositor The address to query
    /// @return The deposited sUSDS amount
    function getQueueBalance(address depositor) external view returns (uint256) {
        return deposits[depositor];
    }

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

    /// @notice Get the principal of an NFAT
    /// @param tokenId The NFAT to query
    /// @return The current principal
    function getPrincipal(uint256 tokenId) external view returns (uint256) {
        require(_owners[tokenId] != address(0), "NFATFacility/invalid-token");
        return _nfats[tokenId].principal;
    }

    /// @notice Get the original depositor of an NFAT
    /// @param tokenId The NFAT to query
    /// @return The depositor address
    function getDepositor(uint256 tokenId) external view returns (address) {
        require(_owners[tokenId] != address(0), "NFATFacility/invalid-token");
        return _nfats[tokenId].depositor;
    }

    /// @notice Get the mint timestamp of an NFAT
    /// @param tokenId The NFAT to query
    /// @return The mint timestamp
    function getMintedAt(uint256 tokenId) external view returns (uint40) {
        require(_owners[tokenId] != address(0), "NFATFacility/invalid-token");
        return _nfats[tokenId].mintedAt;
    }

    // --- ERC-721 Metadata (Optional) ---

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
            interfaceId == 0x80ac58cd || // ERC-721
            interfaceId == 0x5b5e139f;   // ERC-721 Metadata
    }
}

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}
