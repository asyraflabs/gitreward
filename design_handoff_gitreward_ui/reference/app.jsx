/* global React, ReactDOM, Nav, BountiesScreen, BountyScreen, FundScreen, DashboardScreen, WalletScreen, MY_BOUNTIES */
const { useState, useEffect } = React;

function App() {
  const [route, setRoute] = useState("bounties");
  const [param, setParam] = useState(null);
  const [fundRepo, setFundRepo] = useState(null);
  const [myBounties, setMyBounties] = useState(MY_BOUNTIES);

  function go(r, p = null, repo = null) {
    setRoute(r); setParam(p); if (repo !== null) setFundRepo(repo);
    window.scrollTo({ top: 0, behavior: "instant" });
  }

  function onFund({ repo, issue, amount }) {
    setMyBounties((b) => [{ repo, issue: parseInt(issue, 10), amount: parseFloat(amount).toFixed(1), status: "funded", expires: "2026-09-12" }, ...b]);
  }

  const screen = (() => {
    switch (route) {
      case "bounty": return <BountyScreen go={go} id={param} />;
      case "fund": return <FundScreen go={go} onFund={onFund} repo={fundRepo} />;
      case "dashboard": return <DashboardScreen go={go} myBounties={myBounties} />;
      case "wallet": return <WalletScreen go={go} />;
      default: return <BountiesScreen go={go} />;
    }
  })();

  const navRoute = route === "bounty" ? "bounties" : (route === "fund" || route === "wallet") ? "dashboard" : route;

  return (
    <div className="shell">
      <Nav route={navRoute} go={go} />
      <div key={route + param}>{screen}</div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
