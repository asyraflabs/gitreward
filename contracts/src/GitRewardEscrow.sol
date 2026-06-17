// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title GitRewardEscrow
/// @notice Non-custodial bounty escrow for GitHub issues. Funders deposit USDC
///         against an issue; the platform oracle authorizes payout to a
///         contributor wallet by signing an EIP-712 attestation; unmatched
///         bounties refund permissionlessly to the funder after expiry.
/// @dev    The contract trusts the SIGNATURE over (bountyId, recipient), not
///         msg.sender. A leaked relayer key cannot redirect funds. The fee is
///         enforced on-chain (snapshotted at fund, applied at disburse) — the
///         platform only reads it for display. See Appendix A of the build plan;
///         this implementation does not deviate from that frozen spec.
contract GitRewardEscrow is EIP712, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- Constants ---

    /// @notice Hard cap on the fee rate, in basis points (1000 = 10%). The owner
    ///         can never set a fee above this. Advertised as a trust feature.
    uint16 public constant MAX_FEE = 1000;

    /// @notice Minimum bounty size, in USDC base units (5 USDC at 6 decimals).
    uint256 public constant MIN_BOUNTY = 5_000_000;

    /// @notice Minimum lifetime of a bounty from fund time (7 days, per A.1 #6).
    uint64 public constant MIN_DURATION = 7 days;

    /// @notice EIP-712 typehash for the disbursement attestation. MUST match the
    ///         Ruby (eth.rb) signer byte-for-byte: "Disbursement(uint256 bountyId,address recipient)".
    bytes32 public constant DISBURSEMENT_TYPEHASH =
        keccak256("Disbursement(uint256 bountyId,address recipient)");

    // --- Types ---

    // Status lifecycle: None -> Funded -> (Disbursed | Refunded). One-shot.
    enum Status {
        None,
        Funded,
        Disbursed,
        Refunded
    }

    struct Bounty {
        address funder;
        uint256 amount; // USDC, 6 decimals
        uint16 feeSnapshot; // basis points, captured at fund time (e.g. 300 = 3%)
        uint64 expiry; // unix seconds; refundable at/after this
        Status status;
    }

    // --- Storage ---

    /// @notice The USDC token this escrow holds. Immutable, single token for v1.
    IERC20 public immutable USDC;

    /// @notice Address that receives the protocol fee on each disbursement.
    address public treasury;

    /// @notice Address recovered from a valid disbursement signature must equal
    ///         this. Rotation hook for v2; the oracle's public address.
    address public oracleSigner;

    /// @notice Current fee rate in basis points, snapshotted into each bounty at
    ///         fund time. Read by the UI for display.
    uint16 public feeRate;

    /// @notice Monotonic counter; the next bountyId to assign.
    uint256 public nextBountyId = 1;

    mapping(uint256 => Bounty) private _bounties;

    // --- Events ---

    event Funded(
        uint256 indexed bountyId,
        address indexed funder,
        uint256 amount,
        uint16 feeSnapshot,
        uint64 expiry,
        bytes32 issueRef
    );
    event Disbursed(
        uint256 indexed bountyId, address indexed recipient, uint256 paidToRecipient, uint256 paidToTreasury
    );
    event Refunded(uint256 indexed bountyId, address indexed funder, uint256 amount);

    event FeeRateUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event OracleSignerUpdated(address oldSigner, address newSigner);

    // --- Errors ---

    error ZeroAddress();
    error FeeExceedsMax(uint16 newFeeBps, uint16 maxFee);
    error AmountBelowMinimum(uint256 amount, uint256 minimum);
    error ExpiryTooSoon(uint64 expiry, uint64 earliest);
    error BountyNotFunded(uint256 bountyId, Status status);
    error BountyExpired(uint64 expiry, uint256 nowTs);
    error NotExpiredYet(uint64 expiry, uint256 nowTs);
    error NotFunder(address caller, address funder);
    error InvalidRecipient();
    error InvalidOracleSignature(address recovered, address expected);

    /// @param usdc          The USDC token address on the target chain.
    /// @param treasury_     Address that receives protocol fees.
    /// @param oracleSigner_ Address whose signature authorizes disbursements.
    /// @param initialFeeBps Starting fee rate in bps (must be <= MAX_FEE).
    /// @param owner_        Admin (v1: a single EOA; v2: a multisig).
    constructor(address usdc, address treasury_, address oracleSigner_, uint16 initialFeeBps, address owner_)
        EIP712("GitReward", "1")
        Ownable(owner_)
    {
        if (usdc == address(0) || treasury_ == address(0) || oracleSigner_ == address(0)) {
            revert ZeroAddress();
        }
        if (initialFeeBps > MAX_FEE) revert FeeExceedsMax(initialFeeBps, MAX_FEE);
        USDC = IERC20(usdc);
        treasury = treasury_;
        oracleSigner = oracleSigner_;
        feeRate = initialFeeBps;
    }

    // --- Core ---

    /// @notice Fund a bounty for a GitHub issue. Pulls `amount` USDC from the
    ///         caller using an EIP-2612 permit signature (single tx). Reads the
    ///         current feeRate, snapshots it, assigns a sequential bountyId.
    /// @dev    The permit call is wrapped so a front-run permit (already applied
    ///         by an attacker to grief the funder) does not brick this call as
    ///         long as the resulting allowance is sufficient.
    /// @param amount         USDC base units to escrow (>= MIN_BOUNTY).
    /// @param expiry         Unix seconds; refundable at/after this (>= now + MIN_DURATION).
    /// @param issueRef       Off-chain repo+issue reference, stored for audit (event only).
    /// @param permitValue    Allowance authorized by the permit signature.
    /// @param permitDeadline Permit signature deadline.
    /// @param permitV/R/S    Permit signature components.
    /// @return bountyId      The assigned sequential id.
    function fund(
        uint256 amount,
        uint64 expiry,
        bytes32 issueRef,
        uint256 permitValue,
        uint256 permitDeadline,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external nonReentrant returns (uint256 bountyId) {
        if (amount < MIN_BOUNTY) revert AmountBelowMinimum(amount, MIN_BOUNTY);
        uint64 earliest = uint64(block.timestamp) + MIN_DURATION;
        if (expiry < earliest) revert ExpiryTooSoon(expiry, earliest);

        // Apply the permit. Tolerate a front-run that already consumed the nonce:
        // if the permit reverts but allowance is already sufficient, proceed.
        try IERC20Permit(address(USDC)).permit(
            msg.sender, address(this), permitValue, permitDeadline, permitV, permitR, permitS
        ) {} catch {
            // Fall through; the transferFrom below reverts if allowance is short.
        }

        bountyId = nextBountyId++;
        uint16 snapshot = feeRate;

        _bounties[bountyId] = Bounty({
            funder: msg.sender,
            amount: amount,
            feeSnapshot: snapshot,
            expiry: expiry,
            status: Status.Funded
        });

        // Effects done; pull the funds. A failed transfer reverts the whole tx.
        USDC.safeTransferFrom(msg.sender, address(this), amount);

        emit Funded(bountyId, msg.sender, amount, snapshot, expiry, issueRef);
    }

    /// @notice Disburse a funded bounty to a contributor wallet. Submitted by the
    ///         platform relayer, but authorized by the oracle's EIP-712 signature
    ///         over (bountyId, recipient) — msg.sender is irrelevant to safety.
    /// @dev    Only callable strictly before expiry. At/after expiry a bounty can
    ///         only be refunded (refund requires block.timestamp >= expiry), so the
    ///         two paths partition cleanly at the boundary with no overlap. This
    ///         bounds the window in which a compromised oracle key could redirect a
    ///         given bounty to [fund, expiry): past-expiry bounties are
    ///         theft-proof (funder-refundable only). Trade-off: a PR merged in the
    ///         final moments before expiry whose disburse tx mines after expiry
    ///         reverts; the oracle should not sign that close to the deadline.
    /// @param bountyId        The bounty to release.
    /// @param recipient       The contributor wallet, bound into the signature.
    /// @param oracleSignature EIP-712 signature from the oracle signer.
    function disburse(uint256 bountyId, address recipient, bytes calldata oracleSignature) external nonReentrant {
        if (recipient == address(0)) revert InvalidRecipient();

        Bounty storage b = _bounties[bountyId];
        if (b.status != Status.Funded) revert BountyNotFunded(bountyId, b.status);
        if (block.timestamp >= b.expiry) revert BountyExpired(b.expiry, block.timestamp);

        // Verify the attestation. ECDSA.recover rejects malleable (high-s) and
        // zero signatures, so a forged/replayed signature cannot recover the
        // oracle address.
        bytes32 structHash = keccak256(abi.encode(DISBURSEMENT_TYPEHASH, bountyId, recipient));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = ECDSA.recover(digest, oracleSignature);
        if (recovered != oracleSigner) revert InvalidOracleSignature(recovered, oracleSigner);

        // Effects before interactions.
        b.status = Status.Disbursed;

        uint256 amount = b.amount;
        uint256 fee = (amount * b.feeSnapshot) / 10_000; // rounds down
        uint256 payout = amount - fee; // recipient gets the remainder (no dust stranded)

        // Interactions.
        if (fee > 0) USDC.safeTransfer(treasury, fee);
        USDC.safeTransfer(recipient, payout);

        emit Disbursed(bountyId, recipient, payout, fee);
    }

    /// @notice Refund a bounty to its funder at/after expiry. Permissionless to
    ///         the funder, no oracle involvement, no fee. The liveness backstop.
    /// @param bountyId The bounty to refund.
    function refund(uint256 bountyId) external nonReentrant {
        Bounty storage b = _bounties[bountyId];
        if (b.status != Status.Funded) revert BountyNotFunded(bountyId, b.status);
        if (msg.sender != b.funder) revert NotFunder(msg.sender, b.funder);
        if (block.timestamp < b.expiry) revert NotExpiredYet(b.expiry, block.timestamp);

        b.status = Status.Refunded;
        uint256 amount = b.amount;

        USDC.safeTransfer(b.funder, amount);

        emit Refunded(bountyId, b.funder, amount);
    }

    // --- Admin (owner; v1 a single EOA, later a multisig) ---

    /// @notice Set the fee rate (bps). Reverts above MAX_FEE. Does not affect
    ///         already-funded bounties (they use their snapshot).
    function setFeeRate(uint16 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE) revert FeeExceedsMax(newFeeBps, MAX_FEE);
        emit FeeRateUpdated(feeRate, newFeeBps);
        feeRate = newFeeBps;
    }

    /// @notice Update the treasury address that receives fees.
    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    /// @notice Rotate the oracle signer (v2 hardening hook). Future signatures
    ///         must come from the new key; in-flight attestations under the old
    ///         key become invalid immediately.
    function setOracleKey(address newOracleSigner) external onlyOwner {
        if (newOracleSigner == address(0)) revert ZeroAddress();
        emit OracleSignerUpdated(oracleSigner, newOracleSigner);
        oracleSigner = newOracleSigner;
    }

    // --- Views ---

    function getBounty(uint256 bountyId) external view returns (Bounty memory) {
        return _bounties[bountyId];
    }

    /// @notice The EIP-712 domain separator, exposed for off-chain signers/tests.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
