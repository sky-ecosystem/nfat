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

interface INFATFacility {
    function sUSDS() external view returns (IERC20);
    function ownerOf(uint256 tokenId) external view returns (address);
    function isApprovedOrOwner(address spender, uint256 tokenId) external view returns (bool);
    function getPrincipal(uint256 tokenId) external view returns (uint256);
    function burn(uint256 tokenId) external;
    function reducePrincipal(uint256 tokenId, uint256 amount) external;
}

/// @title NFATRedeemer
/// @notice Handles redemption mechanics for Non-Fungible Allocation Tokens
/// @dev Separated from NFATFacility to allow modular upgrades to redemption logic
contract NFATRedeemer {

    // --- Immutables ---

    INFATFacility public immutable facility;
    IERC20        public immutable sUSDS;

    // --- Access Control Storage ---

    mapping(address usr => uint256 allowed)   public wards;
    mapping(address usr => bytes32 rolesData) public userRoles;
    mapping(bytes4  sig => bytes32 rolesData) public actionsRoles;
    bool public stopped;

    // --- Redeem Storage ---

    mapping(uint256 tokenId => uint256 amount) public funded;

    // --- Events: Access Control ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event SetUserRole(address indexed who, uint8 indexed role, bool enabled);
    event SetRoleAction(uint8 indexed role, bytes4 sig, bool enabled);
    event Stop();
    event Start();

    // --- Events: Redeem ---

    event Fund(uint256 indexed tokenId, uint256 amount);
    event Redeem(uint256 indexed tokenId, uint256 amount);
    event Spend(uint256 indexed tokenId, uint256 amount, uint256 remainingPrincipal);

    // --- Modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "NFATRedeemer/not-authorized");
        _;
    }

    modifier roleAuth() {
        require(
            userRoles[msg.sender] & actionsRoles[msg.sig] != bytes32(0) ||
            wards[msg.sender] == 1,
            "NFATRedeemer/role-not-authorized"
        );
        _;
    }

    modifier notStopped() {
        require(!stopped, "NFATRedeemer/stopped");
        _;
    }

    // --- Constructor ---

    constructor(address facility_) {
        facility = INFATFacility(facility_);
        sUSDS = facility.sUSDS();
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

    // --- Redeem Functions ---

    /// @notice Keeper deposits funds for NFAT redemption on behalf of Halo
    /// @param tokenId The NFAT to fund
    /// @param amount The amount of sUSDS to deposit
    function fund(uint256 tokenId, uint256 amount) external roleAuth notStopped {
        require(facility.ownerOf(tokenId) != address(0), "NFATRedeemer/invalid-token");
        require(amount > 0, "NFATRedeemer/zero-amount");

        // Effects
        funded[tokenId] += amount;

        // Interactions
        require(sUSDS.transferFrom(msg.sender, address(this), amount), "NFATRedeemer/transfer-failed");

        emit Fund(tokenId, amount);
    }

    /// @notice NFAT holder burns token, receives funded amount
    /// @param tokenId The NFAT to redeem
    function redeem(uint256 tokenId) external notStopped {
        require(facility.isApprovedOrOwner(msg.sender, tokenId), "NFATRedeemer/not-authorized");

        uint256 amount = funded[tokenId];
        require(amount > 0, "NFATRedeemer/not-funded");

        address owner = facility.ownerOf(tokenId);

        // Effects
        delete funded[tokenId];

        // Interactions - Burn NFAT via facility
        facility.burn(tokenId);

        // Interactions - Transfer funds to owner
        require(sUSDS.transfer(owner, amount), "NFATRedeemer/transfer-failed");

        emit Redeem(tokenId, amount);
    }

    /// @notice Partial claim for amortizing loans - reduces principal
    /// @param tokenId The NFAT to spend from
    /// @param amount The amount to claim
    function spend(uint256 tokenId, uint256 amount) external notStopped {
        require(facility.isApprovedOrOwner(msg.sender, tokenId), "NFATRedeemer/not-authorized");
        require(amount > 0, "NFATRedeemer/zero-amount");
        require(funded[tokenId] >= amount, "NFATRedeemer/insufficient-funded");

        uint256 principal = facility.getPrincipal(tokenId);
        require(principal >= amount, "NFATRedeemer/exceeds-principal");

        address owner = facility.ownerOf(tokenId);

        // Effects
        funded[tokenId] -= amount;

        // Interactions - Reduce principal via facility
        facility.reducePrincipal(tokenId, amount);

        // Interactions - Transfer funds to owner
        require(sUSDS.transfer(owner, amount), "NFATRedeemer/transfer-failed");

        uint256 remainingPrincipal = facility.getPrincipal(tokenId);
        emit Spend(tokenId, amount, remainingPrincipal);
    }

    // --- View Functions ---

    /// @notice Get the funded amount for an NFAT
    /// @param tokenId The NFAT to query
    /// @return The funded amount
    function getFunded(uint256 tokenId) external view returns (uint256) {
        return funded[tokenId];
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
}
