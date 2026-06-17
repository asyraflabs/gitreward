// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {GitRewardEscrow} from "../src/GitRewardEscrow.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

/// @notice Drives random fund/disburse/refund sequences (signing real permits and
/// oracle attestations) and checks the core conservation invariant: the escrow's
/// USDC balance always equals the sum of amounts still in `Funded` status — i.e.
/// no funds are created, destroyed, double-paid, or stranded across any sequence.
contract Handler is Test {
    GitRewardEscrow internal escrow;
    MockUSDC internal usdc;
    uint256 internal oraclePk;
    uint256 internal funderPk = 0xF00D;
    address internal funder;

    uint256[] internal ids;

    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 constant DISBURSEMENT_TYPEHASH =
        keccak256("Disbursement(uint256 bountyId,address recipient)");

    constructor(GitRewardEscrow _escrow, MockUSDC _usdc, uint256 _oraclePk) {
        escrow = _escrow;
        usdc = _usdc;
        oraclePk = _oraclePk;
        funder = vm.addr(funderPk);
    }

    function fund(uint256 amountSeed, uint256 durSeed) external {
        uint256 amount = bound(amountSeed, escrow.MIN_BOUNTY(), 1_000_000e6);
        usdc.mint(funder, amount); // always have enough
        uint64 expiry = uint64(block.timestamp + bound(durSeed, 7 days, 90 days));
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _permitSig(amount, deadline);
        vm.prank(funder);
        try escrow.fund(amount, expiry, bytes32(0), amount, deadline, v, r, s) returns (uint256 id) {
            ids.push(id);
        } catch {}
    }

    function disburse(uint256 idSeed, uint8 recipSeed) external {
        if (ids.length == 0) return;
        uint256 id = ids[bound(idSeed, 0, ids.length - 1)];
        // Recipient kept in a safe range that can't collide with the escrow,
        // treasury, or token addresses (which would distort the balance check).
        address recipient = address(uint160(0x100000 + recipSeed));
        bytes memory sig = _oracleSig(id, recipient);
        try escrow.disburse(id, recipient, sig) {} catch {}
    }

    function refund(uint256 idSeed) external {
        if (ids.length == 0) return;
        uint256 id = ids[bound(idSeed, 0, ids.length - 1)];
        GitRewardEscrow.Bounty memory b = escrow.getBounty(id);
        if (b.status != GitRewardEscrow.Status.Funded) return;
        if (block.timestamp < b.expiry) vm.warp(b.expiry); // only ever move time forward
        vm.prank(funder);
        try escrow.refund(id) {} catch {}
    }

    /// Sum of amounts of all bounties still in Funded status.
    function fundedTotal() external view returns (uint256 total) {
        for (uint256 i; i < ids.length; i++) {
            GitRewardEscrow.Bounty memory b = escrow.getBounty(ids[i]);
            if (b.status == GitRewardEscrow.Status.Funded) total += b.amount;
        }
    }

    function _permitSig(uint256 value, uint256 deadline) internal view returns (uint8, bytes32, bytes32) {
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, funder, address(escrow), value, usdc.nonces(funder), deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", usdc.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(funderPk, digest);
    }

    function _oracleSig(uint256 id, address recipient) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(DISBURSEMENT_TYPEHASH, id, recipient));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", escrow.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePk, digest);
        return abi.encodePacked(r, s, v);
    }
}

contract GitRewardEscrowInvariantTest is StdInvariant, Test {
    GitRewardEscrow internal escrow;
    MockUSDC internal usdc;
    Handler internal handler;

    function setUp() public {
        uint256 oraclePk = 0xA11CE;
        usdc = new MockUSDC();
        escrow = new GitRewardEscrow(address(usdc), address(0x7EA5), vm.addr(oraclePk), 300, address(0x0E11));
        handler = new Handler(escrow, usdc, oraclePk);

        // Only fuzz the three action selectors (not the view helpers).
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = Handler.fund.selector;
        selectors[1] = Handler.disburse.selector;
        selectors[2] = Handler.refund.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// Escrow USDC balance == sum of Funded amounts, after any sequence of actions.
    /// Catches over/under-payment, double-spend, stranded dust, and accounting drift.
    function invariant_balanceEqualsFundedTotal() public view {
        assertEq(usdc.balanceOf(address(escrow)), handler.fundedTotal());
    }
}
