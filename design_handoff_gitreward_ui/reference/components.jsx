/* global React */
const { useState } = React;

/* ---- icons (simple line/solid; currentColor) ---- */
const I = {
  star: (s = 26) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="#F97316">
      <path d="M12 2.2c.5 0 .9.5 1.5 1.9.4.9.6 1.4 1 1.7.4.3 1 .4 1.9.5 1.6.2 2.2.3 2.4.8.2.5-.2 1-1.3 2.1-.7.7-1 1-1.2 1.5-.1.5 0 1 .2 2 .4 1.6.5 2.2.1 2.5-.4.3-1 0-2.4-.7-.9-.5-1.4-.7-1.9-.7s-1 .2-1.9.7c-1.4.7-2 1-2.4.7-.4-.3-.3-.9.1-2.5.2-1 .3-1.5.2-2-.2-.5-.5-.8-1.2-1.5C6.3 9.9 5.9 9.4 6.1 8.9c.2-.5.8-.6 2.4-.8.9-.1 1.5-.2 1.9-.5.4-.3.6-.8 1-1.7.6-1.4 1-1.9 1.5-1.9Z" />
    </svg>
  ),
  pin: (s = 20) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M9 4h6M12 4v6M8 10h8l-1.5 4h-5L8 10ZM12 14v6" /></svg>
  ),
  branch: (s = 20) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><circle cx="6" cy="5" r="2.4" /><circle cx="6" cy="19" r="2.4" /><circle cx="18" cy="7" r="2.4" /><path d="M6 7.4v9.2M18 9.4c0 4-3 5-6 5" /></svg>
  ),
  dollar: (s = 20) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M12 3v18M16 7.5c0-1.4-1.8-2.5-4-2.5s-4 1.1-4 2.5 1.8 2.3 4 2.5 4 1.1 4 2.5-1.8 2.5-4 2.5-4-1.1-4-2.5" /></svg>
  ),
  repo: (s = 17) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M5 4.5A1.5 1.5 0 0 1 6.5 3H19v15H6.5A1.5 1.5 0 0 0 5 19.5z" /><path d="M5 19.5A1.5 1.5 0 0 1 6.5 18H19v3H6.5A1.5 1.5 0 0 1 5 19.5z" /></svg>
  ),
  arrow: (s = 16) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12h14M13 6l6 6-6 6" /></svg>
  ),
  ext: (s = 14) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 5h10v10M19 5 8 16M5 9v10h10" /></svg>
  ),
  copy: (s = 15) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="9" width="11" height="11" rx="2" /><path d="M5 15V5a2 2 0 0 1 2-2h8" /></svg>
  ),
  check: (s = 15) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="m5 12 4.5 4.5L19 7" /></svg>
  ),
  lock: (s = 16) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><rect x="5" y="11" width="14" height="9" rx="2" /><path d="M8 11V8a4 4 0 0 1 8 0v3" /></svg>
  ),
  wallet: (s = 17) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="6" width="18" height="13" rx="2.5" /><path d="M3 9h13a2 2 0 0 1 2 2v2a2 2 0 0 1-2 2H3" /><circle cx="16.5" cy="12.5" r="1" fill="currentColor" stroke="none" /></svg>
  ),
};

function Logo({ onClick }) {
  return <div className="brand" onClick={onClick}>{I.star(24)}<span className="brand-name">GitReward</span></div>;
}

function Button({ children, variant = "primary", size, block, className = "", ...rest }) {
  const cls = ["btn", `btn-${variant}`, size === "sm" ? "btn-sm" : size === "lg" ? "btn-lg" : "", block ? "btn-block" : "", className].join(" ");
  return <button className={cls} {...rest}>{children}</button>;
}

function Badge({ status }) {
  const map = { funded: "badge-funded", open: "badge-open", merged: "badge-merged", paid: "badge-paid" };
  const label = status === "paid" ? "Paid out" : status.charAt(0).toUpperCase() + status.slice(1);
  return <span className={`badge ${map[status] || "badge-open"}`}>{label}</span>;
}

function IconBox({ children, orange }) {
  return <span className={`icon-box ${orange ? "icon-box-orange" : ""}`}>{children}</span>;
}

function Tabs({ value, onChange, options }) {
  return (
    <div className="tabs">
      {options.map(([k, label]) => (
        <button key={k} className={`tab ${value === k ? "active" : ""}`} onClick={() => onChange(k)}>{label}</button>
      ))}
    </div>
  );
}

function Nav({ route, go }) {
  const links = [["bounties", "Bounties"], ["dashboard", "Dashboard"]];
  return (
    <nav className="nav">
      <div className="wrap nav-inner">
        <Logo onClick={() => go("bounties")} />
        <div className="nav-links">
          {links.map(([k, label]) => (
            <button key={k} className={`nav-link ${route === k ? "active" : ""}`} onClick={() => go(k)}>{label}</button>
          ))}
        </div>
        <div className="nav-spacer" />
        <div className="user" onClick={() => go("dashboard")}>
          <span className="avatar">j</span>
          <span style={{ fontWeight: 500, fontSize: 13.5 }}>jimmyasyraf</span>
        </div>
        <span className="signout" style={{ marginLeft: 8 }}>Sign out</span>
      </div>
    </nav>
  );
}

function Amount({ value, size = 28, color = "var(--tx)" }) {
  return <span className="amount" style={{ fontSize: size, color }}>{value}<span className="unit">USDC</span></span>;
}

function RepoTag({ repo }) {
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: 8, color: "var(--tx-2)", fontSize: 13.5, minWidth: 0 }}>
      <span style={{ color: "var(--tx-3)", flexShrink: 0, display: "inline-flex" }}>{I.repo(16)}</span>
      <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{repo}</span>
    </span>
  );
}

function CopyChip({ value, block }) {
  const [done, setDone] = useState(false);
  function copy() { try { navigator.clipboard.writeText(value); } catch (e) {} setDone(true); setTimeout(() => setDone(false), 1200); }
  return (
    <button className="copy" style={{ width: block ? "100%" : "auto" }} onClick={copy}>
      <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{value}</span>
      <span style={{ color: done ? "var(--green)" : "var(--tx-3)", flexShrink: 0, display: "inline-flex" }}>{done ? I.check(15) : I.copy(15)}</span>
    </button>
  );
}

Object.assign(window, { I, Logo, Button, Badge, Nav, Amount, RepoTag, CopyChip, IconBox, Tabs });
