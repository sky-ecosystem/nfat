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

import { ERC721 } from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

interface GemLike {
    function transferFrom(address from, address to, uint256 amount) external;
    function transfer(address to, uint256 amount) external;
}

interface IdentityNetworkLike {
    function isMember(address account) external view returns (bool);
}

/// @title NFATFacility
/// @notice Non-Fungible Allocation Token Facility for bespoke capital deployment deals
/// @dev Implements queue-based deposits and ERC-721 NFAT minting
contract NFATFacility is ERC721 {

    // --- Immutables ---

    GemLike public immutable gem;        // Underlying asset
    address public immutable almProxy;   // Custody destination for claimed funds

    // --- Access Control Storage ---

    mapping(address usr => uint256 allowed) public wards;
    mapping(address usr => uint256 allowed) public buds;  // Operator(s) (lpha-nfat beacon)
    mapping(address usr => uint256 allowed) public cops;  // Freezers
    bool    public stopped;
    address public identityNetwork;

    // --- Queue Storage ---

    mapping(address depositor => uint256 amount) public deposits;

    // --- Redeem Storage ---

    mapping(uint256 tokenId => uint256 amount) public funded;

    // --- Events: Access Control ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event AddFreezer(address indexed usr);
    event RemoveFreezer(address indexed usr);
    event Stop();
    event Start();
    event File(bytes32 indexed what, address data);

    // --- Events: Queue ---

    event Subscribe(address indexed depositor, uint256 amount);
    event Withdraw(address indexed depositor, uint256 amount);
    event Issue(address indexed target, uint256 indexed tokenId, uint256 amount);

    // --- Events: Redeem ---

    event Fund(uint256 indexed tokenId, address indexed funder, uint256 amount);
    event Redeem(uint256 indexed tokenId, uint256 amount);

    // --- Modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "NFATFacility/not-authorized");
        _;
    }

    modifier toll() {
        require(buds[msg.sender] == 1 || wards[msg.sender] == 1, "NFATFacility/not-operator");
        _;
    }

    modifier cop() {
        require(cops[msg.sender] == 1 || wards[msg.sender] == 1, "NFATFacility/not-freezer");
        _;
    }

    modifier notStopped() {
        require(!stopped, "NFATFacility/stopped");
        _;
    }

    // --- Constructor ---

    constructor(address gem_, address almProxy_, string memory name_, string memory symbol_)
        ERC721(name_, symbol_)
    {
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

    function kiss(address usr) external auth {
        buds[usr] = 1;
        emit Kiss(usr);
    }

    function diss(address usr) external auth {
        buds[usr] = 0;
        emit Diss(usr);
    }

    function addFreezer(address usr) external auth {
        cops[usr] = 1;
        emit AddFreezer(usr);
    }

    function removeFreezer(address usr) external auth {
        cops[usr] = 0;
        emit RemoveFreezer(usr);
    }

    function stop() external cop {
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

    /// @notice Operator issues NFAT from queue, mints to target
    /// @param target The Prime address to mint the NFAT to
    /// @param amount The amount of gem to issue
    /// @param tokenId The token ID for the new NFAT
    function issue(address target, uint256 amount, uint256 tokenId) external toll notStopped {
        require(amount > 0, "NFATFacility/zero-amount");
        require(deposits[target] >= amount, "NFATFacility/insufficient-deposits");

        // Effects - Queue
        unchecked { deposits[target] -= amount; }

        // Effects - NFAT (identity network check in _update)
        _mint(target, tokenId);

        // Interactions
        gem.transfer(almProxy, amount);

        emit Issue(target, tokenId, amount);
    }

    // --- Redeem Functions ---

    /// @notice Deposit funds for NFAT redemption
    /// @param tokenId The NFAT to fund
    /// @param amount The amount of gem to deposit
    function fund(uint256 tokenId, uint256 amount) external {
        require(_ownerOf(tokenId) != address(0), "NFATFacility/invalid-token");
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

        address owner = _ownerOf(tokenId);
        require(msg.sender == owner, "NFATFacility/not-owner");
        require(identityNetwork == address(0) || IdentityNetworkLike(identityNetwork).isMember(owner), "NFATFacility/not-member");

        // Effects
        unchecked { funded[tokenId] -= amount; }

        // Interactions
        gem.transfer(owner, amount);

        emit Redeem(tokenId, amount);
    }

    // --- ERC-721 Overrides ---

    /// @dev OZ's _mint and transferFrom both revert before calling _update when to == address(0),
    ///      and _burn is never invoked, so `to` is guaranteed to be non-zero here.
    function _update(address to, uint256 tokenId, address auth_) internal override returns (address) {
        require(
            identityNetwork == address(0) || IdentityNetworkLike(identityNetwork).isMember(to),
            "NFATFacility/not-member"
        );
        return super._update(to, tokenId, auth_);
    }
}
