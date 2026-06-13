# Indexer bookkeeping (C.3): how far the event indexer has processed, per
# contract, so the DB cache knows its freshness and can resume.
class ChainSyncState < ApplicationRecord
  validates :contract_address, presence: true, uniqueness: true
  validates :last_synced_block, numericality: { greater_than_or_equal_to: 0 }

  def self.for(contract_address)
    find_or_create_by(contract_address: contract_address.to_s.downcase)
  end
end
