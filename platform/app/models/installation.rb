# A GitHub App installation (C.3). Links GitHub identity <-> App permissions and
# authorizes the oracle to read issues, comment, and receive merge webhooks.
class Installation < ApplicationRecord
  belongs_to :installed_by_user, class_name: "User", optional: true
  has_many :repositories, dependent: :destroy

  enum :account_type, { user: "user", organization: "organization" }, prefix: :account

  validates :github_installation_id, presence: true, uniqueness: true
  validates :account_github_id, presence: true

  scope :active, -> { where(suspended_at: nil) }

  def suspended?
    suspended_at.present?
  end
end
