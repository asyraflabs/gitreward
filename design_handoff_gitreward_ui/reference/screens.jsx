/* global React, I, Button, Badge, Amount, RepoTag, CopyChip, IconBox, Tabs,
   BOUNTIES, REPOS, MY_BOUNTIES, PAYOUT_WALLET */
const { useState: useS } = React;

/* ============================================================
   1. OPEN BOUNTIES
============================================================ */
function BountiesScreen({ go }) {
  const [filter, setFilter] = useS("all");
  const open = BOUNTIES.filter((b) => b.status === "funded" || b.status === "open");
  const escrowed = open.reduce((s, b) => s + parseFloat(b.amount), 0).toFixed(0);
  const shown = filter === "all" ? BOUNTIES : BOUNTIES.filter((b) => b.status === filter);

  return (
    <div className="wrap screen" style={{ padding: "40px 28px 72px" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 24, flexWrap: "wrap", marginBottom: 24 }}>
        <div style={{ maxWidth: 560 }}>
          <h1 className="h-page">Open bounties</h1>
          <p className="sub">Funded issues across every repo using GitReward. Solve one, link a wallet, get paid on merge.</p>
        </div>
        <div style={{ textAlign: "right" }}>
          <div className="eyebrow" style={{ marginBottom: 8 }}>Total escrowed</div>
          <Amount value={escrowed} size={28} color="var(--orange)" />
        </div>
      </div>

      <div style={{ marginBottom: 22 }}>
        <Tabs value={filter} onChange={setFilter} options={[["all", "All"], ["open", "Open"], ["funded", "Funded"], ["paid", "Paid out"]]} />
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(330px, 1fr))", gap: 16 }}>
        {shown.map((b) => (
          <div key={b.id} className="card card-pad bounty screen" onClick={() => go("bounty", b.id)}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 14 }}>
              <RepoTag repo={b.repo} />
              <Badge status={b.status} />
            </div>
            <div style={{ color: "var(--tx-3)", fontSize: 12.5, marginBottom: 5 }}>Issue #{b.issue}</div>
            <h3 style={{ margin: "0 0 18px", fontSize: 15.5, fontWeight: 600, lineHeight: 1.4, letterSpacing: "-0.01em", textWrap: "pretty" }}>{b.title}</h3>
            <div className="eyebrow" style={{ marginBottom: 6 }}>Reward</div>
            <Amount value={b.amount} size={24} color="var(--orange)" />
            <hr className="divider" style={{ margin: "16px 0 13px" }} />
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <span style={{ color: "var(--tx-3)", fontSize: 12.5 }}>Expires {b.expires} · {b.branch}</span>
              <span className="link" style={{ fontSize: 13 }}>View {I.arrow(13)}</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

/* ============================================================
   2. VIEW BOUNTY
============================================================ */
function BountyScreen({ go, id }) {
  const b = BOUNTIES.find((x) => x.id === id) || BOUNTIES[0];
  const net = (parseFloat(b.amount) * (1 - parseFloat(b.fee) / 100)).toFixed(2);

  return (
    <div className="wrap screen" style={{ padding: "30px 28px 72px", maxWidth: 580 }}>
      <button className="link link-muted" style={{ marginBottom: 20 }} onClick={() => go("bounties")}>
        <span style={{ transform: "rotate(180deg)", display: "inline-flex" }}>{I.arrow(14)}</span> All bounties
      </button>

      <div style={{ marginBottom: 10 }}><RepoTag repo={b.repo} /></div>
      <div style={{ display: "flex", alignItems: "center", gap: 11, marginBottom: 11 }}>
        <span style={{ color: "var(--tx-2)", fontWeight: 600, fontSize: 15 }}>#{b.issue}</span>
        <Badge status={b.status} />
      </div>
      <h1 className="h-page" style={{ fontSize: 26 }}>{b.title}</h1>
      <div style={{ marginTop: 13 }}>
        <a className="link link-muted" style={{ fontSize: 14 }}>View issue on GitHub {I.ext(14)}</a>
      </div>

      <div className="card card-pad" style={{ marginTop: 24 }}>
        <div>
          {[
            ["Reward", <Amount value={b.amount} size={16} color="var(--orange)" />],
            ["Platform fee", <span>{parseFloat(b.fee)}%</span>],
            ["Net to solver", <span style={{ color: "var(--green)" }}>{net} USDC</span>],
            ["Target branch", <span className="code-chip">{b.branch}</span>],
            ["Expiry", <span>{b.expires}{b.expiresIn ? ` (${b.expiresIn}d)` : ""}</span>],
            ["On-chain id", <span>#{b.onchain}</span>],
          ].map(([k, v], i) => (
            <div className="kv" key={i}><span className="kv-k">{k}</span><span className="kv-v">{v}</span></div>
          ))}
        </div>
        <hr className="divider" style={{ margin: "6px 0 16px" }} />
        <div className="eyebrow" style={{ marginBottom: 8 }}>Funding transaction</div>
        <CopyChip value={b.tx || "0x…pending"} block />
      </div>

      <p className="sub" style={{ textAlign: "center", fontSize: 13, marginTop: 16 }}>
        Open a PR that closes #{b.issue} and merge it into <span style={{ color: "var(--tx-2)", fontWeight: 500 }}>{b.branch}</span> to disburse — or refund yourself after expiry.
      </p>
    </div>
  );
}

/* ============================================================
   3. FUND A BOUNTY
============================================================ */
function FundScreen({ go, onFund, repo }) {
  const [issue, setIssue] = useS("17");
  const [branch, setBranch] = useS("master");
  const [amount, setAmount] = useS("50");
  const [days, setDays] = useS("90");
  const [stage, setStage] = useS("idle"); // idle | permit | fund | done

  const amt = parseFloat(amount || 0);
  const fee = (amt * 0.03).toFixed(2);
  const net = (amt * 0.97).toFixed(2);
  const activeRepo = repo || "jimmyasyraf/jimmyasyraf.github.io";

  function submit() {
    setStage("permit");
    setTimeout(() => setStage("fund"), 1500);
    setTimeout(() => { setStage("done"); onFund({ repo: activeRepo, issue, amount, branch }); }, 3200);
  }

  return (
    <div className="wrap screen" style={{ padding: "30px 28px 72px", maxWidth: 860 }}>
      <button className="link link-muted" style={{ marginBottom: 20 }} onClick={() => go("dashboard")}>
        <span style={{ transform: "rotate(180deg)", display: "inline-flex" }}>{I.arrow(14)}</span> Dashboard
      </button>

      <h1 className="h-page">Fund a bounty</h1>
      <p className="sub" style={{ display: "flex", alignItems: "center", gap: 8 }}><RepoTag repo={activeRepo} /></p>

      <div className="grid-2" style={{ marginTop: 24, gridTemplateColumns: "1.25fr 1fr", alignItems: "start" }}>
        <div className="card card-pad" style={{ padding: 24 }}>
          <div className="card-head">
            <h3 className="h-sec">Bounty details</h3>
            <p className="card-desc">Define the issue and reward. Funds release automatically on merge.</p>
          </div>
          <div className="field">
            <label className="label">Issue</label>
            <select className="select" value={issue} onChange={(e) => setIssue(e.target.value)}>
              <option value="17">#17 — Hydration mismatch on dark-mode toggle</option>
              <option value="19">#19 — Flaky e2e on CI</option>
              <option value="23">#23 — Memory leak in worker pool</option>
            </select>
          </div>
          <div className="field">
            <label className="label">Target branch</label>
            <input className="input" value={branch} onChange={(e) => setBranch(e.target.value)} />
            <div className="hint">The PR must merge into this branch to disburse the escrow.</div>
          </div>
          <div className="grid-2" style={{ gap: 16 }}>
            <div className="field" style={{ marginBottom: 0 }}>
              <label className="label">Amount (USDC)</label>
              <input className="input" type="number" value={amount} onChange={(e) => setAmount(e.target.value)} />
              <div className="hint">Minimum 5 USDC.</div>
            </div>
            <div className="field" style={{ marginBottom: 0 }}>
              <label className="label">Expires in (days)</label>
              <input className="input" type="number" value={days} onChange={(e) => setDays(e.target.value)} />
              <div className="hint">Minimum 7 days.</div>
            </div>
          </div>
        </div>

        <div className="card card-pad">
          <div className="card-head">
            <h3 className="h-sec">Escrow summary</h3>
            <p className="card-desc">Review before you sign.</p>
          </div>
          <div className="kv" style={{ padding: "12px 0" }}><span className="kv-k">Bounty locked</span><span className="kv-v">{amt.toFixed(2)} USDC</span></div>
          <div className="kv" style={{ padding: "12px 0" }}><span className="kv-k">Platform fee · 3%</span><span className="kv-v">−{fee} USDC</span></div>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "15px 0 18px" }}>
            <div>
              <div style={{ fontWeight: 500, fontSize: 14 }}>Solver receives</div>
              <div className="hint" style={{ marginTop: 2 }}>97% on merge</div>
            </div>
            <Amount value={net} size={20} color="var(--orange)" />
          </div>

          {stage === "idle" && <Button block onClick={submit}>{I.wallet(16)} Connect wallet &amp; fund</Button>}
          {(stage === "permit" || stage === "fund") && <Button block disabled><span className="spin" /> {stage === "permit" ? "Sign USDC permit…" : "Confirming fund…"}</Button>}
          {stage === "done" && <Button block variant="ghost" onClick={() => go("dashboard")} style={{ color: "var(--green)", borderColor: "var(--green-line)" }}>{I.check(16)} Funded — view dashboard</Button>}

          <div className="hint" style={{ marginTop: 16 }}>You'll sign two things: a gasless USDC permit (authorizing the escrow to pull the funds) and the fund transaction itself (you pay only its gas). The USDC then sits in the open-source escrow until the issue's PR merges, or until you refund after expiry.</div>
        </div>
      </div>
    </div>
  );
}

function Step({ n, label, active, done }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 10, opacity: active || done ? 1 : 0.5 }}>
      <span style={{ width: 22, height: 22, borderRadius: "50%", display: "grid", placeItems: "center", flexShrink: 0, fontSize: 11, fontWeight: 600,
        background: done ? "var(--green-soft)" : active ? "var(--orange-soft)" : "var(--card-2)",
        border: `1px solid ${done ? "var(--green-line)" : active ? "var(--orange-line)" : "var(--stroke)"}`,
        color: done ? "var(--green)" : active ? "var(--orange)" : "var(--tx-3)" }}>{done ? I.check(13) : active ? <span className="spin" style={{ width: 11, height: 11 }} /> : n}</span>
      <span style={{ fontSize: 12.5, fontWeight: 500, whiteSpace: "nowrap", color: done || active ? "var(--tx)" : "var(--tx-2)" }}>{label}</span>
    </div>
  );
}

