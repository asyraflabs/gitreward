import { Controller } from "@hotwired/stimulus"
import {
  createWalletClient, createPublicClient, custom, defineChain, parseUnits
} from "viem"

// The only browser chain code in the app (build plan §2): connect wallet, sign a
// gasless USDC EIP-2612 permit, then send the escrow `fund` tx. Everything else
// is server-rendered Hotwire. Two DISTINCT EIP-712 domains are in play here — the
// USDC permit domain (name from the token, version per network) and, separately,
// GitReward's disbursement domain (signed server-side, never here). Don't conflate.
export default class extends Controller {
  static targets = ["issue", "branch", "amount", "expiry", "submit", "status", "feeLabel",
                    "lockedOut", "feeOut", "netOut"]
  static values = {
    chainId: Number, escrow: String, usdc: String, usdcVersion: String,
    feeBps: Number, createUrl: String, repositoryId: Number, csrf: String,
    rpcUrl: String, chainName: String, chainBountyId: Number, refundUrl: String
  }

  connect() { this.recalc() }

  // Live escrow summary: split the locked amount into fee + net by the live feeRate.
  // No-op on pages without the amount field (e.g. the refund button on bounty show).
  recalc() {
    if (!this.hasAmountTarget) return
    const amt = parseFloat(this.amountTarget.value || 0)
    const feeRate = (this.feeBpsValue || 0) / 10000
    const fee = amt * feeRate
    const net = amt - fee
    if (this.hasLockedOutTarget) this.lockedOutTarget.textContent = amt.toFixed(2) + " USDC"
    if (this.hasFeeOutTarget) this.feeOutTarget.textContent = "−" + fee.toFixed(2) + " USDC"
    if (this.hasNetOutTarget) this.netOutTarget.textContent = net.toFixed(2)
  }

