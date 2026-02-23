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

pragma solidity >=0.8.0;

import { DssInstance } from "dss-test/MCD.sol";

interface NFATFacilityLike {
    function gem() external view returns (address);
    function almProxy() external view returns (address);
    function file(bytes32, address) external;
    function kiss(address) external;
    function addFreezer(address) external;
}

struct NFATConfig {
    bytes32   facilityKey;
    address   almProxy;
    address   identityNetwork;
    address   operator;
    address[] freezers;
}

library NFATInit {

    function init(
        DssInstance memory dss,
        address     facility_,
        NFATConfig  memory cfg
    ) internal {
        NFATFacilityLike facility = NFATFacilityLike(facility_);

        // --- Sanity checks ---

        require(facility.gem()      == dss.chainlog.getAddress("SUSDS"), "NFATInit/gem-mismatch");
        require(facility.almProxy() == cfg.almProxy,                     "NFATInit/almProxy-mismatch");

        // --- Configure identity network ---

        facility.file("identityNetwork", cfg.identityNetwork);

        // --- Configure freezers ---

        for (uint256 i = 0; i < cfg.freezers.length; ++i) {
            facility.addFreezer(cfg.freezers[i]);
        }

        // --- Configure operator ---

        facility.kiss(cfg.operator);

        // --- Chainlog ---

        dss.chainlog.setAddress(cfg.facilityKey, facility_);
    }
}
