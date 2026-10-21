PATH := ~/.solc-select/artifacts/:~/.solc-select/artifacts/solc-0.8.24:$(PATH)
certora-nfat :; PATH=${PATH} certoraRun certora/NFATFacility.conf$(if $(rule), --rule $(rule),)$(if $(results), --wait_for_results all,)

# --------------------------------------------------------------------------------------------------
# Deploy: NFAT Facility                      #
# --------------------------------------------------------------------------------------------------
# Prerequisites:
#   - ETH_FROM: deployer address
#   - ETH_RPC_URL: chain RPC URL
#   - MAINNET_API_KEY: Etherscan key (for --verify)
#   - ENV: config slug; reads script/input/{chainId}/nfat-$(ENV).json (owner, gem, name, symbol)
#     owner = the operating star's SubProxy (sole ward; the onboarding spell executes as it)
#   - foundry keystore account named "deployer" (cast wallet import deployer --interactive)
#
# Deploys the facility, hands sole ward to `owner`, and drops the deployer (via NFATDeploy).
# Output: script/output/{chainId}/nfat-$(ENV)-latest.json
# Usage:  ENV=<env> make deploy-nfat-mainnet

deploy-nfat-mainnet:
	forge script script/DeployNFAT.s.sol:DeployNFAT \
		--sender $(ETH_FROM) --account deployer --broadcast \
		--verify --retries 10 --delay 10 --rpc-url $(ETH_RPC_URL)

deploy-nfat-mainnet-dryrun:
	forge script script/DeployNFAT.s.sol:DeployNFAT \
		--sender $(ETH_FROM) --account deployer --rpc-url $(ETH_RPC_URL)
