require "net/http"
module Chain
  # Thin wrapper over eth.rb for the escrow contract: read views, submit the
  # disburse tx (relayer pays gas), and fetch logs for the indexer. Reads use the
  # node directly; the only state-changing call is `disburse` — funding happens
  # in the user's browser (viem), and refunds are the funder's own call.
  class Client
    ABI_PATH = Rails.root.join("config", "abi", "GitRewardEscrow.json")

    class NotConfigured < StandardError; end

    # eth.rb's Contract.from_abi expects the ABI as a JSON STRING, not a parsed array.
    def self.abi_json
      @abi_json ||= File.read(ABI_PATH)
    end

    def initialize
      raise NotConfigured, "escrow address not set (config/chain.yml)" unless Chain::Config.escrow_configured?

      @eth = Eth::Client.create(Chain::Config.rpc_url)
      @escrow = Eth::Contract.from_abi(
        name: "GitRewardEscrow", address: Chain::Config.escrow_address, abi: self.class.abi_json
      )
    end

    attr_reader :eth, :escrow

    # --- views ---

    def fee_rate_bps     = call("feeRate").to_i
    def max_fee_bps       = call("MAX_FEE").to_i
    def min_bounty_units  = call("MIN_BOUNTY").to_i
    def next_bounty_id    = call("nextBountyId").to_i
    def oracle_signer     = call("oracleSigner")
    def treasury          = call("treasury")

    # Returns a hash mirroring the Bounty struct (A.4). Decoded manually from a
    # raw eth_call: getBounty returns a struct, and eth.rb 0.5.x can't decode
    # tuple return types (the "eth.rb < viem depth" caveat, build plan §10). The
    # struct is five flat statics, so a direct decode is exact.
    def get_bounty(chain_bounty_id)
      selector = Eth::Util.keccak256("getBounty(uint256)")[0, 4]
      calldata = "0x" + (selector + Eth::Abi.encode(%w[uint256], [chain_bounty_id.to_i])).unpack1("H*")
      raw = @eth.eth_call(to: Chain::Config.escrow_address, data: calldata).dig("result")
      funder, amount, fee_snapshot, expiry, status =
        Chain::Abi.decode(%w[address uint256 uint16 uint64 uint8], raw)
      {
        funder: normalize_address(funder),
        amount: amount.to_i,
        fee_snapshot: fee_snapshot.to_i,
        expiry: Time.at(expiry.to_i).utc,
        status: %i[none funded disbursed refunded][status.to_i]
      }
    end

    # --- the one state-changing call the backend makes ---
    # Submitted by the relayer; the contract trusts the SIGNATURE, not the sender.
    DISBURSE_GAS_LIMIT = 200_000 # measured ~100-130k; headroom for fee transfer
    MIN_PRIORITY_FEE = 1_000_000 # 0.001 gwei floor (Base accepts tiny tips)
    FALLBACK_BASE_FEE = 1_000_000_000 # 1 gwei if the node won't report baseFeePerGas

    class DisburseFailed < StandardError; end

    # Returns the tx hash on success. eth.rb's transact_and_wait returns
    # [tx_hash, success_bool]; we raise on a reverted tx so the caller doesn't
    # record a bogus disbursement. Gas is priced off the live base fee — eth.rb's
    # default maxFee is ~42 gwei, which on a sub-gwei chain like Base makes the
    # upfront balance check (gas_limit * maxFee) demand far more ETH than the tx
    # actually costs.
    def disburse(chain_bounty_id:, recipient:, signature:)
      base = base_fee_per_gas
      priority = [base, MIN_PRIORITY_FEE].max
      # eth.rb builds the 1559 tx from these client attributes (not kwargs); its
      # defaults are tens of gwei, which blows the upfront balance check on Base.
      @eth.max_priority_fee_per_gas = priority
      @eth.max_fee_per_gas = base * 3 + priority # buffer for base-fee rise

      tx_hash, success = @eth.transact_and_wait(
        @escrow, "disburse", chain_bounty_id, recipient, hex_to_bin(signature),
        sender_key: Chain::Config.relayer_key, gas_limit: DISBURSE_GAS_LIMIT
      )
      raise DisburseFailed, "disburse tx #{tx_hash} reverted" unless success

      tx_hash
    end

    def base_fee_per_gas
      bf = rpc("eth_getBlockByNumber", ["latest", false])&.dig("baseFeePerGas")
      bf ? bf.to_i(16) : FALLBACK_BASE_FEE
    end

    # --- logs for the indexer ---
    # Use raw JSON-RPC: eth.rb's auto-generated eth_getLogs/eth_blockNumber mangle
    # the camelCase param keys (fromBlock -> fromblock). Raw keeps us exact.
    def latest_block = rpc("eth_blockNumber").to_i(16)

    def get_logs(from_block:, to_block:, topics: nil)
      filter = {
        address: Chain::Config.escrow_address,
        fromBlock: hex(from_block),
        toBlock: to_block == :latest ? "latest" : hex(to_block)
      }
      filter[:topics] = topics if topics
      rpc("eth_getLogs", [filter]) || []
    end

    private

    def call(fn, *args) = @eth.call(@escrow, fn, *args)

    # Minimal JSON-RPC POST. Returns the `result`; raises on RPC error.
    def rpc(method, params = [])
      uri = URI(Chain::Config.rpc_url)
      req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      req.body = { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |h| h.request(req) }
      body = JSON.parse(res.body)
      raise "RPC #{method} error: #{body['error']}" if body["error"]

      body["result"]
    end

    def hex(n) = "0x#{n.to_i.to_s(16)}"

    # eth.rb decodes an `address` to an int or bare hex; present it checksummed.
    def normalize_address(value)
      hexstr = value.is_a?(Integer) ? "0x#{value.to_s(16).rjust(40, '0')}" : value.to_s
      hexstr = "0x#{hexstr}" unless hexstr.start_with?("0x")
      Eth::Address.new(hexstr).checksummed
    rescue StandardError
      value.to_s
    end

    # eth.rb's bytes encoder wants a binary string, not a 0x-hex string.
    def hex_to_bin(sig)
      s = sig.to_s.sub(/\A0x/, "")
      [s].pack("H*")
    end
  end
end
