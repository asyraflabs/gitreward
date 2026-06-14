require "test_helper"

# Covers the "installed before I logged in" healing (User#claim_installations!)
# and the rule that re-syncing never clobbers the original installer.
class InstallationLinkingTest < ActiveSupport::TestCase
  test "claim_installations! adopts unlinked installs on the user's own account" do
    # Installation created by the webhook path before the user ever logged in.
    inst = Installation.create!(github_installation_id: 1, account_type: "user",
                                account_github_id: 12868523, installed_by_user: nil)
    user = User.create!(github_user_id: 12868523, github_login: "jimmyasyraf")

    assert_nil inst.installed_by_user_id
    user.claim_installations!
    assert_equal user.id, inst.reload.installed_by_user_id
  end

  test "claim_installations! ignores installs on other accounts (e.g. orgs)" do
    org_inst = Installation.create!(github_installation_id: 2, account_type: "organization",
                                    account_github_id: 999_999, installed_by_user: nil)
    user = User.create!(github_user_id: 12868523, github_login: "jimmyasyraf")

    user.claim_installations!
    assert_nil org_inst.reload.installed_by_user_id
  end

  test "claim_installations! is idempotent and leaves already-linked installs alone" do
    owner = User.create!(github_user_id: 12868523, github_login: "owner")
    other = User.create!(github_user_id: 777, github_login: "other")
    inst = Installation.create!(github_installation_id: 3, account_type: "user",
                                account_github_id: 12868523, installed_by_user: other)

    owner.claim_installations! # account id matches owner, but it's already linked to `other`
    assert_equal other.id, inst.reload.installed_by_user_id
  end
end
