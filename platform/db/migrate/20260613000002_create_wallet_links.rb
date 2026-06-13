# Appendix C.3 — wallet_links (owner: off-chain). The linchpin of auto-disburse:
# "has a wallet" is an explicit, auditable fact. The address used at disburse is
# whatever is `active` at merge time (A.1 #4).
class CreateWalletLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :wallet_links do |t|
      t.references :user, null: false, foreign_key: true
      t.string   :address, null: false             # checksummed EVM address
      t.datetime :verified_at                       # set if ownership proven via signature
      t.boolean  :active, null: false, default: true

      t.timestamps
    end
    add_index :wallet_links, :address
    # One active wallet per user at a time (A.1 #4 / C.3).
    add_index :wallet_links, :user_id, unique: true, where: "active = 1",
              name: "index_wallet_links_one_active_per_user"
  end
end
