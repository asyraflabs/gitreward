module ExplorerHelper
  # Block-explorer links for on-chain verification. Return nil when no explorer
  # is configured (e.g. local anvil) so callers fall back to plain text.
  def explorer_address_url(address)
    base = Chain::Config.explorer_url
    "#{base}/address/#{address}" if base.present? && address.present?
  end

  def explorer_tx_url(tx_hash)
    base = Chain::Config.explorer_url
    "#{base}/tx/#{tx_hash}" if base.present? && tx_hash.present?
  end

  # Human label for the explorer (e.g. "Basescan") — the second-level domain of
  # its host (sepolia.basescan.org -> Basescan, basescan.org -> Basescan).
  def explorer_name
    host = (URI(Chain::Config.explorer_url).host.to_s rescue "")
    return "block explorer" if host.blank?

    parts = host.sub(/\Awww\./, "").split(".")
    (parts.length >= 2 ? parts[-2] : parts.first).to_s.capitalize
  end
end
