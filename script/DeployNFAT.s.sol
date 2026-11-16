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

import "forge-std/Script.sol";

import { ScriptTools } from "dss-test/ScriptTools.sol";

import { NFATDeploy } from "deploy/NFATDeploy.sol";

// Deploys an NFATFacility from source and hands sole ward to
// `owner`, dropping the deployer. Mutable configuration (recipient/bud/cop wiring, files) is left
// to the activation spell via {NFATInit}. Config: script/input/{chainId}/nfat-{ENV}.json.
contract DeployNFAT is Script {

    using stdJson     for string;
    using ScriptTools for string;

    function run() external {
        vm.setEnv("FOUNDRY_ROOT_CHAINID",             "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        string memory fileSlug = string(abi.encodePacked("nfat-", vm.envString("ENV")));

        string memory config = ScriptTools.loadConfig(fileSlug);

        address owner  = config.readAddress(".owner");
        bytes32 gem    = ScriptTools.stringToBytes32(config.readString(".gem")); // "USDS" or "SUSDS"
        string memory name   = config.readString(".name");
        string memory symbol = config.readString(".symbol");

        vm.startBroadcast();

        // The broadcaster is the initial ward; NFATDeploy hands it to `owner` and drops the deployer.
        address facility = NFATDeploy.deploy(msg.sender, owner, gem, name, symbol);

        vm.stopBroadcast();

        console.log("NFATFacility deployed at", facility);
        console.log("owner (sole ward):      ", owner);

        ScriptTools.exportContract(fileSlug, "nfatFacility", facility);
    }

}
