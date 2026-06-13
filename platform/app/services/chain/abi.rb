module Chain
  # Thin wrapper so callers decode log `data` (a 0x-hex string) without worrying
  # about eth.rb expecting binary input.
  module Abi
    module_function

    def decode(types, hex_data)
      bin = [hex_data.to_s.sub(/\A0x/, "")].pack("H*")
      Eth::Abi.decode(types, bin)
    end
  end
end
