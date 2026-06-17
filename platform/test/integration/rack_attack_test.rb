require "test_helper"

# Proves Rack::Attack actually throttles. Test env's cache is :null_store (no
# counting), so we swap in a real store; and we use a non-localhost IP so the
# "allow-localhost" safelist doesn't apply.
class RackAttackTest < ActionDispatch::IntegrationTest
  PUBLIC_IP = { "REMOTE_ADDR" => "203.0.113.7" }.freeze

  setup do
    @orig_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rack::Attack.cache.store = @orig_store }

  test "throttles repeated POST /auth/github from one IP (429 past the limit)" do
    # logins/ip throttle is 15/min; the 16th+ from the same IP should be blocked.
    codes = Array.new(17) do
      post "/auth/github", headers: PUBLIC_IP
      response.status
    end
    assert_includes codes, 429, "expected a 429 once the per-IP login throttle trips"
    assert_equal 429, codes.last
  end

  test "does not throttle a single request" do
    post "/auth/github", headers: PUBLIC_IP
    assert_not_equal 429, response.status
  end
end
