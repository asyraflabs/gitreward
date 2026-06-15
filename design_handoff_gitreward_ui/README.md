# Handoff: GitReward — dark / orange shadcn UI (Ruby on Rails)

## Overview
A visual redesign of GitReward's authenticated app (a bounty marketplace for GitHub
issues, escrowed in USDC on Base). It unifies the app with the marketing site's
**near-black + single-orange** identity, expressed in the **shadcn/ui** design language.

Screens: **Open Bounties**, **View Bounty**, **Fund a Bounty**, **Dashboard**, **Payout Wallet**.

## About the design files
The files in `reference/` are **design references built in HTML/React+Babel** — a
prototype showing the intended look and behavior. They are **not** meant to be shipped.
Recreate them in the GitReward **Rails** app using server-rendered views + Hotwire.

shadcn/ui itself is React, so its components don't drop into ERB. But shadcn is two
separable layers, and only the visual layer matters here:
- **Visual layer** = CSS variables + Tailwind classes + radii/type scale. This is
  framework-agnostic. `reference/styles.css` is **plain CSS with no React** — port it
  directly; the screens will look identical.
- **Behavior layer** = tabs, copy, the fund tx flow, wallet validation. Rebuild these as
  **Stimulus** controllers (specced below). Use **Turbo** for navigation.

## Fidelity
**High-fidelity.** Colors, type, spacing, radii, and interactions are final. Recreate
pixel-faithfully.

## Target stack (assumed)
- Rails 7+ with **Hotwire** (Turbo + Stimulus).
- **tailwindcss-rails** (or cssbundling-rails). Tailwind is the styling layer.
- **ViewComponent** *or* **Phlex** *or* plain **ERB partials** for componentization.
  This README gives **ERB partials** (the lowest common denominator); if you use
  ViewComponent, each partial below maps 1:1 to a `*Component` + its template.
- Icons via inline SVG partials (see `reference/components.jsx` → object `I` for the paths).

---

## 1. Tokens & Tailwind setup

The palette is **zinc-950 dark** with **orange** as the single accent. Define the tokens
once as CSS variables, then reference them from Tailwind. Source of truth:
`reference/styles.css` `:root`.

### `app/assets/stylesheets/application.css` (or your Tailwind entry `@layer base`)
```css
:root {
  --background:#09090B; --card:#121214; --secondary:#1B1B1E; --card-hover:#17171A;
  --input:#0B0B0D; --border:rgba(255,255,255,.08); --border-strong:rgba(255,255,255,.13);
  --foreground:#FAFAFA; --muted-foreground:#A1A1AA; --subtle:#71717A;
  --primary:#F97316; --primary-hover:#FB8A3C; --primary-foreground:#1A0D02;
  --orange-soft:rgba(249,115,22,.13); --orange-line:rgba(249,115,22,.34);
  --success:#4FB477; --success-soft:rgba(79,180,119,.12); --success-line:rgba(79,180,119,.3);
  --radius:14px; --radius-sm:8px; --radius-md:6px;
}
html,body{ background:var(--background); color:var(--foreground);
  font-family:Inter,system-ui,sans-serif; -webkit-font-smoothing:antialiased; }
```

### `tailwind.config.js` — surface the variables as Tailwind colors
```js
theme: { extend: {
  colors: {
    background:'var(--background)', card:'var(--card)', secondary:'var(--secondary)',
    input:'var(--input)', border:'var(--border)',
    foreground:'var(--foreground)', muted:'var(--muted-foreground)', subtle:'var(--subtle)',
    primary:{ DEFAULT:'var(--primary)', hover:'var(--primary-hover)', fg:'var(--primary-foreground)' },
    success:'var(--success)',
  },
  borderRadius:{ xl:'14px', lg:'10px', md:'8px', sm:'6px' },
  fontFamily:{ sans:['Inter','system-ui','sans-serif'] },
}}
```

> Orange is used **sparingly**: primary buttons, monetary amounts, the "funded" badge,
> links, focus rings, small accent icons. Everything else is neutral.

