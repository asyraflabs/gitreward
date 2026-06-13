# Honest trust/status page (build plan §5/§8): settled count, total paid, the
# zero-loss track record, and a plain-English trust model. Never says "trustless".
class TrustController < ApplicationController
  def index
    @settled_count = Bounty.disbursed.count
    @total_paid = Bounty.disbursed.sum(:amount)
    @refunded_count = Bounty.refunded.count
    @open_count = Bounty.funded.count
    @fee_bps = live_fee_bps
    @escrow_address = Chain::Config.escrow_address if Chain::Config.escrow_configured?
    @network = Chain::Config.network
  end

  private

  def live_fee_bps
    Chain::Client.new.fee_rate_bps
  rescue StandardError
    300
  end
end
