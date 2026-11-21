#!/usr/bin/env python3
"""fetch_ci_ipa.py — fetch + verify the latest simplyMANGA unsigned CI .ipa.

Read-only against GitHub (gh api / gh run download). Never triggers runs,
never pushes, never mutates remote state — per the local-first git model
(origin is backup + CI only).

Pipeline:
  1. resolve run: --run <id>, or latest successful run of ios.yml on main
  2. check artifact exists and is not expired (retention-days: 14)
  3. gh run download -> <out>/run-<id>/simplyMANGA-unsigned.ipa (cached;
     --force re-downloads)
  4. sha256 + verify_ipa.py (sideload-readiness)
  5. write <out>/run-<id>/build-info.json (run id, commit, sha256, version,
     verifier verdict) — the provenance record for the sideload runbook

Stdlib only + gh CLI on PATH. Python 3.9+.

Usage (on the VPS):
  python3 tool/ios/fetch_ci_ipa.py                 # latest green main build
  python3 tool/ios/fetch_ci_ipa.py --run 44853126499
  python3 tool/ios/fetch_ci_ipa.py --out /tmp/ipa --force
"""

import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_REPO = "simplyjaytea/simplymanga"
DEFAULT_WORKFLOW = "ios.yml"
DEFAULT_BRANCH = "main"
DEFAULT_ARTIFACT = "simplyMANGA-unsigned-ipa"
DEFAULT_OUT = "/root/.local/share/simplymanga/ipa"


def gh(*args):
    """Run gh, return parsed stdout. Raises RuntimeError with stderr."""
    cmd = ["gh"] + list(args)
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError("gh failed (%d): %s\n%s"
                           % (p.returncode, " ".join(cmd), p.stderr.strip()))
    return p.stdout


def gh_json(*args):
    return json.loads(gh(*args))


def resolve_run(repo, workflow, branch, run_id):
    if run_id:
        return gh_json("api", "repos/%s/actions/runs/%s" % (repo, run_id))
    runs = gh_json("api",
                   "repos/%s/actions/workflows/%s/runs"
                   "?branch=%s&status=success&per_page=5"
                   % (repo, workflow, branch))
    candidates = runs.get("workflow_runs") or []
    if not candidates:
        raise RuntimeError("no successful %s runs on %s in %s"
                           % (workflow, branch, repo))
    return candidates[0]


def find_artifact(repo, run_id, name):
    arts = gh_json("api", "repos/%s/actions/runs/%s/artifacts" % (repo, run_id))
    for a in arts.get("artifacts", []):
        if a["name"] == name:
            return a
    raise RuntimeError("artifact %r not found on run %s (have: %s)"
                       % (name, run_id,
                          [a["name"] for a in arts.get("artifacts", [])]))


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Fetch + verify the latest simplyMANGA unsigned CI .ipa (read-only).")
    ap.add_argument("--run", type=int, default=None, help="specific run id")
    ap.add_argument("--repo", default=DEFAULT_REPO)
    ap.add_argument("--workflow", default=DEFAULT_WORKFLOW)
    ap.add_argument("--branch", default=DEFAULT_BRANCH)
    ap.add_argument("--artifact-name", default=DEFAULT_ARTIFACT)
    ap.add_argument("--out", default=DEFAULT_OUT, help="cache root directory")
    ap.add_argument("--force", action="store_true", help="re-download even if cached")
    ap.add_argument("--skip-verify", action="store_true")
    args = ap.parse_args(argv)

    if not shutil.which("gh"):
        print("error: gh CLI not found on PATH (https://cli.github.com)",
              file=sys.stderr)
        return 2

    try:
        run = resolve_run(args.repo, args.workflow, args.branch, args.run)
        run_id = run["id"]
        print("run %s: %s @ %s (%s) — %s"
              % (run_id, run.get("head_branch"), (run.get("head_sha") or "")[:9],
                 run.get("event"), run.get("html_url")))
        if run.get("conclusion") != "success":
            print("error: run conclusion is %r, not success"
                  % run.get("conclusion"), file=sys.stderr)
            return 1
        art = find_artifact(args.repo, run_id, args.artifact_name)
        if art.get("expired"):
            print("error: artifact %r expired (retention window passed). "
                  "Trigger a fresh build (workflow_dispatch) or use a newer run."
                  % args.artifact_name, file=sys.stderr)
            return 1

        dest = os.path.join(args.out, "run-%s" % run_id)
        os.makedirs(dest, exist_ok=True)
        existing = [f for f in os.listdir(dest) if f.endswith(".ipa")]
        if existing and not args.force:
            ipa = os.path.join(dest, existing[0])
            print("cached: %s (use --force to re-download)" % ipa)
        else:
            gh("run", "download", str(run_id), "--repo", args.repo,
               "--name", args.artifact_name, "--dir", dest)
            ipas = [f for f in os.listdir(dest) if f.endswith(".ipa")]
            if not ipas:
                print("error: no .ipa in downloaded artifact", file=sys.stderr)
                return 1
            ipa = os.path.join(dest, ipas[0])
            print("downloaded: %s (%d bytes)" % (ipa, os.path.getsize(ipa)))
    except RuntimeError as e:
        print("error: %s" % e, file=sys.stderr)
        return 1

    report = None
    if not args.skip_verify:
        p = subprocess.run(
            [sys.executable, os.path.join(HERE, "verify_ipa.py"), ipa,
             "--expect-bundle-id", "com.simplymanga.app", "--json"],
            capture_output=True, text=True)
        try:
            report = json.loads(p.stdout)
        except json.JSONDecodeError:
            print("error: verifier produced no JSON:\n%s\n%s"
                  % (p.stdout, p.stderr), file=sys.stderr)
            return 1
        if not report["ok"]:
            print("VERIFIER FAILED:", file=sys.stderr)
            for f in report["fatal"]:
                print("  FATAL: %s" % f, file=sys.stderr)
            return 1

    info = (report or {}).get("info", {})
    build_info = {
        "repo": args.repo,
        "run_id": run_id,
        "run_url": run.get("html_url"),
        "head_branch": run.get("head_branch"),
        "head_sha": run.get("head_sha"),
        "run_created_at": run.get("created_at"),
        "artifact_name": args.artifact_name,
        "artifact_id": art.get("id"),
        "artifact_bytes": art.get("size_in_bytes"),
        "ipa_path": os.path.abspath(ipa),
        "ipa_bytes": os.path.getsize(ipa),
        "ipa_sha256": info.get("sha256"),
        "bundle_id": info.get("CFBundleIdentifier"),
        "version": info.get("CFBundleShortVersionString"),
        "build": info.get("CFBundleVersion"),
        "min_ios": info.get("MinimumOSVersion"),
        "unsigned": info.get("unsigned"),
        "verifier_ok": (report or {}).get("ok"),
        "verifier_warnings": (report or {}).get("warnings", []),
        "fetched_at_utc": datetime.datetime.now(datetime.timezone.utc)
                          .strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    bi_path = os.path.join(dest, "build-info.json")
    with open(bi_path, "w") as f:
        json.dump(build_info, f, indent=2, sort_keys=True)
        f.write("\n")
    print("build-info: %s" % bi_path)
    print("READY: %s  %s (%s)  sha256=%s"
          % (ipa, build_info["version"], build_info["build"],
             (build_info["ipa_sha256"] or "")[:16] + "…"))
    if build_info["verifier_warnings"]:
        for w in build_info["verifier_warnings"]:
            print("  WARN: %s" % w)
    return 0


if __name__ == "__main__":
    sys.exit(main())
