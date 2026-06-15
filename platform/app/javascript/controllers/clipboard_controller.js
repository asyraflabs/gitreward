import { Controller } from "@hotwired/stimulus"

// Copy-to-clipboard for the address/tx "copy chip". Swaps the icon to a green
// check for ~1.2s on success. (Design handoff §3 clipboard_controller.)
export default class extends Controller {
  static targets = ["icon"]
  static values = { text: String }

  copy() {
    navigator.clipboard.writeText(this.textValue).catch(() => {})
    if (!this.hasIconTarget) return
    const original = this.iconTarget.innerHTML
    this.iconTarget.innerHTML = CHECK
    this.iconTarget.classList.add("text-[var(--green)]")
    setTimeout(() => {
      this.iconTarget.innerHTML = original
      this.iconTarget.classList.remove("text-[var(--green)]")
    }, 1200)
  }
}

const CHECK = `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12 4.5 4.5L19 7"/></svg>`