/* ============================================================
   4. DASHBOARD
============================================================ */
function DashboardScreen({ go, myBounties }) {
  const list = myBounties || MY_BOUNTIES;
  return (
    <div className="wrap screen" style={{ padding: "40px 28px 72px" }}>
      <h1 className="h-page">Dashboard</h1>
      <p className="sub" style={{ marginBottom: 26 }}>Manage your payout wallet, connected repos, and bounties you've funded.</p>

      <div className="grid-2" style={{ marginBottom: 16 }}>
        <div className="card card-pad">
          <div className="card-head">
            <h2 className="h-sec h-sec-nowrap">Payout wallet</h2>
            <p className="card-desc">Bounties you earn are paid to this address.</p>
          </div>
          <CopyChip value={PAYOUT_WALLET} block />
          <a className="link" style={{ fontSize: 13.5, marginTop: 14 }} onClick={() => go("wallet")}>Change wallet {I.arrow(13)}</a>
        </div>

        <div className="card card-pad">
          <div className="card-head">
            <h2 className="h-sec h-sec-nowrap">Repositories</h2>
            <p className="card-desc">Repos connected to GitReward.</p>
          </div>
          <div style={{ marginTop: -2 }}>
            {REPOS.map((r) => (
              <div className="repo-row" key={r}>
                <div style={{ display: "flex", alignItems: "center", gap: 12, minWidth: 0 }}>
                  <IconBox>{I.repo(17)}</IconBox>
                  <span style={{ fontSize: 13.5, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{r}</span>
                </div>
                <a className="link" style={{ fontSize: 13.5 }} onClick={() => go("fund", null, r)}>Fund {I.arrow(13)}</a>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="card card-pad">
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 16, gap: 16 }}>
          <div>
            <h2 className="h-sec h-sec-nowrap">Your bounties</h2>
            <p className="card-desc">Issues you're currently funding.</p>
          </div>
          <Button size="sm" onClick={() => go("fund")} style={{ flexShrink: 0 }}>{I.dollar(15)} New bounty</Button>
        </div>
        <table className="tbl">
          <thead><tr><th>Issue</th><th>Amount</th><th>Status</th><th>Expiry</th><th></th></tr></thead>
          <tbody>
            {list.map((b, i) => {
              const t = BOUNTIES.find((x) => x.repo === b.repo && x.issue === b.issue);
              return (
                <tr key={i}>
                  <td><span style={{ fontSize: 13.5 }}>{b.repo}<span className="accent" style={{ marginLeft: 1 }}> #{b.issue}</span></span></td>
                  <td><span style={{ fontWeight: 500 }}>{b.amount} <span style={{ color: "var(--tx-3)" }}>USDC</span></span></td>
                  <td><Badge status={b.status} /></td>
                  <td><span style={{ color: "var(--tx-2)", fontSize: 13.5 }}>{b.expires}</span></td>
                  <td style={{ textAlign: "right" }}><a className="link" style={{ fontSize: 13 }} onClick={() => t ? go("bounty", t.id) : go("bounties")}>View {I.arrow(13)}</a></td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

Object.assign(window, { BountiesScreen, BountyScreen, FundScreen, DashboardScreen, WalletScreen });

/* ============================================================
   5. PAYOUT WALLET
============================================================ */
function WalletScreen({ go, onLink }) {
  const [active, setActive] = useS(PAYOUT_WALLET);
  const [draft, setDraft] = useS(PAYOUT_WALLET);
  const [linked, setLinked] = useS(false);

  const valid = /^0x[a-fA-F0-9]{40}$/.test(draft.trim());
  const changed = draft.trim() !== active;

  function link() {
    if (!valid || !changed) return;
    setActive(draft.trim());
    setLinked(true);
    setTimeout(() => setLinked(false), 2200);
  }

  return (
    <div className="wrap screen" style={{ padding: "30px 28px 72px", maxWidth: 580 }}>
      <button className="link link-muted" style={{ marginBottom: 20 }} onClick={() => go("dashboard")}>
        <span style={{ transform: "rotate(180deg)", display: "inline-flex" }}>{I.arrow(14)}</span> Dashboard
      </button>

      <h1 className="h-page">Payout wallet</h1>
      <p className="sub" style={{ maxWidth: 540 }}>
        The address bounties you earn are paid to. It's used at merge time — whatever is active when a PR merges is where the USDC goes. Double-check it: a wrong address is irreversible, and it's your assertion, not ours.
      </p>

      {/* current active */}
      <div className="card card-pad" style={{ marginTop: 24, padding: 18, background: "var(--card-2)" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
          <IconBox orange>{I.wallet(18)}</IconBox>
          <div style={{ minWidth: 0, flex: 1 }}>
            <div className="eyebrow" style={{ marginBottom: 5 }}>Current active wallet</div>
            <div style={{ fontSize: 14, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{active}</div>
          </div>
          <span className="badge badge-paid" style={{ gap: 6 }}><span style={{ width: 6, height: 6, borderRadius: "50%", background: "var(--green)" }} />Active</span>
        </div>
      </div>

      {/* replace */}
      <div className="card card-pad" style={{ marginTop: 16 }}>
        <div className="field" style={{ marginBottom: 0 }}>
          <label className="label">Replace payout wallet</label>
          <input className="input" value={draft} onChange={(e) => { setDraft(e.target.value); setLinked(false); }} placeholder="0x…" spellCheck={false} style={{ borderColor: draft && !valid ? "var(--orange-line)" : undefined }} />
          <div className="hint">{draft && !valid ? "That doesn't look like a valid 0x address (40 hex characters)." : "Paste an Ethereum address that can receive USDC on Base."}</div>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 14, marginTop: 18 }}>
          <Button onClick={link} disabled={!valid || !changed}>{I.wallet(16)} Link wallet</Button>
          {linked && <span style={{ display: "inline-flex", alignItems: "center", gap: 6, color: "var(--green)", fontSize: 13.5, fontWeight: 500 }}>{I.check(15)} Wallet linked</span>}
          {!linked && !changed && <span style={{ color: "var(--tx-3)", fontSize: 13 }}>This is already your active wallet.</span>}
        </div>
      </div>

      <p className="hint" style={{ marginTop: 14 }}>USDC on Base only (v1). Make sure this wallet can receive USDC on Base.</p>
    </div>
  );
}
