// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {GitRewardEscrow} from "../src/GitRewardEscrow.sol";

/// @notice Deploys GitRewardEscrow. Parameters come from env vars so the same
///         script serves Base Sepolia (test) and Base mainnet (launch).
///
/// Required env:
///   USDC_ADDRESS    - token address on the target chain (see README)
///   TREASURY        - fee recipient
///   ORACLE_SIGNER   - public address of the oracle signing key
///   OWNER           - admin (v1: a single EOA)
///   FEE_BPS         - initial fee in basis points (e.g. 300 = 3%); default 300
///
/// Run (Base Sepolia):
///   forge script script/Deploy.s.sol \
///     --rpc-url $BASE_SEPOLIA_RPC --broadcast --verify \
///     --private-key $DEPLOYER_PK
contract Deploy is Script {
    function run() external returns (GitRewardEscrow escrow) {
        address usdc = vm.envAddress("USDC_ADDRESS");
        address treasury = vm.envAddress("TREASURY");
        address oracleSigner = vm.envAddress("ORACLE_SIGNER");
        address owner = vm.envAddress("OWNER");
        uint16 feeBps = uint16(vm.envOr("FEE_BPS", uint256(300)));

        vm.startBroadcast();
        escrow = new GitRewardEscrow(usdc, treasury, oracleSigner, feeBps, owner);
        vm.stopBroadcast();

        console2.log("GitRewardEscrow deployed at:", address(escrow));
        console2.log("  chainId:      ", block.chainid);
        console2.log("  USDC:         ", usdc);
        console2.log("  treasury:     ", treasury);
        console2.log("  oracleSigner: ", oracleSigner);
        console2.log("  owner:        ", owner);
        console2.log("  feeBps:       ", feeBps);
    }
}