  // Minimal ABIs (the only functions we touch in-browser).
  fundAbi = [{
    type: "function", name: "fund", stateMutability: "nonpayable",
    inputs: [
      { name: "amount", type: "uint256" }, { name: "expiry", type: "uint64" },
      { name: "issueRef", type: "bytes32" }, { name: "permitValue", type: "uint256" },
      { name: "permitDeadline", type: "uint256" }, { name: "permitV", type: "uint8" },
      { name: "permitR", type: "bytes32" }, { name: "permitS", type: "bytes32" }
    ],
    outputs: [{ name: "bountyId", type: "uint256" }]
  }]
  usdcAbi = [
    { type: "function", name: "name", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
    { type: "function", name: "nonces", stateMutability: "view", inputs: [{ name: "owner", type: "address" }], outputs: [{ type: "uint256" }] }
  ]
  refundAbi = [{
    type: "function", name: "refund", stateMutability: "nonpayable",
    inputs: [{ name: "bountyId", type: "uint256" }], outputs: []
  }]

  chain() {
    return defineChain({
      id: this.chainIdValue,
      name: this.chainNameValue || `chain-${this.chainIdValue}`,
      nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
      rpcUrls: { default: { http: this.rpcUrlValue ? [this.rpcUrlValue] : [] } }
    })
  }

  // Make sure the wallet is on our chain BEFORE any contract read. Reading
  // USDC.name() while the wallet is on the wrong network returns "0x" (no code
  // at that address there) — the confusing first-click error. Switch (and add
  // the network if the wallet doesn't know it) so that can't happen.
  async ensureChain(wallet) {
    const current = await wallet.getChainId()
    if (current === this.chainIdValue) return

    this.busy(`Switch your wallet to ${this.chainNameValue || "the right network"}…`)
    try {
      await wallet.switchChain({ id: this.chainIdValue })
    } catch (e) {
      const unknownChain = e?.code === 4902 || /unrecognized|not been added|4902|does not match/i.test(`${e?.message} ${e?.cause?.message}`)
      if (!unknownChain) throw e
      // Wallet doesn't have the network yet — add it, then switch.
      await wallet.addChain({ chain: this.chain() })
      await wallet.switchChain({ id: this.chainIdValue })
    }
  }

  async fund(event) {
    event.preventDefault()
    if (!window.ethereum) return this.fail("No Ethereum wallet found. Install MetaMask or a Base wallet.")

    const issueEl = this.issueTarget.selectedOptions[0]
    if (!issueEl) return this.fail("Select an issue to fund.")
    const issueNumber = issueEl.value
    const issueNodeId = issueEl.dataset.nodeId
    const issueRef = issueEl.dataset.issueRef

    const usdcAmount = this.amountTarget.value
    const days = parseInt(this.expiryTarget.value, 10)
    if (!usdcAmount || Number(usdcAmount) < 5) return this.fail("Minimum bounty is 5 USDC.")
    if (!days || days < 7) return this.fail("Expiry must be at least 7 days.")

    const amount = parseUnits(usdcAmount, 6)               // USDC base units (6 decimals)
    // +1h buffer so a `days`-day expiry clears the contract's `now + days` minimum
    // even though the chain's block.timestamp runs a few seconds ahead of Date.now()
    // (without it, selecting the exact 7-day minimum reverts with ExpiryTooSoon).
    const now = Math.floor(Date.now() / 1000)
    const expiry = BigInt(now + days * 86400 + 3600)
    const deadline = BigInt(now + 3600)

    try {
      this.busy("Connecting wallet…")
      const chain = this.chain()
      const wallet = createWalletClient({ chain, transport: custom(window.ethereum) })
      const [account] = await wallet.requestAddresses()

      // Get on the right network first, then build the read client against it.
      await this.ensureChain(wallet)
      const pub = createPublicClient({ chain, transport: custom(window.ethereum) })

      this.busy("Reading USDC permit details…")
      const [tokenName, nonce] = await Promise.all([
        pub.readContract({ address: this.usdcValue, abi: this.usdcAbi, functionName: "name" }),
        pub.readContract({ address: this.usdcValue, abi: this.usdcAbi, functionName: "nonces", args: [account] })
      ])

      this.busy("Sign the USDC permit (gasless)…")
      const permitSig = await wallet.signTypedData({
        account,
        domain: { name: tokenName, version: this.usdcVersionValue, chainId: this.chainIdValue, verifyingContract: this.usdcValue },
        types: {
          Permit: [
            { name: "owner", type: "address" }, { name: "spender", type: "address" },
            { name: "value", type: "uint256" }, { name: "nonce", type: "uint256" },
            { name: "deadline", type: "uint256" }
          ]
        },
        primaryType: "Permit",
        message: { owner: account, spender: this.escrowValue, value: amount, nonce, deadline }
      })
      const { v, r, s } = this.splitSig(permitSig)

      this.busy("Confirm the fund transaction in your wallet…")
      const txHash = await wallet.writeContract({
        account, chain,
        address: this.escrowValue, abi: this.fundAbi, functionName: "fund",
        args: [amount, expiry, issueRef, amount, deadline, v, r, s]
      })

      this.busy("Recording your bounty…")
      await this.record({ issueNumber, issueNodeId, issueRef, amount, expiry, txHash })
    } catch (e) {
      console.error(e)
      this.fail(e.shortMessage || e.message || "Funding failed.")
    }
  }

  // Refund a funded, expired bounty back to the funder. Permissionless on-chain
  // (the contract requires msg.sender == funder), no permit, no oracle — the
  // connected wallet must be the one that funded.
  async refund(event) {
    event.preventDefault()
    if (!window.ethereum) return this.fail("No Ethereum wallet found.")
    try {
      this.busy("Connecting wallet…")
      const chain = this.chain()
      const wallet = createWalletClient({ chain, transport: custom(window.ethereum) })
      const [account] = await wallet.requestAddresses()
      await this.ensureChain(wallet)

      this.busy("Confirm the refund in your wallet…")
      const txHash = await wallet.writeContract({
        account, chain,
        address: this.escrowValue, abi: this.refundAbi, functionName: "refund",
        args: [BigInt(this.chainBountyIdValue)]
      })

      this.busy("Refund submitted, confirming…")
      const res = await fetch(this.refundUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfValue, "Accept": "application/json" },
        body: JSON.stringify({ tx_hash: txHash })
      })
      const data = await res.json()
      if (data.ok) { this.busy("Refunded! Updating…"); window.location = data.redirect }
      else this.fail((data.errors || ["Could not record refund"]).join(", "))
    } catch (e) {
      console.error(e)
      this.fail(e.shortMessage || e.message || "Refund failed.")
    }
  }

  async record({ issueNumber, issueNodeId, issueRef, amount, expiry, txHash }) {
    const res = await fetch(this.createUrlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfValue, "Accept": "application/json" },
      body: JSON.stringify({
        repository_id: this.repositoryIdValue,
        bounty: {
          amount: amount.toString(),
          fee_bps_snapshot: this.feeBpsValue,
          expiry: expiry.toString(),
          github_issue_number: issueNumber,
          github_issue_node_id: issueNodeId,
          target_branch: this.branchTarget.value,
          issue_ref: issueRef,
          fund_tx_hash: txHash
        }
      })
    })
    const data = await res.json()
    if (data.ok) {
      this.busy("Funded! Redirecting…")
      window.location = data.redirect
    } else {
      this.fail((data.errors || ["Could not record bounty"]).join(", "))
    }
  }

  splitSig(sig) {
    const r = `0x${sig.slice(2, 66)}`
    const s = `0x${sig.slice(66, 130)}`
    const v = parseInt(sig.slice(130, 132), 16)
    return { v, r, s }
  }

  busy(msg) {
    this.submitTarget.disabled = true
    this.statusTarget.textContent = msg
    this.statusTarget.className = "hint"
    this.statusTarget.style.color = "var(--tx-2)"
  }

  fail(msg) {
    this.submitTarget.disabled = false
    this.statusTarget.textContent = msg
    this.statusTarget.className = "hint"
    this.statusTarget.style.color = "#f17171"
  }
}
