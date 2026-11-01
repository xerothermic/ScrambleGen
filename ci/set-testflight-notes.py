#!/usr/bin/env python3
"""Set the TestFlight "What to Test" text of the build that CI just uploaded.

Runs after the upload step on a macOS runner; needs only python3 and openssl.
Waits for App Store Connect to list and finish processing the build, then
creates or updates the en-US betaBuildLocalization. Never fails the job: any
problem is logged as a warning and the script exits 0 (the workflow step is
also continue-on-error).

Env in:  ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, MARKETING_VERSION,
         BUILD_NUMBER, BUNDLE_ID (default com.pcintaiwan.scramblegen),
         GITHUB_REF_NAME, GITHUB_SHA, GITHUB_REPOSITORY, GITHUB_EVENT_BEFORE
         (optional), GH_TOKEN (optional, for the PR title),
         POLL_SECONDS (30), POLL_TIMEOUT (1200), ASC_API_BASE (testing).
Commit messages and PR titles are untrusted: they are only ever handled as
data here (argv lists, JSON encoding), never through a shell.
"""
import base64, json, os, subprocess, sys, time, urllib.error, urllib.parse, urllib.request

API = os.environ.get("ASC_API_BASE", "https://api.appstoreconnect.apple.com")
LIMIT = 4000
ZERO = "0" * 40


def b64u(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def der_to_raw(der):
    """ECDSA DER signature -> 64-byte r||s as JWT ES256 requires."""
    assert der[0] == 0x30
    i = 2 + (der[1] - 0x80 if der[1] & 0x80 else 0)
    parts = []
    for _ in range(2):
        assert der[i] == 0x02
        n = der[i + 1]
        parts.append(int.from_bytes(der[i + 2:i + 2 + n], "big").to_bytes(32, "big"))
        i += 2 + n
    return b"".join(parts)


def make_jwt(key_id, issuer, key_path, now=None):
    now = int(now or time.time())
    head = b64u(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    body = b64u(json.dumps({"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
                           separators=(",", ":")).encode())
    signing_input = f"{head}.{body}".encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path], input=signing_input,
                         capture_output=True, check=True).stdout
    return f"{head}.{body}.{b64u(der_to_raw(der))}"


def call(method, path, token, payload=None, query=None):
    url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:600]
        raise RuntimeError(f"{method} {path} -> HTTP {e.code}: {detail}")


def git(*args):
    r = subprocess.run(["git", *args], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def commit_subjects(before):
    git("fetch", "--quiet", "--deepen=30")
    rng = None
    if before and before != ZERO and git("cat-file", "-t", before).strip() == "commit":
        rng = f"{before}..HEAD"
    out = git("log", "--no-merges", "--format=%s", "-n", "10" if rng else "5", *( [rng] if rng else [] ))
    subs = [s.split("Co-Authored-By:")[0].strip() for s in out.splitlines()]
    subs = [s for s in subs if s]
    # The CI build-number bump commits are noise.
    subs = [s for s in subs if not s.startswith("Build number ")]
    if not subs and rng:  # force-push or only bump commits: fall back
        return commit_subjects("")
    return subs


def pr_title(repo, branch):
    if not (os.environ.get("GH_TOKEN") and repo and branch):
        return ""
    owner = repo.split("/")[0]
    r = subprocess.run(["gh", "api", f"repos/{repo}/pulls", "-X", "GET", "-f", f"head={owner}:{branch}",
                        "-f", "state=open", "--jq", ".[0].title // empty"], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def build_notes(branch, sha, build, version, subjects, title):
    lines = [f"Branch: {branch}", f"Commit: {sha[:7]}", f"Build: {version} ({build})"]
    if title:
        lines.append(f"PR: {title}")
    lines += ["", "Changes:"] + [f"- {s}" for s in subjects]
    text = "\n".join(lines)
    return text if len(text) <= LIMIT else text[:LIMIT - 1].rstrip() + "…"


def main():
    env = os.environ
    key_id, issuer, key_path = env["ASC_KEY_ID"], env["ASC_ISSUER_ID"], env["ASC_KEY_PATH"]
    version, build = env["MARKETING_VERSION"], env["BUILD_NUMBER"]
    bundle = env.get("BUNDLE_ID", "com.pcintaiwan.scramblegen")
    poll, timeout = int(env.get("POLL_SECONDS", "30")), int(env.get("POLL_TIMEOUT", "1200"))

    notes = build_notes(env.get("GITHUB_REF_NAME", "?"), env.get("GITHUB_SHA", "?" * 7), build, version,
                        commit_subjects(env.get("GITHUB_EVENT_BEFORE", "")),
                        pr_title(env.get("GITHUB_REPOSITORY", ""), env.get("GITHUB_REF_NAME", "")))
    print("Notes to set:\n" + notes + "\n")

    token = make_jwt(key_id, issuer, key_path)
    apps = call("GET", "/v1/apps", token, query={"filter[bundleId]": bundle})["data"]
    if not apps:
        raise RuntimeError(f"no app with bundle id {bundle} visible to this API key")
    app_id = apps[0]["id"]

    deadline = time.time() + timeout
    build_id = None
    while True:
        token = make_jwt(key_id, issuer, key_path)
        found = call("GET", "/v1/builds", token, query={
            "filter[app]": app_id, "filter[version]": build,
            "filter[preReleaseVersion.version]": version, "limit": "1"})["data"]
        state = found[0]["attributes"].get("processingState") if found else None
        print(f"build {version} ({build}): {state or 'not listed yet'}")
        if found and state == "VALID":
            build_id = found[0]["id"]
            break
        if found and state in ("FAILED", "INVALID"):
            raise RuntimeError(f"build processing ended in state {state}")
        if time.time() + poll > deadline:
            raise RuntimeError(f"build still not processed after {timeout}s")
        time.sleep(poll)

    token = make_jwt(key_id, issuer, key_path)
    locs = call("GET", f"/v1/builds/{build_id}/betaBuildLocalizations", token)["data"]
    existing = next((l for l in locs if l["attributes"].get("locale") == "en-US"), None)
    if existing:
        call("PATCH", f"/v1/betaBuildLocalizations/{existing['id']}", token, {
            "data": {"type": "betaBuildLocalizations", "id": existing["id"],
                     "attributes": {"whatsNew": notes}}})
    else:
        call("POST", "/v1/betaBuildLocalizations", token, {
            "data": {"type": "betaBuildLocalizations",
                     "attributes": {"locale": "en-US", "whatsNew": notes},
                     "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
    print(f"TestFlight 'What to Test' set for build {version} ({build}).")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # never fail the workflow over release notes
        print(f"::warning::Could not set TestFlight notes: {e}")
        print("Set them by hand: App Store Connect > TestFlight > build > Test Details.")
    sys.exit(0)