### Token reference (exact values)
| Role | Value |
|---|---|
| Canvas bg | `#09090B` |
| Card / surface | `#121214` |
| Secondary / muted surface | `#1B1B1E` |
| Card hover | `#17171A` |
| Input bg | `#0B0B0D` |
| Border hairline / strong | `rgba(255,255,255,.08)` / `.13` |
| Foreground | `#FAFAFA` |
| Muted foreground | `#A1A1AA` |
| Subtle | `#71717A` |
| Primary (orange) / hover / fg | `#F97316` / `#FB8A3C` / `#1A0D02` |
| Orange soft / line | `rgba(249,115,22,.13)` / `.34` |
| Success / soft / line | `#4FB477` / `rgba(79,180,119,.12)` / `.3` |

### Type & metrics
- Family **Inter**, base 16px. Page title 28px/600/-0.025em; card title 15.5px/600;
  card description 13.5px muted; body 14.5px muted; eyebrow 11px/600 uppercase/0.08em subtle.
- Radius: card 14px · button/input/tabs 8px · badge/chip/icon 6px · pill 999px.
- Card shadow `0 1px 2px 0 rgba(0,0,0,.4)`. Content max-width 1120px, padding 28px (16px <800px).
- Focus ring: 2px solid orange, 2px offset (keep for a11y).
- No monospace anywhere — amounts/addresses use Inter (tabular-nums for numbers).

---

## 2. Components as ERB partials

