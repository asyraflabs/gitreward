# A user's linked payout wallet (C.3). Separate table so history/rotation is
# possible and "has a wallet" is an explicit, auditable fact — the linchpin of
# auto-disburse. One active wallet per user (enforced by a partial unique index).
class WalletLink < ApplicationRecord
  belongs_to :user

  validates :address, presence: true, format: { with: /\A0x[0-9a-fA-F]{40}\z/, message: "must be a 0x EVM address" }

  before_validation :checksum_address

  # Make this the user's single active wallet, deactivating any prior one.
  def activate!
    transaction do
      user.wallet_links.where.not(id: id).update_all(active: false)
      update!(active: true)
    end
  end

  private

  # Store EIP-55 checksummed form (C.3 says checksummed address).
  def checksum_address
    return if address.blank?

    normalized = address.strip
    self.address = Eth::Address.new(normalized).checksummed if normalized.match?(/\A0x[0-9a-fA-F]{40}\z/)
  rescue StandardError
    # leave as-is; format validation will flag it
  end
end
