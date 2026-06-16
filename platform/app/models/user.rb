# The human, identified by their GitHub account (C.2 identity model).
# "Maintainer" and "contributor" are behaviors, not types — inferred from
# relationships, no role column.
class User < ApplicationRecord
  encrypts :oauth_token

  has_many :wallet_links, dependent: :destroy
  has_many :installations, foreign_key: :installed_by_user_id, dependent: :nullify, inverse_of: :installed_by_user
  has_many :repositories, through: :installations
  has_many :bounties, foreign_key: :funder_user_id, dependent: :restrict_with_exception, inverse_of: :funder_user

  validates :github_user_id, presence: true, uniqueness: true

  # The wallet a disbursement would pay (A.1 #4: whatever is active at merge time).
  def active_wallet
    wallet_links.find_by(active: true)
  end

  # Heal the "installed the App before I ever logged in" ordering: adopt any
  # unlinked installation on this user's own account (account id == our github
  # id). Org installs link via the webhook sender instead. Idempotent.
  def claim_installations!
    Installation.where(account_github_id: github_user_id, installed_by_user_id: nil)
                .update_all(installed_by_user_id: id)
  end

  def wallet_linked?
    active_wallet.present?
  end

  # Find-or-create from an OmniAuth GitHub callback.
  def self.from_github_auth(auth)
    user = find_or_initialize_by(github_user_id: auth.uid.to_i)
    user.github_login = auth.info.nickname
    user.github_avatar_url = auth.info.image
    user.email = auth.info.email
    user.oauth_token = auth.credentials&.token if auth.credentials&.token
    user.save!
    user
  end
end