Place under `app/views/ui/`. Each partial lists its **locals** and a **markup sketch**
(Tailwind classes shown for the key styling — fall back to the exact values in
`reference/styles.css` if a utility isn't configured). For ViewComponent, the same locals
become component args.

### `ui/_button.html.erb`
Locals: `label`, `variant:` (`primary`|`secondary`|`ghost`), `size:` (`sm`|`md`|`lg`),
`type:`, `icon:`, `disabled:`, `data:` (for Stimulus actions), `block:`.
```erb
<%# heights: sm 34 / md 40 / lg 42 ; radius-md(8) ; weight 600 primary else 500 %>
<button type="<%= type || 'button' %>" <%= 'disabled' if disabled %>
  data="<%= data %>"
  class="inline-flex items-center justify-center gap-2 rounded-md font-medium whitespace-nowrap
         h-10 px-4 text-sm transition disabled:opacity-60 disabled:cursor-not-allowed
         <%= block ? 'w-full' : '' %>
         <%= { 'primary'  => 'bg-primary text-primary-fg font-semibold hover:bg-primary-hover',
               'secondary'=> 'bg-secondary text-foreground border border-border hover:bg-[#232327]',
               'ghost'    => 'bg-transparent text-foreground border border-border-strong hover:bg-secondary'
             }[variant || 'primary'] %>">
  <%= icon %><%= label %>
</button>
```

### `ui/_badge.html.erb`
Locals: `status:` (`funded`|`open`|`paid`|`merged`), or `label:`+`tone:`.
```erb
<%# rounded-md, 11px/600, px2 py0.5, soft fill + 1px border %>
<span class="inline-flex items-center rounded-sm text-[11px] font-semibold leading-tight px-2 py-0.5
  <%= { 'funded'=>'text-primary bg-[var(--orange-soft)] border border-[var(--orange-line)]',
        'open'  =>'text-muted bg-secondary border border-border-strong',
        'paid'  =>'text-success bg-[var(--success-soft)] border border-[var(--success-line)]',
        'merged'=>'text-success bg-[var(--success-soft)] border border-[var(--success-line)]'
      }[status] %>">
  <%= { 'funded'=>'Funded','open'=>'Open','paid'=>'Paid out','merged'=>'Merged' }[status] %>
</span>
```

### `ui/_card.html.erb`
Locals: `title:`, `description:`, `block:` (content via `yield`/`capture`).
```erb
<div class="bg-card border border-border rounded-xl shadow-[0_1px_2px_0_rgba(0,0,0,.4)] p-[22px]">
  <% if title %>
    <div class="mb-[18px]">
      <h3 class="text-[15.5px] font-semibold tracking-[-0.01em]"><%= title %></h3>
      <% if description %><p class="text-[13.5px] text-muted leading-relaxed mt-1"><%= description %></p><% end %>
    </div>
  <% end %>
  <%= block %>
</div>
```

### `ui/_icon_box.html.erb`
Locals: `icon:`, `orange:` (bool). 38px rounded-square (radius 9px).
```erb
<span class="grid place-items-center w-[38px] h-[38px] rounded-[9px] shrink-0 border
  <%= orange ? 'bg-[var(--orange-soft)] border-[var(--orange-line)] text-primary'
             : 'bg-secondary border-border text-muted' %>"><%= icon %></span>
```

### `ui/_input.html.erb` / `ui/_select.html.erb`
Locals: `name:`, `value:`, `type:`, `placeholder:`, `data:`, `options:` (select).
```erb
<%# h-10, bg-input, border-strong, radius-md; focus = orange border + 3px orange ring %>
<input name="<%= name %>" value="<%= value %>" type="<%= type || 'text' %>"
  placeholder="<%= placeholder %>" data="<%= data %>" spellcheck="false"
  class="w-full h-10 px-[13px] bg-input border border-border-strong rounded-md text-sm
         text-foreground outline-none transition
         focus:border-primary focus:shadow-[0_0_0_3px_var(--orange-soft)]
         placeholder:text-subtle">
```
Select: same shell, `appearance-none pr-9` + a chevron background SVG (see styles.css `.select`).

### `ui/_kv.html.erb`
Locals: `k:`, `v:` (html-safe). Space-between row, 14px padding, bottom hairline.
```erb
<div class="flex justify-between items-center gap-4 py-[14px] border-b border-border last:border-0">
  <span class="text-muted text-sm"><%= k %></span>
  <span class="text-sm font-medium text-right whitespace-nowrap"><%= v %></span>
</div>
```

### `ui/_amount.html.erb`
Locals: `value:`, `size:` (px), `color:` (default foreground; use `text-primary` for rewards).
```erb
<span class="font-semibold tracking-[-0.02em] whitespace-nowrap <%= color %>" style="font-size:<%= size %>px">
  <%= value %><span class="font-medium text-muted ml-[5px]" style="font-size:.6em">USDC</span>
</span>
```

### `ui/_copy_chip.html.erb`  → drives `clipboard` Stimulus controller
Locals: `value:`, `block:`.
```erb
<button type="button" data-controller="clipboard" data-clipboard-value="<%= value %>"
  data-action="clipboard#copy"
  class="inline-flex items-center justify-between gap-2.5 bg-input border border-border-strong
         rounded-md px-3 py-[9px] text-[13px] text-foreground hover:bg-secondary transition
         <%= block ? 'w-full' : '' %>">
  <span class="truncate"><%= value %></span>
  <span data-clipboard-target="icon" class="text-subtle shrink-0"><%= render 'ui/icons/copy' %></span>
</button>
```

### `ui/_repo_tag.html.erb`
Locals: `repo:`. Repo icon (muted) + `owner/repo` (muted, truncate).
```erb
<span class="inline-flex items-center gap-2 text-muted text-[13.5px] min-w-0">
  <span class="text-subtle shrink-0"><%= render 'ui/icons/repo' %></span>
  <span class="truncate"><%= repo %></span>
</span>
```

### `ui/_tabs.html.erb`  → drives `tabs` Stimulus controller
Locals: `name:`, `options:` (array of `[value,label]`), `active:`.
```erb
<div data-controller="tabs" data-tabs-active-value="<%= active %>"
     class="inline-flex gap-0.5 p-[3px] bg-secondary border border-border rounded-[9px]">
  <% options.each do |val,label| %>
    <button type="button" data-tabs-target="tab" data-value="<%= val %>"
      data-action="tabs#select"
      class="px-[13px] py-1.5 rounded-md text-[13px] font-medium text-muted transition
             data-[active=true]:bg-[#2C2C31] data-[active=true]:text-foreground"><%= label %></button>
  <% end %>
</div>
```

### Nav — `layouts/_nav.html.erb`
Sticky, blurred translucent bar `bg-[rgba(9,9,11,.8)] backdrop-blur` + hairline bottom
border. Left: star logo + "GitReward" + links (Bounties, Dashboard, with active state).
Right: user pill (gradient avatar circle + handle) + "Sign out". Use `link_to` +
`current_page?`/controller-name checks for the active class.

---

## 3. Stimulus controllers

Place under `app/javascript/controllers/`.

### `tabs_controller.js` (Open Bounties filter)
```js
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["tab"]
  static values  = { active: String }
  connect() { this.render() }
  select(e) { this.activeValue = e.currentTarget.dataset.value }  // triggers activeValueChanged
  activeValueChanged() { this.render(); this.filter() }
  render() { this.tabTargets.forEach(t => t.dataset.active = (t.dataset.value === this.activeValue)) }
  filter() {
    // Show/hide bounty cards by data-status. Cards: data-bounty data-status="funded|open|paid"
    document.querySelectorAll("[data-bounty]").forEach(c => {
      const show = this.activeValue === "all" || c.dataset.status === this.activeValue
      c.classList.toggle("hidden", !show)
    })
  }
}
```
Bounty cards carry `data-bounty data-status="<status>"` so the controller can filter
client-side. (If you prefer server-side, make the tabs `link_to` with a `?status=` param
and let Turbo re-render the list — either is fine.)

### `clipboard_controller.js` (CopyChip)
```js
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["icon"]
  static values  = { value: String }
  copy() {
    navigator.clipboard.writeText(this.valueValue).catch(()=>{})
    const html = this.iconTarget.innerHTML
    this.iconTarget.innerHTML = CHECK_SVG       // green check (text-success)
    this.iconTarget.classList.add("text-success")
    setTimeout(() => { this.iconTarget.innerHTML = html
      this.iconTarget.classList.remove("text-success") }, 1200)
  }
}
```

### `fund_flow_controller.js` (Fund a Bounty)
Drives the live escrow summary **and** the sign→fund→done transaction stages.
```js
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["amount","fee","net","cta","ctaLabel","summaryNet"]
  static values  = { stage: { type:String, default:"idle" } }   // idle|permit|fund|done

  // recompute the 97/3 split whenever the amount input changes
  recalc() {
    const amt = parseFloat(this.amountTarget.value || 0)
    this.feeTarget.textContent       = "−" + (amt*0.03).toFixed(2) + " USDC"
    this.netTarget.textContent       = (amt*0.97).toFixed(2)        // inside _amount
  }

  submit() {                        // wired to the CTA
    if (this.stageValue !== "idle") return
    this.stageValue = "permit"
    setTimeout(() => this.stageValue = "fund", 1500)
    setTimeout(() => this.stageValue = "done", 3200)
  }

  stageValueChanged() {
    const cta = this.ctaTarget
    const map = {
      idle:   { label:"Connect wallet & fund", disabled:false, spin:false },
      permit: { label:"Sign USDC permit…",     disabled:true,  spin:true  },
      fund:   { label:"Confirming fund…",      disabled:true,  spin:true  },
      done:   { label:"Funded — view dashboard", disabled:false, spin:false, href:"/dashboard" },
    }[this.stageValue]
    cta.disabled = map.disabled
    this.ctaLabelTarget.textContent = map.label
    cta.classList.toggle("opacity-60", map.disabled)
    if (this.stageValue === "done") {
      cta.classList.add("border","border-[var(--success-line)]","text-success")
      cta.dataset.href = map.href            // Turbo-visit on next click, or submit the real tx
    }
  }
}
```
**Fee model (important):** the funder locks exactly the bounty amount; the 3% platform fee
comes **out of** it; the solver receives **97%**. (Locked 50 → fee 1.50 → solver 48.50.)
In production, replace the `setTimeout` stages with the real USDC permit signature + the
escrow `fund()` call (wallet/ethers via a JS island or your web3 layer); the controller
just reflects those promise states into `stageValue`.

### `wallet_form_controller.js` (Payout Wallet)
```js
import { Controller } from "@hotwired/stimulus"
const RE = /^0x[a-fA-F0-9]{40}$/
export default class extends Controller {
  static targets = ["input","button","hint","active","linked","note"]
  validate() {
    const v = this.inputTarget.value.trim()
    const valid = RE.test(v)
    const changed = v !== this.activeTarget.dataset.address
    this.buttonTarget.disabled = !(valid && changed)
    this.buttonTarget.classList.toggle("opacity-60", this.buttonTarget.disabled)
    this.hintTarget.textContent = (v && !valid)
      ? "That doesn't look like a valid 0x address (40 hex characters)."
      : "Paste an Ethereum address that can receive USDC on Base."
    if (this.hasNoteTarget) this.noteTarget.classList.toggle("hidden", changed)
  }
  link(e) {
    // let the form POST to Rails (server updates the payout wallet), OR optimistic:
    const v = this.inputTarget.value.trim()
    if (!RE.test(v)) { e.preventDefault(); return }
    this.activeTarget.dataset.address = v
    this.activeTarget.querySelector("[data-addr]").textContent = v
    this.linkedTarget.classList.remove("hidden")        // green "✓ Wallet linked"
    setTimeout(() => this.linkedTarget.classList.add("hidden"), 2200)
  }
}
```
Prefer letting the **form submit to Rails** (`form_with` → `PATCH /payout_wallet`) and
re-render via Turbo; use the optimistic JS only if you want the instant inline confirm.

---

## 4. Screens (controllers/views + Turbo)

Suggested routes:
```ruby
resources :bounties, only: [:index, :show]
resource  :fund_bounty, only: [:new, :create]     # GET /fund_bounty/new , POST
resource  :dashboard,  only: [:show]
resource  :payout_wallet, only: [:show, :update]
```

### Open Bounties — `bounties#index` → `bounties/index.html.erb`
- Header: left = "Open bounties" (page title) + sub; right = eyebrow "Total escrowed" +
  `ui/amount` (orange, sum of funded+open).
- `ui/tabs` (All / Open / Funded / Paid out).
- Grid `repeat(auto-fill,minmax(330px,1fr))` gap 16 of bounty cards. Each card is a
  `link_to bounty_path(b)`, carries `data-bounty data-status="<status>"`, and contains:
  RepoTag + status Badge / "Issue #N" (subtle) / title (15.5px/600, text-wrap pretty) /
  eyebrow "Reward" + orange Amount / hairline / footer "Expires {date} · {branch}" +
  "View →". Hover: border→strong, bg→card-hover.

### View Bounty — `bounties#show` → `bounties/show.html.erb`
- Single column, **max-width 580px**. Back link "← All bounties".
- RepoTag; "#N" + status Badge; title (page title 26px); muted "View issue on GitHub ↗".
- **One `ui/card`** (no header): `ui/kv` rows — Reward (orange Amount), Platform fee
  (`{fee}%`), Net to solver (green `{amount×0.97} USDC`), Target branch (code-chip),
  Expiry `{date} (Nd)`, On-chain id `#N`. Then hairline + eyebrow "Funding transaction" +
  `ui/copy_chip` (full width) with the tx hash.
- Below the card, centered small muted line: "Open a PR that closes #N and merge it into
  **{branch}** to disburse — or refund yourself after expiry." (No CTA button.)

### Fund a Bounty — `fund_bounty#new` → `fund_bounties/new.html.erb`
- Wrap the page in `data-controller="fund_flow"`. Back link "← Dashboard"; title + RepoTag.
- Two columns `1.25fr 1fr`:
  - **Left** `ui/card` "Bounty details" (+desc): Issue (`ui/select`), Target branch
    (`ui/input` + hint), 2-col Amount (number, `data-fund_flow-target="amount"
    data-action="input->fund_flow#recalc"`) + Expires in (days) with hints.
  - **Right** `ui/card` "Escrow summary" (+ "Review before you sign."): kv "Bounty locked"
    = amount; kv "Platform fee · 3%" = `−{fee}` (`data-fund_flow-target="fee"`); row
    "Solver receives" / "97% on merge" + orange Amount (`data-fund_flow-target="net"`).
    Then the CTA button (`data-fund_flow-target="cta"` + a `ctaLabel` span,
    `data-action="fund_flow#submit"`), then the hint paragraph (verbatim):
    > "You'll sign two things: a gasless USDC permit (authorizing the escrow to pull the
    > funds) and the fund transaction itself (you pay only its gas). The USDC then sits in
    > the open-source escrow until the issue's PR merges, or until you refund after expiry."

