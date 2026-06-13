# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# viem — pinned to a single jsdelivr /+esm bundle, NOT `bin/importmap pin viem`.
# The default downloader can't follow viem's relative-import chunk graph (404s);
# the /+esm bundle inlines the whole dep tree (@noble, abitype, ox) into one
# file that works in-browser with no build step. (Build plan §2 / table row.)
pin "viem", to: "https://cdn.jsdelivr.net/npm/viem@2.52.2/+esm"
