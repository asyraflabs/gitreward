# Appendix C.3 — chain_sync_state (owner: indexer bookkeeping). Tracks how far
# the event indexer has processed so the DB cache knows its freshness and resumes.
class CreateChainSyncStates < ActiveRecord::Migration[8.1]
  def change
    create_table :chain_sync_states do |t|
      t.string :contract_address, null: false
      t.bigint :last_synced_block, null: false, default: 0

      t.timestamps
    end
    add_index :chain_sync_states, :contract_address, unique: true
  end
end