### Dashboard — `dashboard#show` → `dashboards/show.html.erb`
- Title "Dashboard" + sub. Two cards (1fr 1fr):
  - **Payout wallet** (+desc): `ui/copy_chip` of the address + `link_to "Change wallet →",
    payout_wallet_path`.
  - **Repositories** (+desc): rows of `ui/icon_box`(repo) + `owner/repo` + "Fund →"
    (`link_to new_fund_bounty_path(repo: r)`).
- **Your bounties** `ui/card`: header (title+desc) + "New bounty" primary (→ new fund).
  Table: Issue (`owner/repo` + orange `#N`), Amount, Status (Badge), Expiry, "View →".

### Payout Wallet — `payout_wallet#show` → `payout_wallets/show.html.erb`
- Wrap in `data-controller="wallet_form"`. Single column, max-width 580. Back "← Dashboard".
- Title "Payout wallet" + description (verbatim): "The address bounties you earn are paid
  to. It's used at merge time — whatever is active when a PR merges is where the USDC goes.
  Double-check it: a wrong address is irreversible, and it's your assertion, not ours."
- **Current active wallet** card (secondary surface): `ui/icon_box`(orange wallet) +
  eyebrow "Current active wallet" + the address (`data-wallet_form-target="active"
  data-address="<addr>"`, with `<span data-addr>` for the text) + green "● Active" badge.
