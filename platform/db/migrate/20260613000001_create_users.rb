# Appendix C.3 — users (owner: off-chain). The human, identified by GitHub.
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.bigint :github_user_id, null: false        # stable numeric id, never the login
      t.string :github_login                        # current username, for display
      t.string :github_avatar_url
      t.string :email
      t.text   :oauth_token                         # encrypted at model level (encrypts)

      t.timestamps
    end
    add_index :users, :github_user_id, unique: true
  end
end
