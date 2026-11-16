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

import { NFATFacility } from "./NFATFacility.sol";

interface INFATFacilityFactory {

    function deploy(
        string    memory name,
        string    memory symbol,
        string    memory baseURI,
        address          gem,
        address          recipient,
        address          identityNetwork,
        address[] memory wards,
        address[] memory buds,
        address[] memory cops
    ) external returns (address);


    event FacilityDeployed(
        address   indexed facility,
        string            name,
        string            symbol,
        string            baseURI,
        address   indexed gem,
        address   indexed recipient,
        address           identityNetwork,
        address[]         wards,
        address[]         buds,
        address[]         cops
    );

}

contract NFATFacilityFactory is INFATFacilityFactory {

    function deploy(
        string    memory name,
        string    memory symbol,
        string    memory baseURI,
        address          gem,
        address          recipient,
        address          identityNetwork,
        address[] memory wards,
        address[] memory buds,
        address[] memory cops
    ) external override returns (address) {
        // Step 0: At least one ward is required — the factory denies itself below, so an empty
        //         wards array would leave the facility permanently without an authorized admin.

        require(wards.length > 0, "NFATFacilityFactory/no-wards");

        // Step 1: Deploy the new facility contract.

        NFATFacility facility = new NFATFacility({ gem_: gem, name_: name, symbol_: symbol });

        // Step 2: Grant roles

        for (uint256 i = 0; i < wards.length; i++) {
            require(wards[i] != address(0), "NFATFacilityFactory/ward-zero-address");
            facility.rely(wards[i]);
        }

        for (uint256 i = 0; i < buds.length; i++) {
            require(buds[i] != address(0), "NFATFacilityFactory/bud-zero-address");
            facility.kiss(buds[i]);
        }

        for (uint256 i; i < cops.length; i++) {
            require(cops[i] != address(0), "NFATFacilityFactory/cop-zero-address");
            facility.addFreezer(cops[i]);
        }

        // Step 3: File recipient, identity network, and baseURI on the facility.

        require(recipient != address(0), "NFATFacilityFactory/recipient-zero-address");
        facility.file("recipient", recipient);

        if(bytes(baseURI).length > 0)     facility.file("baseURI",         baseURI);
        if(identityNetwork != address(0)) facility.file("identityNetwork", identityNetwork);

        // Step 4: Revoke ward role for factory

        facility.deny(address(this));

        emit FacilityDeployed(
            address(facility), name, symbol, baseURI, gem, recipient, identityNetwork, wards, buds, cops
        );

        return address(facility);
    }

}
