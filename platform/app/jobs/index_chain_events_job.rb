# Recurring indexer pass: pulls new escrow events into the DB cache. Scheduled in
# config/recurring.yml. No-ops gracefully if the chain isn't configured/reachable.
class IndexChainEventsJob < ApplicationJob
  queue_as :default

  def perform
    return unless Chain::Config.escrow_configured?

    Chain::EventIndexer.new.sync!
  rescue Chain::Client::NotConfigured
    # escrow not set yet; nothing to index
  rescue StandardError => e
    Rails.logger.error("IndexChainEventsJob failed: #{e.class}: #{e.message}")
    raise
  end
end
