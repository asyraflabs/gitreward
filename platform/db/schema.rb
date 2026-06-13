# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_13_000008) do
  create_table "attestations", force: :cascade do |t|
    t.integer "bounty_id", null: false
    t.datetime "created_at", null: false
    t.bigint "pr_author_github_id", null: false
    t.string "pr_ref", null: false
    t.string "recipient_address", null: false
    t.text "signature", null: false
    t.datetime "signed_at", null: false
    t.string "submitted_tx_hash"
    t.datetime "updated_at", null: false
    t.index ["bounty_id"], name: "index_attestations_on_bounty_id", unique: true
  end

  create_table "bounties", force: :cascade do |t|
    t.bigint "amount"
    t.bigint "chain_bounty_id"
    t.datetime "created_at", null: false
    t.string "disburse_tx_hash"
    t.datetime "expiry"
    t.integer "fee_bps_snapshot"
    t.string "fund_tx_hash"
    t.string "funder_address"
    t.integer "funder_user_id", null: false
    t.string "github_issue_node_id"
    t.integer "github_issue_number", null: false
    t.string "issue_ref"
    t.string "recipient_address"
    t.string "refund_tx_hash"
    t.integer "repository_id", null: false
    t.string "status", default: "pending", null: false
    t.string "target_branch", null: false
    t.datetime "updated_at", null: false
    t.index ["chain_bounty_id"], name: "index_bounties_on_chain_bounty_id", unique: true
    t.index ["funder_user_id"], name: "index_bounties_on_funder_user_id"
    t.index ["repository_id", "github_issue_number"], name: "index_bounties_on_repository_id_and_github_issue_number"
    t.index ["repository_id", "github_issue_number"], name: "index_one_active_bounty_per_issue", unique: true, where: "status IN ('pending','funded')"
    t.index ["repository_id"], name: "index_bounties_on_repository_id"
    t.index ["status"], name: "index_bounties_on_status"
  end

  create_table "chain_sync_states", force: :cascade do |t|
    t.string "contract_address", null: false
    t.datetime "created_at", null: false
    t.bigint "last_synced_block", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["contract_address"], name: "index_chain_sync_states_on_contract_address", unique: true
  end

  create_table "installations", force: :cascade do |t|
    t.bigint "account_github_id", null: false
    t.string "account_type", null: false
    t.datetime "created_at", null: false
    t.bigint "github_installation_id", null: false
    t.integer "installed_by_user_id"
    t.datetime "suspended_at"
    t.datetime "updated_at", null: false
    t.index ["github_installation_id"], name: "index_installations_on_github_installation_id", unique: true
    t.index ["installed_by_user_id"], name: "index_installations_on_installed_by_user_id"
  end

  create_table "pull_request_events", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "author_github_id"
    t.integer "bounty_id"
    t.datetime "created_at", null: false
    t.string "github_delivery_id", null: false
    t.string "github_pr_node_id", null: false
    t.integer "pr_number"
    t.datetime "processed_at"
    t.datetime "updated_at", null: false
    t.index ["bounty_id"], name: "index_pull_request_events_on_bounty_id"
    t.index ["github_delivery_id"], name: "index_pull_request_events_on_github_delivery_id", unique: true
  end

  create_table "repositories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "default_branch"
    t.string "full_name", null: false
    t.bigint "github_repo_id", null: false
    t.integer "installation_id", null: false
    t.datetime "updated_at", null: false
    t.index ["github_repo_id"], name: "index_repositories_on_github_repo_id", unique: true
    t.index ["installation_id"], name: "index_repositories_on_installation_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "github_avatar_url"
    t.string "github_login"
    t.bigint "github_user_id", null: false
    t.text "oauth_token"
    t.datetime "updated_at", null: false
    t.index ["github_user_id"], name: "index_users_on_github_user_id", unique: true
  end

  create_table "wallet_links", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "address", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.datetime "verified_at"
    t.index ["address"], name: "index_wallet_links_on_address"
    t.index ["user_id"], name: "index_wallet_links_on_user_id"
    t.index ["user_id"], name: "index_wallet_links_one_active_per_user", unique: true, where: "active = 1"
  end

  add_foreign_key "attestations", "bounties"
  add_foreign_key "bounties", "repositories"
  add_foreign_key "bounties", "users", column: "funder_user_id"
  add_foreign_key "installations", "users", column: "installed_by_user_id"
  add_foreign_key "pull_request_events", "bounties"
  add_foreign_key "repositories", "installations"
  add_foreign_key "wallet_links", "users"
end
