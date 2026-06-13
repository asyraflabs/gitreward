# Appendix C.3 — installations (owner: off-chain). GitHub App install linking
# GitHub identity <-> App permissions; how the oracle is authorized to read
# issues, comment, and receive merge webhooks.
class CreateInstallations < ActiveRecord::Migration[8.1]
  def change
    create_table :installations do |t|
      t.bigint   :github_installation_id, null: false
      t.string   :account_type, null: false         # "user" | "organization"
      t.bigint   :account_github_id, null: false     # the user/org the install belongs to
      t.references :installed_by_user, foreign_key: { to_table: :users } # nullable; may differ from OAuth
      t.datetime :suspended_at                        # GitHub can suspend installs

      t.timestamps
    end
    add_index :installations, :github_installation_id, unique: true
  end
end
