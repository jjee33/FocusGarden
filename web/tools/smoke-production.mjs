/**
 * A repeatable check that the live site is actually working.
 *
 *     node --no-warnings tools/smoke-production.mjs [origin]
 *
 * Everything here has been checked by hand at least once during development,
 * which is exactly the problem: a check performed once is a fact about the past.
 * This asserts the same things on demand, exits non-zero when any of them stops
 * being true, and is cheap enough to run after every deploy.
 *
 * Deliberately READ-ONLY and unauthenticated. It creates no accounts and writes
 * nothing, so it is safe to run against production as often as you like - a
 * smoke test that pollutes the database is one people stop running.
 */

const ORIGIN = process.argv[2] ?? "https://thefocusgarden.com";

const checks = [];
function check(name, fn) { checks.push({ name, fn }); }

async function get(path, init) {
  const res = await fetch(`${ORIGIN}${path}`, { redirect: "manual", ...init });
  return { status: res.status, headers: res.headers, text: async () => res.text() };
}

// --- the pages a person or a crawler lands on -------------------------------

check("home serves HTML", async () => {
  const r = await get("/");
  if (r.status !== 200) throw new Error(`status ${r.status}`);
  const body = await r.text();
  if (!body.includes("Focus Garden")) throw new Error("no brand in the markup");
  // The pitch must survive with no JavaScript, or search engines see nothing.
  if (!body.includes("grew out of time you spent focusing")) {
    throw new Error("the pitch is missing from the static shell");
  }
});

for (const path of ["/privacy", "/terms"]) {
  check(`${path} is real HTML, not the app shell`, async () => {
    const r = await get(path);
    if (r.status !== 200) throw new Error(`status ${r.status}`);
    const body = await r.text();
    if (!/Privacy Policy|Terms of Service/.test(body)) throw new Error("served the SPA instead");
  });
}

check("robots.txt parses as robots.txt", async () => {
  const r = await get("/robots.txt");
  if (r.status !== 200) throw new Error(`status ${r.status}`);
  const body = await r.text();
  if (body.trimStart().startsWith("<")) throw new Error("served HTML - the SPA fallback ate it");
  if (!body.includes("Sitemap:")) throw new Error("no sitemap line");
});

check("sitemap.xml is XML", async () => {
  const r = await get("/sitemap.xml");
  const body = await r.text();
  if (!body.includes("<urlset")) throw new Error("not a sitemap");
});

check("link preview image exists", async () => {
  const r = await get("/og.png");
  if (r.status !== 200) throw new Error(`status ${r.status}`);
  if (!(r.headers.get("content-type") ?? "").includes("image/png")) {
    throw new Error(`content-type ${r.headers.get("content-type")}`);
  }
});

check("Open Graph tags are present", async () => {
  const body = await (await get("/")).text();
  for (const tag of ["og:title", "og:image", "og:description", "twitter:card"]) {
    if (!body.includes(tag)) throw new Error(`missing ${tag}`);
  }
});

// --- the API ----------------------------------------------------------------

check("health reports every credential valid", async () => {
  const r = await get("/api/health");
  const body = JSON.parse(await r.text());
  if (body.ok !== true) {
    throw new Error(`missing: ${body.missing?.join(",") || "none"}; `
      + `malformed: ${(body.malformed ?? []).map((m) => m.key).join(",") || "none"}`);
  }
});

check("sync refuses anonymous callers", async () => {
  const r = await get("/api/sync/pull?since=0&sessionsSince=0");
  if (r.status !== 401) throw new Error(`expected 401, got ${r.status}`);
});

check("account deletion refuses anonymous callers", async () => {
  const r = await get("/api/account/delete", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: "anyone@example.com" }),
  });
  if (r.status !== 401) throw new Error(`expected 401, got ${r.status}`);
});

check("sign-in does not reveal whether an address is registered", async () => {
  const attempt = async (email) => {
    const r = await get("/api/auth/sign-in/email", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password: "definitely-not-the-password" }),
    });
    return `${r.status}:${await r.text()}`;
  };
  const unknown = await attempt("certainly-nobody-here@example.com");
  const known = await attempt("admin@thefocusgarden.com");
  if (unknown !== known) {
    throw new Error("responses differ, so the endpoint is an address lookup service");
  }
});

check("the verification link reaches the server", async () => {
  // The service worker used to answer this from the precache, which silently
  // broke sign-up for everyone who had loaded the app before opening their email.
  const r = await get("/api/auth/verify-email?token=not-a-real-token&callbackURL=%2F");
  const body = await r.text();
  if (body.includes("<!doctype html") || body.includes("<div id=\"root\"")) {
    throw new Error("served the app shell instead of hitting the endpoint");
  }
});

check("Google sign-in builds a real, correct redirect", async () => {
  const r = await get("/api/auth/sign-in/social", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ provider: "google", callbackURL: "/" }),
  });
  const body = JSON.parse(await r.text());
  const url = new URL(body.url ?? "");
  if (!url.host.includes("google")) throw new Error("not pointed at Google");
  if (url.searchParams.get("redirect_uri") !== `${ORIGIN}/api/auth/callback/google`) {
    throw new Error(`redirect_uri is ${url.searchParams.get("redirect_uri")}`);
  }
  if (url.searchParams.get("code_challenge") === null) throw new Error("no PKCE challenge");
});

check("mail endpoints are rate limited", async () => {
  const body = JSON.stringify({ email: `smoke-${Date.now()}@example.invalid` });
  const opts = { method: "POST", headers: { "Content-Type": "application/json" }, body };
  const first = await get("/api/account/resend-verification", opts);
  const second = await get("/api/account/resend-verification", opts);
  if (first.status !== 200) throw new Error(`first call was ${first.status}`);
  if (second.status !== 429) throw new Error(`second call was ${second.status}, expected 429`);
});

// --- run --------------------------------------------------------------------

let failed = 0;
for (const { name, fn } of checks) {
  try {
    await fn();
    console.log(`  ok    ${name}`);
  } catch (error) {
    failed += 1;
    console.log(`  FAIL  ${name}`);
    console.log(`        ${error.message}`);
  }
}

console.log(`\n${checks.length - failed}/${checks.length} passed against ${ORIGIN}`);
process.exit(failed === 0 ? 0 : 1);
