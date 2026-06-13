// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {GitRewardEscrow} from "../src/GitRewardEscrow.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

/// @notice The Phase 1 byte-for-byte agreement gate (build plan A.7): the Ruby
///         (eth.rb) signer and the Solidity verifier MUST derive the identical
///         EIP-712 disbursement digest, so a signature made by one is accepted
///         by the other.
///
/// Two proofs:
///   1. test_rubyFixture_*  — STATIC. Reads a committed eth.rb-produced fixture
///      and recovers the expected signer. No Ruby needed at test time; this is
///      the always-on CI gate.
///   2. test_liveContract_* — LIVE FFI. Deploys the real escrow, passes its
///      actual domain to eth.rb, and disburses with the returned signature —
///      proving the deployed contract accepts an eth.rb signature end-to-end.
///      Opt-in: run with `RUN_LIVE_EIP712=true forge test --ffi`.
contract EIP712RoundTripTest is Test {
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant DISBURSEMENT_TYPEHASH =
        keccak256("Disbursement(uint256 bountyId,address recipient)");

    string internal fixtureJson;

    function setUp() public {
        fixtureJson = vm.readFile(string.concat(vm.projectRoot(), "/test/fixtures/disbursement_fixture.json"));
    }

    // --- Proof 1: static committed fixture ---

    function test_rubyFixture_recoversExpectedOracle() public view {
        // Pull every value from the eth.rb-produced fixture.
        uint256 chainId = vm.parseJsonUint(fixtureJson, ".domain.chainId");
        address verifyingContract = vm.parseJsonAddress(fixtureJson, ".domain.verifyingContract");
        uint256 bountyId = vm.parseJsonUint(fixtureJson, ".message.bountyId");
        address recipient = vm.parseJsonAddress(fixtureJson, ".message.recipient");
        address expectedSigner = vm.parseJsonAddress(fixtureJson, ".expectedSigner");
        bytes32 fixtureDigest = vm.parseJsonBytes32(fixtureJson, ".digest");
        bytes memory signature = vm.parseJsonBytes(fixtureJson, ".signature");

        // Reconstruct the digest independently in Solidity using the SAME domain
        // (name "GitReward", version "1") the contract uses.
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("GitReward")),
                keccak256(bytes("1")),
                chainId,
                verifyingContract
            )
        );
        bytes32 structHash = keccak256(abi.encode(DISBURSEMENT_TYPEHASH, bountyId, recipient));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // The Solidity-computed digest must equal eth.rb's digest, byte for byte.
        assertEq(digest, fixtureDigest, "digest mismatch: eth.rb and Solidity disagree on EIP-712 encoding");

        // And the signature over that digest must recover the expected oracle.
        address recovered = ecrecoverFromSig(digest, signature);
        assertEq(recovered, expectedSigner, "recovered signer != expected oracle");
    }

    function test_typehashMatchesContract() public {
        // Prove the contract's on-chain typehash constant equals the one this
        // test (and thus the fixture) assumes.
        MockUSDC usdc = new MockUSDC();
        GitRewardEscrow escrow =
            new GitRewardEscrow(address(usdc), address(0x7EA5), address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266), 300, address(this));
        assertEq(escrow.DISBURSEMENT_TYPEHASH(), DISBURSEMENT_TYPEHASH);
    }

    // --- Proof 2: live FFI round-trip against the real deployed contract ---

    function test_liveContract_verifiesRubySignature() public {
        if (!vm.envOr("RUN_LIVE_EIP712", false)) {
            emit log("skipped (set RUN_LIVE_EIP712=true and pass --ffi to run the live eth.rb round-trip)");
            return;
        }

        // anvil account #0 — the same key oracle/sign_cli.rb uses.
        address oracle = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        address funder = address(0xF00D);
        address recipient = address(0xBEEF);
        address treasury = address(0x7EA5);

        MockUSDC usdc = new MockUSDC();
        GitRewardEscrow escrow = new GitRewardEscrow(address(usdc), treasury, oracle, 300, address(this));

        uint256 amount = 100_000_000;
        usdc.mint(funder, amount);
        vm.prank(funder);
        usdc.approve(address(escrow), amount);
        vm.prank(funder);
        // Permit already covered elsewhere; here approve + a permit sig that may
        // no-op is fine since allowance is set. Use a dummy permit (deadline in
        // the future, zero sig) — fund tolerates a failing permit via try/catch.
        uint256 bountyId = escrow.fund(amount, uint64(block.timestamp + 30 days), keccak256("issue"), 0, block.timestamp + 1, 0, bytes32(0), bytes32(0));

        // Ask eth.rb to sign over THIS contract's actual domain.
        string[] memory cmd = new string[](6);
        cmd[0] = "ruby";
        cmd[1] = string.concat(vm.projectRoot(), "/../oracle/sign_cli.rb");
        cmd[2] = vm.toString(block.chainid);
        cmd[3] = vm.toString(address(escrow));
        cmd[4] = vm.toString(bountyId);
        cmd[5] = vm.toString(recipient);
        bytes memory signature = vm.ffi(cmd);

        escrow.disburse(bountyId, recipient, signature);

        assertEq(uint8(escrow.getBounty(bountyId).status), uint8(GitRewardEscrow.Status.Disbursed));
        assertGt(usdc.balanceOf(recipient), 0);
    }

    // --- helper ---

    function ecrecoverFromSig(bytes32 digest, bytes memory sig) internal pure returns (address) {
        require(sig.length == 65, "bad sig length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 0x20))
            s := mload(add(sig, 0x40))
            v := byte(0, mload(add(sig, 0x60)))
        }
        return ecrecover(digest, v, r, s);
    }
}
