require "test_helper"

class BetaBannerTest < ActionDispatch::IntegrationTest
  test "shows the long 'is live' banner on the landing page on beta host" do
    host! "beta.gitreward.com"
    get root_path
    assert_response :success
    assert_select ".beta-banner"
    assert_select ".beta-tag", text: "Beta"
    assert_match(/is live/i, response.body)
  end

  test "shows the short testnet banner on in-app pages on beta host" do
    host! "beta.gitreward.com"
    get directory_path
    assert_response :success
    assert_select ".beta-banner"
    assert_match(/test USDC, not real money/i, response.body)
    assert_no_match(/is live/i, response.body)
  end

  test "hides the banner on any other host" do
    host! "gitreward.com"
    get root_path
    assert_response :success
    assert_select ".beta-banner", count: 0
  end
end
