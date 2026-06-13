// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {GitRewardEscrow} from "../src/GitRewardEscrow.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GitRewardEscrowTest is Test {
    GitRewardEscrow internal escrow;
    MockUSDC internal usdc;

    // Actors
    uint256 internal oraclePk = 0xA11CE;
    address internal oracle;
    uint256 internal funderPk = 0xF00D;
    address internal funder;
    address internal treasury = address(0x7EA5);
    address internal owner = address(0x0E11);
    address internal recipient = address(0xBEEF);
    address internal relayer = address(0x5E1A); // any sender — must not affect safety

    uint16 internal constant INITIAL_FEE_BPS = 300; // 3%
    bytes32 internal constant ISSUE_REF = keccak256("acme/repo#42");

    // EIP-712 typehashes (mirror the contracts under test)
    bytes32 internal constant DISBURSEMENT_TYPEHASH =
        keccak256("Disbursement(uint256 bountyId,address recipient)");
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        oracle = vm.addr(oraclePk);
        funder = vm.addr(funderPk);

        usdc = new MockUSDC();
        escrow = new GitRewardEscrow(address(usdc), treasury, oracle, INITIAL_FEE_BPS, owner);

        usdc.mint(funder, 1_000_000_000_000); // 1,000,000 USDC
    }

    // ----------------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------------

    /// @dev Build an EIP-2612 permit signature against the MockUSDC domain.
    function _permitSig(uint256 ownerPk, address ownerAddr, address spender, uint256 value, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        uint256 nonce = usdc.nonces(ownerAddr);
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, ownerAddr, spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", usdc.DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(ownerPk, digest);
    }

    /// @dev Build the GitReward disbursement digest exactly as the contract does.
    function _disburseDigest(uint256 bountyId, address recip) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(DISBURSEMENT_TYPEHASH, bountyId, recip));
        return keccak256(abi.encodePacked("\x19\x01", escrow.domainSeparator(), structHash));
    }

    /// @dev Produce an oracle signature over (bountyId, recipient).
    function _oracleSig(uint256 signerPk, uint256 bountyId, address recip) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, _disburseDigest(bountyId, recip));
        return abi.encodePacked(r, s, v);
    }

    /// @dev Fund a bounty as `funder` for `amount`, expiring at now + `duration`.
    function _fund(uint256 amount, uint64 duration) internal returns (uint256 bountyId) {
        uint64 expiry = uint64(block.timestamp) + duration;
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _permitSig(funderPk, funder, address(escrow), amount, deadline);
        vm.prank(funder);
        bountyId = escrow.fund(amount, expiry, ISSUE_REF, amount, deadline, v, r, s);
    }

    // ----------------------------------------------------------------------
    // Constructor / config
    // ----------------------------------------------------------------------

    function test_constructor_setsState() public view {
        assertEq(address(escrow.USDC()), address(usdc));
        assertEq(escrow.treasury(), treasury);
        assertEq(escrow.oracleSigner(), oracle);
        assertEq(escrow.feeRate(), INITIAL_FEE_BPS);
        assertEq(escrow.owner(), owner);
        assertEq(escrow.MAX_FEE(), 1000);
        assertEq(escrow.MIN_BOUNTY(), 5_000_000);
        assertEq(escrow.nextBountyId(), 1);
    }

    function test_constructor_revertsOnZeroAddress() public {
        vm.expectRevert(GitRewardEscrow.ZeroAddress.selector);
        new GitRewardEscrow(address(0), treasury, oracle, INITIAL_FEE_BPS, owner);
        vm.expectRevert(GitRewardEscrow.ZeroAddress.selector);
        new GitRewardEscrow(address(usdc), address(0), oracle, INITIAL_FEE_BPS, owner);
        vm.expectRevert(GitRewardEscrow.ZeroAddress.selector);
        new GitRewardEscrow(address(usdc), treasury, address(0), INITIAL_FEE_BPS, owner);
    }

    function test_constructor_revertsOnFeeAboveMax() public {
        vm.expectRevert(abi.encodeWithSelector(GitRewardEscrow.FeeExceedsMax.selector, uint16(1001), uint16(1000)));
        new GitRewardEscrow(address(usdc), treasury, oracle, 1001, owner);
    }

    // ----------------------------------------------------------------------
    // fund — happy + guards
    // ----------------------------------------------------------------------

    function test_fund_happyPath() public {
        uint256 amount = 100_000_000; // 100 USDC
        uint64 expiry = uint64(block.timestamp) + 30 days;

        vm.expectEmit(true, true, false, true, address(escrow));
        emit GitRewardEscrow.Funded(1, funder, amount, INITIAL_FEE_BPS, expiry, ISSUE_REF);

        uint256 bountyId = _fund(amount, 30 days);
        assertEq(bountyId, 1);
        assertEq(escrow.nextBountyId(), 2);
        assertEq(usdc.balanceOf(address(escrow)), amount);

        GitRewardEscrow.Bounty memory b = escrow.getBounty(1);
        assertEq(b.funder, funder);
        assertEq(b.amount, amount);
        assertEq(b.feeSnapshot, INITIAL_FEE_BPS);
        assertEq(b.expiry, expiry);
        assertEq(uint8(b.status), uint8(GitRewardEscrow.Status.Funded));
    }

    function test_fund_assignsSequentialIds() public {
        assertEq(_fund(MIN_5_USDC(), 7 days), 1);
        assertEq(_fund(MIN_5_USDC(), 7 days), 2);
        assertEq(_fund(MIN_5_USDC(), 7 days), 3);
    }

    function test_fund_snapshotsFeeNotLiveRate() public {
        uint256 id1 = _fund(100_000_000, 30 days);
        vm.prank(owner);
        escrow.setFeeRate(1000); // bump to 10%
        uint256 id2 = _fund(100_000_000, 30 days);

        assertEq(escrow.getBounty(id1).feeSnapshot, INITIAL_FEE_BPS); // unchanged
        assertEq(escrow.getBounty(id2).feeSnapshot, 1000);
    }

    function test_fund_revertsBelowMinimum() public {
        uint256 amount = 4_999_999;
        uint64 expiry = uint64(block.timestamp) + 30 days;
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _permitSig(funderPk, funder, address(escrow), amount, deadline);
        vm.prank(funder);
        vm.expectRevert(abi.encodeWithSelector(GitRewardEscrow.AmountBelowMinimum.selector, amount, 5_000_000));
        escrow.fund(amount, expiry, ISSUE_REF, amount, deadline, v, r, s);
    }

    function test_fund_revertsExpiryTooSoon() public {
        uint256 amount = 100_000_000;
        uint64 expiry = uint64(block.timestamp) + 7 days - 1; // just under min duration
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _permitSig(funderPk, funder, address(escrow), amount, deadline);
        uint64 earliest = uint64(block.timestamp) + 7 days;
        vm.prank(funder);
        vm.expectRevert(abi.encodeWithSelector(GitRewardEscrow.ExpiryTooSoon.selector, expiry, earliest));
        escrow.fund(amount, expiry, ISSUE_REF, amount, deadline, v, r, s);
    }

    function test_fund_toleratesFrontRunPermit() public {
        // Attacker front-runs the funder's permit (submits it directly). The
        // funder's fund() must still succeed because allowance is already set.
        uint256 amount = 100_000_000;
        uint64 expiry = uint64(block.timestamp) + 30 days;
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _permitSig(funderPk, funder, address(escrow), amount, deadline);

        // Front-run: someone else applies the permit.
        vm.prank(relayer);
        usdc.permit(funder, address(escrow), amount, deadline, v, r, s);
        assertEq(usdc.allowance(funder, address(escrow)), amount);

        // fund() with the now-stale permit sig still works (try/catch + allowance).
        vm.prank(funder);
        uint256 bountyId = escrow.fund(amount, expiry, ISSUE_REF, amount, deadline, v, r, s);
        assertEq(bountyId, 1);
        assertEq(usdc.balanceOf(address(escrow)), amount);
    }

    // ----------------------------------------------------------------------
    // disburse — happy + fee math
    // ----------------------------------------------------------------------

    function test_disburse_happyPath() public {
        uint256 amount = 100_000_000; // 100 USDC
        uint256 bountyId = _fund(amount, 30 days);

        uint256 expectedFee = (amount * INITIAL_FEE_BPS) / 10_000; // 3 USDC
        uint256 expectedPayout = amount - expectedFee; // 97 USDC

        bytes memory sig = _oracleSig(oraclePk, bountyId, recipient);

        vm.expectEmit(true, true, false, true, address(escrow));
        emit GitRewardEscrow.Disbursed(bountyId, recipient, expectedPayout, expectedFee);

        vm.prank(relayer); // any sender; safety comes from the signature
        escrow.disburse(bountyId, recipient, sig);

        assertEq(usdc.balanceOf(recipient), expectedPayout);
        assertEq(usdc.balanceOf(treasury), expectedFee);
        assertEq(usdc.balanceOf(address(escrow)), 0);
        assertEq(uint8(escrow.getBounty(bountyId).status), uint8(GitRewardEscrow.Status.Disbursed));
    }

    function test_disburse_zeroFeeWhenRateZero() public {
        vm.prank(owner);
        escrow.setFeeRate(0);
        uint256 amount = 100_000_000;
        uint256 bountyId = _fund(amount, 30 days);

        bytes memory sig = _oracleSig(oraclePk, bountyId, recipient);
        vm.prank(relayer);
        escrow.disburse(bountyId, recipient, sig);

        assertEq(usdc.balanceOf(recipient), amount);
        assertEq(usdc.balanceOf(treasury), 0);
    }

    // ----------------------------------------------------------------------
    // disburse — adversarial
    // ----------------------------------------------------------------------

    function test_disburse_revertsOnForgedSignature() public {
        uint256 bountyId = _fund(100_000_000, 30 days);
        uint256 attackerPk = 0xBADBAD;
        bytes memory sig = _oracleSig(attackerPk, bountyId, recipient);

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(GitRewardEscrow.InvalidOracleSignature.selector, vm.addr(attackerPk), oracle)
        );
        escrow.disburse(bountyId, recipient, sig);
    }

    function test_disburse_revertsWhenRecipientNotBound() public {
        // Oracle signed for `recipient`, attacker submits with a different payee.
        uint256 bountyId = _fund(100_000_000, 30 days);
        bytes memory sig = _oracleSig(oraclePk, bountyId, recipient);
        address attacker = address(0xDEAD);

        vm.prank(relayer);
        // Recovered signer won't match because the digest binds the recipient.
        vm.expectRevert();
        escrow.disburse(bountyId, attacker, sig);
    }

    function test_disburse_revertsOnWrongBountyId() public {
        uint256 id1 = _fund(100_000_000, 30 days);
        uint256 id2 = _fund(100_000_000, 30 days);
        // Signature for id1 cannot disburse id2.
        bytes memory sig = _oracleSig(oraclePk, id1, recipient);
        vm.prank(relayer);
        vm.expectRevert();
        escrow.disburse(id2, recipient, sig);
    }

    function test_disburse_revertsOnReplay() public {
        uint256 bountyId = _fund(100_000_000, 30 days);
        bytes memory sig = _oracleSig(oraclePk, bountyId, recipient);

        vm.prank(relayer);
        escrow.disburse(bountyId, recipient, sig);

        // Replaying the exact same valid signature must fail (one-shot status).
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                GitRewardEscrow.BountyNotFunded.selector, bountyId, GitRewardEscrow.Status.Disbursed
            )
        );
        escrow.disburse(bountyId, recipient, sig);
    }

    function test_disburse_revertsAfterRefund() public {
        uint256 bountyId = _fund(100_000_000, 7 days);
        vm.warp(block.timestamp + 7 days);
        vm.prank(funder);
        escrow.refund(bountyId);

        bytes memory sig = _oracleSig(oraclePk, bountyId, recipient);
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                GitRewardEscrow.BountyNotFunded.selector, bountyId, GitRewardEscrow.Status.Refunded
            )
        );
        escrow.disburse(bountyId, recipient, sig);
    }

    function test_disburse_revertsOnZeroRecipient() public {
        uint256 bountyId = _fund(100_000_000, 30 days);
        bytes memory sig = _oracleSig(oraclePk, bountyId, address(0));
        vm.prank(relayer);
        vm.expectRevert(GitRewardEscrow.InvalidRecipient.selector);
        escrow.disburse(bountyId, address(0), sig);
    }

    function test_disburse_revertsOnUnknownBounty() public {
        bytes memory sig = _oracleSig(oraclePk, 999, recipient);
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(GitRewardEscrow.BountyNotFunded.selector, uint256(999), GitRewardEscrow.Status.None)
        );
        escrow.disburse(999, recipient, sig);
    }

    function test_disburse_revertsOnMalleableSignature() public {
        uint256 bountyId = _fund(100_000_000, 30 days);
        bytes32 digest = _disburseDigest(bountyId, recipient);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePk, digest);

        // Flip s to its complement and v, producing the malleable counterpart.
        uint256 N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes32 sMalleable = bytes32(N - uint256(s));
        uint8 vFlipped = v == 27 ? 28 : 27;
        bytes memory malleable = abi.encodePacked(r, sMalleable, vFlipped);

        vm.prank(relayer);
        vm.expectRevert(); // OZ ECDSA rejects high-s
        escrow.disburse(bountyId, recipient, malleable);
    }

    function test_disburse_afterOracleRotationOldSigInvalid() public {
        uint256 bountyId = _fund(100_000_000, 30 days);
        bytes memory oldSig = _oracleSig(oraclePk, bountyId, recipient);

        uint256 newPk = 0xC0FFEE;
        vm.prank(owner);
        escrow.setOracleKey(vm.addr(newPk));

        // Old signature no longer valid.
        vm.prank(relayer);
        vm.expectRevert();
        escrow.disburse(bountyId, recipient, oldSig);

        // New key works.
        bytes memory newSig = _oracleSig(newPk, bountyId, recipient);
        vm.prank(relayer);
        escrow.disburse(bountyId, recipient, newSig);
        assertEq(uint8(escrow.getBounty(bountyId).status), uint8(GitRewardEscrow.Status.Disbursed));
    }

    // ----------------------------------------------------------------------
    // refund
    // ----------------------------------------------------------------------

    function test_refund_happyPath() public {
        uint256 amount = 100_000_000;
        uint256 bountyId = _fund(amount, 7 days);
        uint256 before = usdc.balanceOf(funder);

        vm.warp(block.timestamp + 7 days);

        vm.expectEmit(true, true, false, true, address(escrow));
        emit GitRewardEscrow.Refunded(bountyId, funder, amount);

        vm.prank(funder);
        escrow.refund(bountyId);

        assertEq(usdc.balanceOf(funder), before + amount);
        assertEq(usdc.balanceOf(address(escrow)), 0);
        assertEq(uint8(escrow.getBounty(bountyId).status), uint8(GitRewardEscrow.Status.Refunded));
    }

    function test_refund_revertsBeforeExpiry() public {
        uint256 bountyId = _fund(100_000_000, 30 days);
        uint64 expiry = escrow.getBounty(bountyId).expiry;
        vm.prank(funder);
        vm.expectRevert(abi.encodeWithSelector(GitRewardEscrow.NotExpiredYet.selector, expiry, block.timestamp));
        escrow.refund(bountyId);
    }

    function test_refund_revertsForNonFunder() public {
        uint256 bountyId = _fund(100_000_000, 7 days);
        vm.warp(block.timestamp + 7 days);
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(GitRewardEscrow.NotFunder.selector, relayer, funder));
        escrow.refund(bountyId);
    }

    function test_refund_revertsAfterDisburse() public {
        uint256 bountyId = _fund(100_000_000, 7 days);
        bytes memory sig = _oracleSig(oraclePk, bountyId, recipient);
        vm.prank(relayer);
        escrow.disburse(bountyId, recipient, sig);

        vm.warp(block.timestamp + 7 days);
        vm.prank(funder);
        vm.expectRevert(
            abi.encodeWithSelector(
                GitRewardEscrow.BountyNotFunded.selector, bountyId, GitRewardEscrow.Status.Disbursed
            )
        );
        escrow.refund(bountyId);
    }

    function test_refund_revertsOnDoubleRefund() public {
        uint256 bountyId = _fund(100_000_000, 7 days);
        vm.warp(block.timestamp + 7 days);
        vm.prank(funder);
        escrow.refund(bountyId);
        vm.prank(funder);
        vm.expectRevert(
            abi.encodeWithSelector(
                GitRewardEscrow.BountyNotFunded.selector, bountyId, GitRewardEscrow.Status.Refunded
            )
        );
        escrow.refund(bountyId);
    }

    function test_refund_exactlyAtExpiry() public {
        uint256 bountyId = _fund(100_000_000, 7 days);
        uint64 expiry = escrow.getBounty(bountyId).expiry;
        vm.warp(expiry); // block.timestamp == expiry is allowed
        vm.prank(funder);
        escrow.refund(bountyId);
        assertEq(uint8(escrow.getBounty(bountyId).status), uint8(GitRewardEscrow.Status.Refunded));
    }

    // ----------------------------------------------------------------------
    // Admin authorization
    // ----------------------------------------------------------------------

    function test_setFeeRate_onlyOwner() public {
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, relayer));
        escrow.setFeeRate(500);

        vm.prank(owner);
        escrow.setFeeRate(500);
        assertEq(escrow.feeRate(), 500);
    }

    function test_setFeeRate_revertsAboveMax() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(GitRewardEscrow.FeeExceedsMax.selector, uint16(1001), uint16(1000)));
        escrow.setFeeRate(1001);
    }

    function test_setFeeRate_atMaxAllowed() public {
        vm.prank(owner);
        escrow.setFeeRate(1000);
        assertEq(escrow.feeRate(), 1000);
    }

    function test_setTreasury_onlyOwnerAndNonZero() public {
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, relayer));
        escrow.setTreasury(address(0x1234));

        vm.prank(owner);
        vm.expectRevert(GitRewardEscrow.ZeroAddress.selector);
        escrow.setTreasury(address(0));

        vm.prank(owner);
        escrow.setTreasury(address(0x1234));
        assertEq(escrow.treasury(), address(0x1234));
    }

    function test_setOracleKey_onlyOwnerAndNonZero() public {
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, relayer));
        escrow.setOracleKey(address(0x1234));

        vm.prank(owner);
        vm.expectRevert(GitRewardEscrow.ZeroAddress.selector);
        escrow.setOracleKey(address(0));

        vm.prank(owner);
        escrow.setOracleKey(address(0x1234));
        assertEq(escrow.oracleSigner(), address(0x1234));
    }

    // ----------------------------------------------------------------------
    // Fuzz
    // ----------------------------------------------------------------------

    function testFuzz_feeMath_neverOverpaysOrStrands(uint256 amount, uint16 feeBps) public {
        amount = bound(amount, escrow.MIN_BOUNTY(), 1_000_000_000_000);
        feeBps = uint16(bound(feeBps, 0, escrow.MAX_FEE()));

        vm.prank(owner);
        escrow.setFeeRate(feeBps);

        uint256 bountyId = _fund(amount, 30 days);
        bytes memory sig = _oracleSig(oraclePk, bountyId, recipient);
        vm.prank(relayer);
        escrow.disburse(bountyId, recipient, sig);

        uint256 paidRecipient = usdc.balanceOf(recipient);
        uint256 paidTreasury = usdc.balanceOf(treasury);

        // Conservation: every base unit accounted for, nothing stranded, no overpay.
        assertEq(paidRecipient + paidTreasury, amount);
        assertEq(usdc.balanceOf(address(escrow)), 0);
        // Fee never exceeds the snapshot rate.
        assertLe(paidTreasury, (amount * feeBps) / 10_000);
        assertEq(paidTreasury, (amount * feeBps) / 10_000); // exact floor
    }

    function testFuzz_disburse_onlyExactOracleSigVerifies(uint256 wrongPk) public {
        wrongPk = bound(wrongPk, 1, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140);
        vm.assume(vm.addr(wrongPk) != oracle);

        uint256 bountyId = _fund(100_000_000, 30 days);
        bytes memory sig = _oracleSig(wrongPk, bountyId, recipient);
        vm.prank(relayer);
        vm.expectRevert();
        escrow.disburse(bountyId, recipient, sig);
    }

    function testFuzz_refund_returnsFullAmount(uint256 amount) public {
        amount = bound(amount, escrow.MIN_BOUNTY(), 1_000_000_000_000);
        uint256 bountyId = _fund(amount, 7 days);
        uint256 before = usdc.balanceOf(funder);
        vm.warp(block.timestamp + 7 days);
        vm.prank(funder);
        escrow.refund(bountyId);
        assertEq(usdc.balanceOf(funder), before + amount); // no fee on refund
    }

    // ----------------------------------------------------------------------
    // Internal
    // ----------------------------------------------------------------------

    function MIN_5_USDC() internal pure returns (uint256) {
        return 5_000_000;
    }
}
