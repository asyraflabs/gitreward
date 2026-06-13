# A repo covered by an installation (C.3). Lets the funding UI list repos/issues
# and lets the webhook handler map an event to an installation.
class Repository < ApplicationRecord
  belongs_to :installation
  has_many :bounties, dependent: :restrict_with_exception

  validates :github_repo_id, presence: true, uniqueness: true
  validates :full_name, presence: true

  def owner_login
    full_name.to_s.split("/").first
  end

  def name
    full_name.to_s.split("/").last
  end
end