- **Replace** card via `form_with url: payout_wallet_path, method: :patch`: label
  "Replace payout wallet" + `ui/input` (`data-wallet_form-target="input"
  data-action="input->wallet_form#validate"`), `data-wallet_form-target="hint"` line,
  then "Link wallet" submit button (`data-wallet_form-target="button"`,
  `data-action="wallet_form#link"`) + a hidden green "✓ Wallet linked"
  (`data-wallet_form-target="linked"`) and the "already your active wallet" note
  (`data-wallet_form-target="note"`).
- Footnote: "USDC on Base only (v1). Make sure this wallet can receive USDC on Base."

---

## 5. Motion, responsive, a11y
- Screen entrance: `translateY(12px)→0`, .38s custom ease, **transform-only** (content
  stays visible without JS); gate on `@media (prefers-reduced-motion: no-preference)`.
- Buttons/cards transition 0.15s. Spinner 0.7s linear (for `permit`/`fund` stages).
- Responsive < 800px: single column, hide nav links, tighter padding, smaller page title.
- Keep the visible 2px orange focus ring on all interactive elements.

## 6. Data / models (replace the mocks)
- `reference/data.jsx` is **mock data only** — do not port. Wire real models:
  bounties (repo, issue, title, amount, fee, branch, expiry, status, tx hash, on-chain id),
  the user's payout wallet, and connected repositories. Statuses: `funded | open | paid | merged`.
- The fund flow's stages should reflect the real USDC permit signature + escrow `fund()`
  call; the wallet form should PATCH the payout address to Rails.

## 7. Files (in `reference/`)
- `styles.css` — **source of truth** for every exact value (colors, type, radii, the
  select chevron SVG, focus ring, animations). Port these into Tailwind/`application.css`.
- `components.jsx` — the React originals of each partial above, incl. the inline icon SVG
  paths (object `I`) — copy the `<path>` data into `app/views/ui/icons/*` partials.
- `screens.jsx` — the React originals of each screen (logic reference for the Stimulus controllers).
- `app.jsx` — routing reference.
- `data.jsx` — mock data (do not port).
- `GitReward.html` — open in a browser to see/click the live prototype.
