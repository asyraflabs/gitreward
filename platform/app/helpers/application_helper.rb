module ApplicationHelper
  # True only on the public testnet beta host, so the "testnet live" banner
  # shows there but not in dev or on a future mainnet domain.
  def beta_host?
    request.host == "beta.gitreward.com"
  end
end
