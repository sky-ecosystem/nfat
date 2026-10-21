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

interface NFATFacilityLike {
    function gem() external view returns (address);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function recipient() external view returns (address);
    function identityNetwork() external view returns (address);
    function baseURI() external view returns (string memory);
    function file(bytes32, address) external;
    function file(bytes32, string calldata) external;
    function kiss(address) external;
    function addFreezer(address) external;
}

struct NFATConfig {
    address   gem;
    string    name;
    string    symbol;
    address   almProxy;
    address   identityNetwork;
    string    baseURI;
    address[] freezers;
}

// Note: `stopped` is initially false
library NFATInit {

    function init(address facility_, NFATConfig memory cfg) internal {
        NFATFacilityLike facility = NFATFacilityLike(facility_);

        require(cfg.almProxy != address(0), "NFATInit/alm-proxy-zero-address");

        // Block re-initialization: init is meant for a fresh facility, and a second run could not
        // cleanly re-wire the facility for a different ALMProxy (the previous recipient would
        // remain a bud), so refuse outright.
        require(facility.recipient()             == address(0), "NFATInit/recipient-already-set");
        require(facility.identityNetwork()       == address(0), "NFATInit/identity-network-already-set");
        require(bytes(facility.baseURI()).length == 0,          "NFATInit/base-uri-already-set");

        // Validate the configured gem explicitly
        require(facility.gem() == cfg.gem, "NFATInit/gem-mismatch");
        require(keccak256(bytes(facility.name()))   == keccak256(bytes(cfg.name)),   "NFATInit/name-mismatch");
        require(keccak256(bytes(facility.symbol())) == keccak256(bytes(cfg.symbol)), "NFATInit/symbol-mismatch");

        // Structural wiring: the shared ALMProxy is both the recipient and the sole bud.
        // No additional operators are kissed: the Halo NFAT facet only tracks issuances made through
        // the ALMProxy, so a third-party issuer would create positions it cannot account for or repay.
        facility.file("recipient", cfg.almProxy);
        facility.kiss(cfg.almProxy);

        // Optional files are skipped when unset.
        if (cfg.identityNetwork != address(0)) facility.file("identityNetwork", cfg.identityNetwork);
        if (bytes(cfg.baseURI).length > 0)     facility.file("baseURI",         cfg.baseURI);

        for (uint256 i = 0; i < cfg.freezers.length; ++i) {
            require(cfg.freezers[i] != address(0), "NFATInit/freezer-zero-address");
            facility.addFreezer(cfg.freezers[i]);
        }

        // Note: no chainlog registration here. NFAT onboarding spells execute as a star SubProxy,
        // which cannot write the Sky chainlog (PauseProxy-only); stars track addresses in their
        // own address registry. If Sky core wants the facility in the chainlog, its own spell
        // registers it.
    }
}
