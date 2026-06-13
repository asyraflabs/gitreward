# The discovery layer — the moat (build plan §5). A cross-repo directory of open
# bounties, served from the DB read-model so it's fast and doesn't hammer RPC.
class DirectoryController < ApplicationController
  def index
    @bounties = Bounty.open_directory.includes(:repository).limit(100)
    @total_open = Bounty.funded.sum(:amount)
  end
end
