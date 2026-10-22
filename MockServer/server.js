/* Route Builder — staging mock API
   Node 18+, no dependencies.  node server.js [port]
   Deterministic: same request sequence produces the same failures. */

const http = require("http");
const PORT = Number(process.argv[2] || 4000);

/* ---------------------------------------------------------------- data */

const RAW = [
  ["Bluebell Event Hall", "42 Harbor St, Westfield", "020 7946 0220"],
  ["North Cafe", "12 North Rd, Northbridge", "+44-20-7946-0188"],
  ["Sova Studio Gallery", "42 King St, Northbridge", "02079460477"],
  ["Daily Farm Deli", "71 Queen St, Northbridge", "020-7946-0909"],
  ["Green Bay Hostel", "120 Bay St, Northbridge", "+44 20 7946 0633"],
  ["Rosewood Interiors", "94 Mill Lane, Northbridge", "020-7946-0101"],
  ["Zita Deli", "190 High St, Northbridge", "020-7946-0778"],
  ["Isaac's Hardware", "3 Market St, Northbridge", "07700900123"],
  ["Tal Optic", "189 High St, Northbridge", "020-7946-0202"],
  ["Eurocar Garage", "22 Forge Rd, Northbridge", "020-7946-0556"],
  ["Quicksilver Couriers", "28 Station Rd, Northbridge", "020-7946-0414"],
  ["Fleur Boutique", "60 Park Ave, Northbridge", "020-7946-0899"],
  ["Oren Dental Clinic", "14 Church St, Northbridge", "020-7946-0303"],
  ["Net Sport", "33 George St, Northbridge", "020-7946-0141"],
  ["Pilates 9 Studio", "31 Shore Rd, Northbridge", "020-7946-0232"],
  ["Eden Organic Market", "44 Garden Rd, Northbridge", "020-7946-0999"],
  ["Roma Pizza — Central Bus Station branch, 6th floor, next to the north elevator", "108 Market St, Northbridge", "020-7946-0100"],
  ["Checkpoint Logistics", "5 Dock Rd, Northbridge", "020-7946-0444"],
  ["Almond Patisserie", "77 Bridge St, Northbridge", "020-7946-0171"],
  ["24/7 Pharmacy", "12 Trade St, Eastvale", "020-7946-0808"],
  ["Ambassador Cars", "34 Ring Rd, Northbridge", "020-7946-0737"],
  ["Taylor & Sons Distribution", "18 Fiber Rd, Southgate", "020-7946-0606"],
  ["Amber Wine Bar", "24 Canal St, Northbridge", "020-7946-0282"],
  ["Zen Nails ✨", "30 Queen St, Northbridge", "020-7946-0515"]
];

const STOPS = RAW.map((r, i) => {
  const s = {
    id: "stp_" + String(1000 + i),
    name: r[0],
    address: r[1],
    phone: r[2],
    zone: ["center", "south", "north", "east"][i % 4]
  };
  /* packages_max: number | numeric string | null */
  if (i % 5 === 0) s.packages_max = null;
  else if (i % 3 === 0) s.packages_max = String(4 + (i % 7));
  else s.packages_max = 4 + (i % 7);

  /* last_delivery_at in three different formats */
  const t = Date.now() - (i + 1) * 3600e3;
  if (i % 3 === 0) s.last_delivery_at = new Date(t).toISOString();
  else if (i % 3 === 1) s.last_delivery_at = new Date(t).toISOString().replace("Z", "");
  else s.last_delivery_at = Math.floor(t / 1000);

  if (i % 6 === 0) s.notes = null;
  return s;
});

/* ------------------------------------------------------------- plumbing */

let seq = 0;                 // global request counter -> deterministic chaos
const rl = new Map();        // rate-limit buckets
const routes = new Map();
const notified = new Map();  // idempotency ledger

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function send(res, code, body, headers) {
  const b = body === undefined ? "" : JSON.stringify(body);
  res.writeHead(code, Object.assign({
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "*",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS"
  }, headers || {}));
  res.end(b);
}

function readBody(req) {
  return new Promise((resolve) => {
    let d = "";
    req.on("data", (c) => (d += c));
    req.on("end", () => {
      try { resolve(JSON.parse(d || "{}")); } catch (e) { resolve({ __bad: true }); }
    });
  });
}

function limited(req) {
  const ip = req.socket.remoteAddress || "x";
  const now = Date.now();
  const b = rl.get(ip) || { n: 0, t: now };
  if (now - b.t > 60000) { b.n = 0; b.t = now; }
  b.n++;
  rl.set(ip, b);
  return b.n > 30 ? Math.ceil((b.t + 60000 - now) / 1000) : 0;
}

/* ------------------------------------------------------------- handlers */

