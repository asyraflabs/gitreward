# The central table (C.3): a cached copy of on-chain state PLUS the off-chain
# GitHub references the chain doesn't know. On-chain is the source of truth for
# money state (C.1); the mirror fields here are rebuildable by replaying events.
class Bounty < ApplicationRecord
  USDC_DECIMALS = 6
  USDC_UNIT = 10**USDC_DECIMALS

  belongs_to :funder_user, class_name: "User"
  belongs_to :repository
  has_one :attestation, dependent: :destroy
  has_many :pull_request_events, dependent: :nullify

  # pending = local, fund tx not yet confirmed; the rest mirror chain Status (A.6).
  enum :status, {
    pending: "pending",
    funded: "funded",
    disbursed: "disbursed",
    refunded: "refunded"
  }, default: :pending

  validates :github_issue_number, presence: true
  validates :target_branch, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 5 * USDC_UNIT }, allow_nil: true

  scope :active, -> { where(status: %w[pending funded]) }
  scope :open_directory, -> { funded.order(created_at: :desc) }

  # --- money helpers: integer base units everywhere, never floats (C.5) ---

  def amount_usdc
    return nil if amount.nil?

    amount.to_d / USDC_UNIT
  end

  def self.usdc_to_base_units(dollars)
    (BigDecimal(dollars.to_s) * USDC_UNIT).to_i
  end

  # Fee/payout split mirrored from the contract's snapshot, for display only
  # (the chain computes the authoritative split at disburse).
  def fee_base_units
    return nil if amount.nil? || fee_bps_snapshot.nil?

    amount * fee_bps_snapshot / 10_000 # integer floor, matches Solidity (B.2)
  end

  def payout_base_units
    return nil if amount.nil? || fee_base_units.nil?

    amount - fee_base_units
  end

  def issue_url
    "https://github.com/#{repository.full_name}/issues/#{github_issue_number}"
  end

  # Canonical bytes32 issueRef passed on-chain (audit correlation, A.4 / C.3).
  def self.issue_ref_for(full_name, issue_number)
    "0x#{Eth::Util.keccak256("#{full_name}##{issue_number}").unpack1('H*')}"
  end
end
