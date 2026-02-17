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
}

/// @title NFATRedeemer
/// @notice Handles redemption mechanics for Non-Fungible Allocation Tokens
/// @dev Separated from NFATFacility to allow modular upgrades to redemption logic
contract NFATRedeemer {

    // --- Immutables ---

    INFATFacility public immutable facility;
    IERC20        public immutable sUSDS;

    // --- Redeem Storage ---

    mapping(uint256 tokenId => uint256 amount) public funded;

    // --- Events ---

    event Fund(uint256 indexed tokenId, uint256 amount);
    event Redeem(uint256 indexed tokenId, uint256 amount);

    // --- Constructor ---

    constructor(address facility_) {
        facility = INFATFacility(facility_);
        sUSDS = facility.sUSDS();
    }

    // --- Redeem Functions ---

    /// @notice Deposit funds for NFAT redemption
    /// @param tokenId The NFAT to fund
    /// @param amount The amount of sUSDS to deposit
    function fund(uint256 tokenId, uint256 amount) external {
        facility.ownerOf(tokenId); // reverts if token does not exist
        require(amount > 0, "NFATRedeemer/zero-amount");

        // Effects
        funded[tokenId] += amount;

        // Interactions
        sUSDS.transferFrom(msg.sender, address(this), amount);

        emit Fund(tokenId, amount);
    }

    /// @notice NFAT holder claims specified amount from funded balance
    /// @param tokenId The NFAT to redeem from
    /// @param amount The amount of sUSDS to claim
    function redeem(uint256 tokenId, uint256 amount) external {
        require(amount > 0, "NFATRedeemer/zero-amount");
        require(funded[tokenId] >= amount, "NFATRedeemer/insufficient-funded");

        address owner = facility.ownerOf(tokenId);
        require(msg.sender == owner, "NFATRedeemer/not-owner");

        // Effects
        funded[tokenId] -= amount;

        // Interactions - Transfer funds to owner
        sUSDS.transfer(owner, amount);

        emit Redeem(tokenId, amount);
    }
}
