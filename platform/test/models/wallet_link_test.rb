require "test_helper"

class WalletLinkTest < ActiveSupport::TestCase
  setup { @user = User.create!(github_user_id: 1, github_login: "dev") }

  test "stores the EIP-55 checksummed address" do
    w = @user.wallet_links.create!(address: "0x14dc79964da2c08b23698b3d3cc7ca32193d9955")
    assert_equal "0x14dC79964da2C08b23698B3D3cc7Ca32193d9955", w.address
  end

  test "rejects malformed addresses" do
    w = @user.wallet_links.build(address: "not-an-address")
    assert_not w.valid?
  end

  test "activate! enforces a single active wallet" do
    a = @user.wallet_links.create!(address: "0x14dC79964da2C08b23698B3D3cc7Ca32193d9955")
    b = @user.wallet_links.create!(address: "0x90F79bf6EB2c4f870365E785982E1f101E93b906", active: false)
    b.activate!
    assert_equal b, @user.reload.active_wallet
    assert_not a.reload.active
  end
end
