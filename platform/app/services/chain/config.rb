module Chain
  # Resolves the active network parameters (from config/chain.yml) and the
  # signing/relaying keys (from encrypted credentials). Single place the rest of
  # the chain code asks "which chain, which contract, which keys."
  module Config
    module_function

    def settings
      @settings ||= begin
        raw = Rails.application.config_for(:chain)
        raw.symbolize_keys
      end
    end

    def reload!
      @settings = nil
      settings
    end

    def chain_id        = settings.fetch(:chain_id).to_i
    def rpc_url         = settings.fetch(:rpc_url)
    def usdc_address    = settings.fetch(:usdc_address)
    def escrow_address  = settings.fetch(:escrow_address)
    def network         = settings.fetch(:network)
    def confirmations   = settings.fetch(:confirmations, 0).to_i
    def usdc_permit_version = settings.fetch(:usdc_permit_version, "2").to_s

    # The crown jewel: authorizes payouts. Never logged, never plaintext env (A.5).
    def oracle_key
      key = Rails.application.credentials.dig(:chain, :oracle_key)
      raise "chain.oracle_key missing from credentials" if key.blank?

      Eth::Key.new(priv: key)
    end

    # Pays gas only; a leak cannot redirect funds (the contract trusts the
    # signature, not msg.sender). Kept distinct from the oracle key (A.5/§7).
    def relayer_key
      key = Rails.application.credentials.dig(:chain, :relayer_key)
      raise "chain.relayer_key missing from credentials" if key.blank?

      Eth::Key.new(priv: key)
    end

    def oracle_signer_address = oracle_key.address.to_s

    def escrow_configured?
      escrow_address.present? && escrow_address != "0x0000000000000000000000000000000000000000"
    end
  end
end
