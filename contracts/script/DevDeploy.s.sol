// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {GitRewardEscrow} from "../src/GitRewardEscrow.sol";
import {MockUSDC} from "../test/mocks/MockUSDC.sol";

/// @notice Local-only (anvil) deploy: MockUSDC + escrow, then funds one bounty so
///         the Rails chain client/indexer have real reads, logs, and a Funded
///         bounty to disburse. NOT for any real network. Uses anvil default keys.
contract DevDeploy is Script {
    // anvil default accounts
    uint256 constant DEPLOYER_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // acct0 = oracle/owner
    address constant ORACLE = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // acct0 addr
    address constant TREASURY = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // acct2
    uint256 constant FUNDER_PK = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6; // acct3
    address constant FUNDER = 0x90F79bf6EB2c4f870365E785982E1f101E93b906; // acct3 addr

    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function run() external {
        // Deploy as acct0 (owner + oracle signer).
        vm.startBroadcast(DEPLOYER_PK);
        MockUSDC usdc = new MockUSDC();
        GitRewardEscrow escrow = new GitRewardEscrow(address(usdc), TREASURY, ORACLE, 300, vm.addr(DEPLOYER_PK));
        usdc.mint(FUNDER, 1_000_000_000); // 1,000 USDC to the funder
        vm.stopBroadcast();

        // Fund one bounty as the funder (50 USDC), using a permit signature.
        uint256 amount = 50_000_000;
        uint64 expiry = uint64(block.timestamp + 30 days);
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _permit(usdc, FUNDER_PK, FUNDER, address(escrow), amount, deadline);

        vm.startBroadcast(FUNDER_PK);
        uint256 bountyId = escrow.fund(amount, expiry, keccak256("acme/widgets#7"), amount, deadline, v, r, s);
        vm.stopBroadcast();

        console2.log("USDC_ADDRESS=%s", address(usdc));
        console2.log("ESCROW_ADDRESS=%s", address(escrow));
        console2.log("FUNDED_BOUNTY_ID=%s", bountyId);
    }

    function _permit(MockUSDC usdc, uint256 pk, address owner, address spender, uint256 value, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, usdc.nonces(owner), deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", usdc.DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(pk, digest);
    }
}
