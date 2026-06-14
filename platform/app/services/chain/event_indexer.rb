module Chain
  # Syncs the escrow's Funded/Disbursed/Refunded events into the DB cache so Rails
  # renders without hitting the chain per request. Chain is the source of truth
  # (C.1): these mirror fields are fully rebuildable by replaying from block 0.
  # Resumable via chain_sync_state.last_synced_block.
  class EventIndexer
    # event signatures -> topic0
    SIGS = {
      funded:    "Funded(uint256,address,uint256,uint16,uint64,bytes32)",
      disbursed: "Disbursed(uint256,address,uint256,uint256)",
      refunded:  "Refunded(uint256,address,uint256)"
    }.freeze

    MAX_BLOCK_SPAN = 2_000 # cap per getLogs window to stay within RPC limits

    def self.topic0(sig) = "0x#{Eth::Util.keccak256(sig).unpack1('H*')}"

    TOPICS = SIGS.transform_values { |s| topic0(s) }.freeze

    def initialize(client: Chain::Client.new)
      @client = client
      @sync = ChainSyncState.for(Chain::Config.escrow_address)
    end

    # Process new blocks once. Returns the block synced to.
    def sync!
      head = @client.latest_block - Chain::Config.confirmations
      from = @sync.last_synced_block.zero? ? 0 : @sync.last_synced_block + 1
      return @sync.last_synced_block if head < from

      from.step(head, MAX_BLOCK_SPAN) do |window_start|
        window_end = [window_start + MAX_BLOCK_SPAN - 1, head].min
        logs = @client.get_logs(from_block: window_start, to_block: window_end)
        logs.each { |log| handle(log) }
        @sync.update!(last_synced_block: window_end)
      end
      head
    end

    private

    def handle(log)
      topic0 = log["topics"]&.first
      case topic0
      when TOPICS[:funded]    then on_funded(log)
      when TOPICS[:disbursed] then on_disbursed(log)
      when TOPICS[:refunded]  then on_refunded(log)
      end
    rescue StandardError => e
      Rails.logger.error("Indexer failed on log #{log['transactionHash']}: #{e.class}: #{e.message}")
    end

    def on_funded(log)
      bounty_id = topic_uint(log, 1)
      funder = topic_address(log, 2)
      amount, fee_snapshot, expiry, _issue_ref =
        Chain::Abi.decode(%w[uint256 uint16 uint64 bytes32], log["data"])

      # Match the pending bounty created by our funding UI (by fund tx hash).
      bounty = Bounty.find_by(fund_tx_hash: log["transactionHash"]) ||
               Bounty.find_by(chain_bounty_id: bounty_id)
      return unless bounty # funded outside our platform; v1 ignores (logged upstream)

      was_funded = bounty.funded?
      bounty.update!(
        chain_bounty_id: bounty_id,
        amount: amount,
        fee_bps_snapshot: fee_snapshot,
        expiry: Time.at(expiry).utc,
        funder_address: funder,
        status: :funded
      )

      # Announce on the issue only on the pending -> funded transition (build
      # plan §1.2 step 3), so a redelivered/re-synced log never double-comments.
      Bounties::Announcer.announce_funded(bounty) unless was_funded
    end

    def on_disbursed(log)
      bounty_id = topic_uint(log, 1)
      recipient = topic_address(log, 2)
      bounty = Bounty.find_by(chain_bounty_id: bounty_id)
      bounty&.update!(status: :disbursed, recipient_address: recipient,
                      disburse_tx_hash: log["transactionHash"])
    end

    def on_refunded(log)
      bounty_id = topic_uint(log, 1)
      bounty = Bounty.find_by(chain_bounty_id: bounty_id)
      bounty&.update!(status: :refunded, refund_tx_hash: log["transactionHash"])
    end

    def topic_uint(log, i) = log["topics"][i].to_i(16)
    # An indexed address is the low 20 bytes (last 40 hex chars) of the 32-byte topic.
    def topic_address(log, i) = "0x#{log['topics'][i][-40..]}"
  end
end