async function listStops(u, res) {
  const page = Math.max(1, Number(u.searchParams.get("page") || 1));
  const size = Math.min(50, Math.max(1, Number(u.searchParams.get("page_size") || 10)));
  const q = (u.searchParams.get("q") || "").trim();
  const zone = u.searchParams.get("zone");

  /* every 9th call to this endpoint fails hard */
  if (seq % 9 === 0) return send(res, 500, { error: "internal_error", request_id: "req_" + seq });
  /* every 14th is a slow 503 that asks to be retried */
  if (seq % 14 === 0) {
    await sleep(1200);
    return send(res, 503, { error: "upstream_unavailable" }, { "Retry-After": "2" });
  }

  let rows = STOPS.slice();
  if (zone) rows = rows.filter((s) => s.zone === zone);
  if (q) {
    const dq = q.replace(/\D/g, "");
    rows = rows.filter((s) => s.name.includes(q) || s.address.includes(q) ||
      (dq.length >= 3 && s.phone.replace(/\D/g, "").includes(dq)));
  }

  const start = (page - 1) * size;
  let items = rows.slice(start, start + size);

  /* page 2 repeats the tail of page 1 */
  if (page === 2 && rows.length > size) items = [rows[size - 1]].concat(items.slice(0, size - 1));

  const lastPage = start + size >= rows.length;

  /* no results -> null on search, [] on browse */
  if (items.length === 0 && q) items = null;

  return send(res, 200, {
    items: items,
    page: page,
    page_size: size,
    total: rows.length + 1,                    // includes a soft-deleted record
    total_pages: Math.floor(rows.length / size),
    has_more: lastPage ? rows.length % size !== 0 : true
  });
}

async function getStop(id, res) {
  const s = STOPS.find((x) => x.id === id);
  if (!s) return send(res, 404, { error: "not_found" });
  return send(res, 200, s);
}

async function getPhotos(id, res) {
  const s = STOPS.find((x) => x.id === id);
  if (!s) return send(res, 404, { error: "not_found" });
  await sleep(3500 + (seq % 5) * 250);          // deliberately slow
  const n = Number(id.slice(-4)) % 4;           // 0..3 photos, sometimes none
  const items = [];
  for (let k = 0; k < n; k++) {
    items.push({
      id: id + "_p" + k,
      url: k === 1 ? null : "https://picsum.photos/seed/" + id + k + "/400/250",
      tag: ["entrance", "parking", "back_door"][k % 3],
      width: 400, height: 250
    });
  }
  return send(res, 200, { items: items });
}

async function createRoute(body, res) {
  if (body.__bad) return send(res, 400, { error: "malformed_json" });
  const stops = Array.isArray(body.stops) ? body.stops : null;
  if (!stops || !stops.length) return send(res, 422, { error: "validation_failed", fields: { stops: "required" } });

  const saved = stops.map((s) => ({
    stop_id: s.stop_id,
    packages: Number(s.packages) || 1,
    instructions: String(s.instructions || "").slice(0, 200)   // silent truncation
  }));
  const id = "rt_" + (2000 + routes.size);
  routes.set(id, { id: id, stops: saved, created_at: new Date().toISOString() });
  return send(res, 201, { id: id, stops: saved, status: "draft" });
}

async function notify(routeId, body, headers, res) {
  const r = routes.get(routeId);
  if (!r) return send(res, 404, { error: "route_not_found" });
  const stopId = body.stop_id;
  if (!stopId) return send(res, 422, { error: "validation_failed", fields: { stop_id: "required" } });

  const key = headers["idempotency-key"];
  const ledgerKey = routeId + "|" + stopId;
  if (key && notified.has(ledgerKey + "|" + key)) {
    return send(res, 200, notified.get(ledgerKey + "|" + key));
  }

  await sleep(600 + (seq % 4) * 300);

  const prior = notified.get(ledgerKey) || 0;
  /* first attempt fails for every third stop, retry succeeds */
  const idx = STOPS.findIndex((s) => s.id === stopId);
  const shouldFail = idx % 3 === 2 && prior === 0;
  notified.set(ledgerKey, prior + 1);

  /* 200 OK with a failure payload */
  const payload = shouldFail
    ? { stop_id: stopId, status: "failed", reason: "carrier_rejected", attempts: prior + 1 }
    : { stop_id: stopId, status: "sent", sent_at: new Date().toISOString(), attempts: prior + 1, deliveries: prior + 1 };

  if (key) notified.set(ledgerKey + "|" + key, payload);
  return send(res, 200, payload);
}

/* ---------------------------------------------------------------- router */

const server = http.createServer(async (req, res) => {
  if (req.method === "OPTIONS") return send(res, 204);
  seq++;

  const wait = limited(req);
  if (wait) return send(res, 429, { error: "rate_limited" }, { "Retry-After": String(wait) });

  const u = new URL(req.url, "http://localhost");
  const p = u.pathname.replace(/\/+$/, "");

  try {
    if (req.method === "GET" && p === "/v1/stops") return await listStops(u, res);

    let m = p.match(/^\/v1\/stops\/([^/]+)\/photos$/);
    if (req.method === "GET" && m) return await getPhotos(m[1], res);

    m = p.match(/^\/v1\/stops\/([^/]+)$/);
    if (req.method === "GET" && m) return await getStop(m[1], res);

    if (req.method === "POST" && p === "/v1/routes") return await createRoute(await readBody(req), res);

    m = p.match(/^\/v1\/routes\/([^/]+)\/notify$/);
    if (req.method === "POST" && m) return await notify(m[1], await readBody(req), req.headers, res);

    if (p === "/health") return send(res, 200, { ok: true, requests: seq });

    return send(res, 404, { error: "no_such_route", path: p });
  } catch (e) {
    return send(res, 500, { error: "internal_error", detail: String(e && e.message) });
  }
});

server.listen(PORT, () => {
  console.log("Route Builder mock API on http://localhost:" + PORT);
  console.log("  GET  /v1/stops?page=1&page_size=10&q=&zone=");
  console.log("  GET  /v1/stops/:id");
  console.log("  GET  /v1/stops/:id/photos");
  console.log("  POST /v1/routes");
  console.log("  POST /v1/routes/:id/notify");
});
