# Appendix C.3 — repositories (owner: off-chain). Repos covered by an
# installation; lets the funding UI list repos/issues and lets the webhook
# handler map an event to an installation.
class CreateRepositories < ActiveRecord::Migration[8.1]
  def change
    create_table :repositories do |t|
      t.references :installation, null: false, foreign_key: true
      t.bigint :github_repo_id, null: false
      t.string :full_name, null: false               # "owner/repo"
      t.string :default_branch                        # default target branch for bounties

      t.timestamps
    end
    add_index :repositories, :github_repo_id, unique: true
  end
end
