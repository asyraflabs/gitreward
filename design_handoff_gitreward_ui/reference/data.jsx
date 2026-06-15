/* GitReward demo data */
const BOUNTIES = [
  { id: 1, onchain: 1, repo: "jimmyasyraf/jimmyasyraf.github.io", issue: 17, title: "Hydration mismatch on dark-mode toggle", amount: "5.0", fee: "3.0", branch: "master", expires: "2026-06-24", expiresIn: 10, status: "funded", lang: "TypeScript", tx: "0xb64ff83b72abf15fdc0334358e7b72e840192bcdb03656d8993d949b60f42ff2", funder: "0x14dC79964da2C08b23698B3D3cc7Ca32193d9955" },
  { id: 2, onchain: 2, repo: "jimmyasyraf/robot_navigation", issue: 42, title: "A* planner stalls on dynamic obstacles", amount: "120.0", fee: "3.0", branch: "main", expires: "2026-07-09", expiresIn: 25, status: "open", lang: "Python" },
  { id: 3, onchain: 3, repo: "jimmyasyraf/scrape", issue: 8, title: "Rate-limit backoff drops the last page of results", amount: "45.0", fee: "3.0", branch: "main", expires: "2026-06-30", expiresIn: 16, status: "open", lang: "Go" },
  { id: 4, onchain: 4, repo: "jimmyasyraf/trustana-assignment", issue: 3, title: "Add optimistic UI for bulk attribute edits", amount: "80.0", fee: "3.0", branch: "develop", expires: "2026-07-15", expiresIn: 31, status: "open", lang: "TypeScript" },
  { id: 5, onchain: 5, repo: "jimmyasyraf/robot_navigation", issue: 51, title: "Port costmap inflation to SIMD", amount: "260.0", fee: "3.0", branch: "main", expires: "—", expiresIn: 0, status: "paid", lang: "Rust" },
];

const REPOS = ["jimmyasyraf/scrape", "jimmyasyraf/robot_navigation", "jimmyasyraf/jimmyasyraf.github.io", "jimmyasyraf/trustana-assignment"];
const LANG_COLOR = { TypeScript: "#5AB0FF", Python: "#FFD24A", Go: "#4ED4E0", Rust: "#FF8A5B", JavaScript: "#F7DF1E" };
const MY_BOUNTIES = [
  { repo: "jimmyasyraf/jimmyasyraf.github.io", issue: 15, amount: "30.0", status: "funded", expires: "2026-06-24" },
  { repo: "jimmyasyraf/robot_navigation", issue: 51, amount: "260.0", status: "paid", expires: "—" },
];
const PAYOUT_WALLET = "0x14dC79964da2C08b23698B3D3cc7Ca32193d9955";

Object.assign(window, { BOUNTIES, REPOS, LANG_COLOR, MY_BOUNTIES, PAYOUT_WALLET });
