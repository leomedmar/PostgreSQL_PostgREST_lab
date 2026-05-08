#!/usr/bin/env python3
"""Local demo dashboard for the PostgREST multi-tenant lab."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import threading
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

BASE_URL = os.getenv("BASE_URL", "http://localhost:3000")

_ANSI_RE = re.compile(r'\x1b\[[0-9;]*m')
HOST = os.getenv("DEMO_DASHBOARD_HOST", "127.0.0.1")
PORT = int(os.getenv("DEMO_DASHBOARD_PORT", "8090"))
REPO_ROOT = Path(__file__).resolve().parent.parent
TEST_SUITES = [
  "test-auth-edge",
  "test-input-validation",
  "test-cross-tenant-writes",
  "test-query-hardening",
  "test-api-surface",
  "test-integrity-consistency",
  "test-security-all",
  "test-integrity-all",
  "test-resilience",
  "test-rebuild-baseline",
  "test-all",
]

WALKTHROUGH_STATE: dict[str, Any] = {
    "running": False,
    "started_at": None,
    "finished_at": None,
    "exit_code": None,
    "output": "",
    "last_error": None,
}
WALKTHROUGH_LOCK = threading.Lock()

TEST_SUITE_STATE: dict[str, dict[str, Any]] = {
  suite: {
    "running": False,
    "started_at": None,
    "finished_at": None,
    "exit_code": None,
    "output": "",
    "last_error": None,
    "results": [],
  }
  for suite in TEST_SUITES
}
TEST_SUITE_LOCK = threading.Lock()


def _extract_tokens_from_script() -> dict[str, str]:
    script_path = REPO_ROOT / "tests" / "generate_tokens.py"
    result = subprocess.run(
        ["python3", str(script_path)],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    if result.returncode != 0:
        raise RuntimeError(
            "Could not generate demo tokens. Run `python3 tests/generate_tokens.py` "
            "to inspect the issue."
        )

    token_a_match = re.search(r'export TOKEN_A="([^"]+)"', result.stdout)
    token_b_match = re.search(r'export TOKEN_B="([^"]+)"', result.stdout)

    if not token_a_match or not token_b_match:
        raise RuntimeError("Token generation output did not include TOKEN_A/TOKEN_B exports.")

    return {
        "TOKEN_A": token_a_match.group(1),
        "TOKEN_B": token_b_match.group(1),
    }


def load_tokens() -> dict[str, str]:
    token_a = os.getenv("TOKEN_A")
    token_b = os.getenv("TOKEN_B")

    if token_a and token_b:
        return {"TOKEN_A": token_a, "TOKEN_B": token_b}

    return _extract_tokens_from_script()


def request_products(token: str | None, profile: str) -> tuple[int, str]:
    url = f"{BASE_URL}/products"
    headers: dict[str, str] = {"Accept-Profile": profile}

    if token:
        headers["Authorization"] = f"Bearer {token}"

    req = urllib.request.Request(url=url, method="GET", headers=headers)

    try:
        with urllib.request.urlopen(req, timeout=8) as response:
            body = response.read().decode("utf-8", errors="replace")
            return response.getcode(), body
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return exc.code, body


def is_empty_array(body: str) -> bool:
    try:
        parsed = json.loads(body or "[]")
    except Exception:
        return False
    return isinstance(parsed, list) and len(parsed) == 0


def evaluate_scenarios() -> dict[str, Any]:
    tokens = load_tokens()

    scenarios = [
        {
            "id": 1,
            "name": "TOKEN_A with tenant_b profile",
            "token": tokens["TOKEN_A"],
            "profile": "tenant_b",
            "expect_deny": True,
        },
        {
            "id": 2,
            "name": "TOKEN_B with tenant_a profile",
            "token": tokens["TOKEN_B"],
            "profile": "tenant_a",
            "expect_deny": True,
        },
        {
            "id": 3,
            "name": "Anon request with tenant_a profile",
            "token": None,
            "profile": "tenant_a",
            "expect_deny": True,
        },
        {
            "id": 4,
            "name": "TOKEN_A with tenant_a profile",
            "token": tokens["TOKEN_A"],
            "profile": "tenant_a",
            "expect_deny": False,
        },
        {
            "id": 5,
            "name": "TOKEN_B with tenant_b profile",
            "token": tokens["TOKEN_B"],
            "profile": "tenant_b",
            "expect_deny": False,
        },
    ]

    results: list[dict[str, Any]] = []
    pass_count = 0

    for scenario in scenarios:
        code, body = request_products(scenario["token"], scenario["profile"])
        deny = scenario["expect_deny"]

        if deny:
            passed = code not in (200, 201) or (code in (200, 201) and is_empty_array(body))
        else:
            passed = code in (200, 201)

        if passed:
            pass_count += 1

        body_preview = body.strip().replace("\n", " ")
        if len(body_preview) > 200:
            body_preview = body_preview[:200] + "..."

        results.append(
            {
                "id": scenario["id"],
                "name": scenario["name"],
                "profile": scenario["profile"],
                "expect_deny": deny,
                "http_code": code,
                "passed": passed,
                "body_preview": body_preview,
            }
        )

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "base_url": BASE_URL,
        "pass_count": pass_count,
        "fail_count": len(results) - pass_count,
        "results": results,
    }


def get_walkthrough_state() -> dict[str, Any]:
    with WALKTHROUGH_LOCK:
        return {
            "running": WALKTHROUGH_STATE["running"],
            "started_at": WALKTHROUGH_STATE["started_at"],
            "finished_at": WALKTHROUGH_STATE["finished_at"],
            "exit_code": WALKTHROUGH_STATE["exit_code"],
            "output": WALKTHROUGH_STATE["output"],
            "last_error": WALKTHROUGH_STATE["last_error"],
        }


def run_walkthrough_background() -> None:
    command = ["bash", "demo/03_walkthrough.sh"]

    with WALKTHROUGH_LOCK:
        WALKTHROUGH_STATE.update(
            {
                "running": True,
                "started_at": datetime.now(timezone.utc).isoformat(),
                "finished_at": None,
                "exit_code": None,
                "output": "",
                "last_error": None,
            }
        )

    try:
        process = subprocess.Popen(
            command,
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

        combined_output: list[str] = []
        assert process.stdout is not None

        for line in process.stdout:
            combined_output.append(line)
            with WALKTHROUGH_LOCK:
                WALKTHROUGH_STATE["output"] = "".join(combined_output)[-12000:]

        exit_code = process.wait()
        with WALKTHROUGH_LOCK:
            WALKTHROUGH_STATE["running"] = False
            WALKTHROUGH_STATE["finished_at"] = datetime.now(timezone.utc).isoformat()
            WALKTHROUGH_STATE["exit_code"] = exit_code
            WALKTHROUGH_STATE["output"] = "".join(combined_output)[-12000:]
    except Exception as exc:
        with WALKTHROUGH_LOCK:
            WALKTHROUGH_STATE["running"] = False
            WALKTHROUGH_STATE["finished_at"] = datetime.now(timezone.utc).isoformat()
            WALKTHROUGH_STATE["exit_code"] = -1
            WALKTHROUGH_STATE["last_error"] = str(exc)


def start_walkthrough_run() -> tuple[bool, str]:
    with WALKTHROUGH_LOCK:
        if WALKTHROUGH_STATE["running"]:
            return False, "Walkthrough is already running."

    worker = threading.Thread(target=run_walkthrough_background, daemon=True)
    worker.start()
    return True, "Walkthrough execution started."


def get_test_suite_status() -> dict[str, Any]:
    with TEST_SUITE_LOCK:
        suites = {
            name: {
                "running": state["running"],
                "started_at": state["started_at"],
                "finished_at": state["finished_at"],
                "exit_code": state["exit_code"],
                "output": state["output"],
                "last_error": state["last_error"],
                "results": state["results"],
            }
            for name, state in TEST_SUITE_STATE.items()
        }

    return {
        "suites": suites,
        "running_any": any(item["running"] for item in suites.values()),
    }


def any_test_suite_running() -> bool:
    with TEST_SUITE_LOCK:
        return any(state["running"] for state in TEST_SUITE_STATE.values())


def run_test_suite_background(suite: str) -> None:
    with TEST_SUITE_LOCK:
        TEST_SUITE_STATE[suite].update(
            {
                "running": True,
                "started_at": datetime.now(timezone.utc).isoformat(),
                "finished_at": None,
                "exit_code": None,
                "output": "",
                "last_error": None,
            }
        )

    try:
        process = subprocess.Popen(
            ["make", suite],
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

        combined_output: list[str] = []
        assert process.stdout is not None

        for line in process.stdout:
            combined_output.append(line)
            with TEST_SUITE_LOCK:
                TEST_SUITE_STATE[suite]["output"] = "".join(combined_output)[-12000:]

        exit_code = process.wait()
        final_output = "".join(combined_output)[-12000:]
        with TEST_SUITE_LOCK:
            TEST_SUITE_STATE[suite]["running"] = False
            TEST_SUITE_STATE[suite]["finished_at"] = datetime.now(timezone.utc).isoformat()
            TEST_SUITE_STATE[suite]["exit_code"] = exit_code
            TEST_SUITE_STATE[suite]["output"] = final_output
            TEST_SUITE_STATE[suite]["results"] = parse_suite_results(final_output)
    except Exception as exc:
        with TEST_SUITE_LOCK:
            TEST_SUITE_STATE[suite]["running"] = False
            TEST_SUITE_STATE[suite]["finished_at"] = datetime.now(timezone.utc).isoformat()
            TEST_SUITE_STATE[suite]["exit_code"] = -1
            TEST_SUITE_STATE[suite]["last_error"] = str(exc)


def parse_suite_results(output: str) -> list[dict[str, Any]]:
    clean = _ANSI_RE.sub('', output)
    results = []
    current_desc: str | None = None
    current_http: str = '-'
    for line in clean.splitlines():
        m_desc = re.match(r'\s*>\s*(.+)', line)
        if m_desc:
            current_desc = m_desc.group(1).strip()
            current_http = '-'
            continue
        m_http = re.match(r'\s*HTTP:\s*(\S+)', line)
        if m_http:
            current_http = m_http.group(1)
            continue
        m = re.match(r'\s*(PASS|FAIL)\s*--\s*(.+)', line)
        if m:
            results.append({
                'id': len(results) + 1,
                'name': current_desc or m.group(2).strip(),
                'passed': m.group(1) == 'PASS',
                'http_code': current_http,
                'profile': '-',
                'expect_deny': None,
                'body_preview': '',
            })
            current_desc = None
            current_http = '-'
    return results


def start_test_suite_run(suite: str) -> tuple[bool, str]:
    if suite not in TEST_SUITES:
        return False, f"Unknown suite: {suite}"

    if any_test_suite_running():
        return False, "Another test suite is already running."

    worker = threading.Thread(target=run_test_suite_background, args=(suite,), daemon=True)
    worker.start()
    return True, f"Test suite started: {suite}"


HTML_PAGE = """<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
  <title>PostgREST Demo Dashboard</title>
  <style>
    :root {
      --ink: #11212d;
      --paper: #f4f1ea;
      --accent: #0f8b8d;
      --accent-2: #b23a48;
      --ok: #1a7f37;
      --bad: #b42318;
      --muted: #4f5d75;
      --card: #fffdf7;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: \"Space Grotesk\", \"Avenir Next\", \"Segoe UI\", sans-serif;
      color: var(--ink);
      background:
        radial-gradient(circle at 10% 10%, #f9d29d 0, transparent 28%),
        radial-gradient(circle at 90% 20%, #9bd1cf 0, transparent 30%),
        linear-gradient(130deg, #f7f3ec 0%, #e8eef2 100%);
      min-height: 100vh;
      padding: 24px;
    }
    .wrap {
      max-width: 1100px;
      margin: 0 auto;
      display: grid;
      gap: 16px;
    }
    .hero {
      background: var(--card);
      border: 2px solid #d9d6ce;
      border-radius: 16px;
      padding: 18px 20px;
      box-shadow: 0 6px 24px rgba(17, 33, 45, 0.08);
    }
    .hero h1 {
      margin: 0 0 8px;
      letter-spacing: 0.02em;
    }
    .meta {
      color: var(--muted);
      font-size: 0.95rem;
      display: flex;
      gap: 20px;
      flex-wrap: wrap;
    }
    .cards {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 12px;
    }
    .card {
      background: var(--card);
      border: 2px solid #ddd8cc;
      border-radius: 14px;
      padding: 14px;
    }
    .value {
      font-size: 2rem;
      font-weight: 700;
      margin-top: 6px;
    }
    .ok { color: var(--ok); }
    .bad { color: var(--bad); }
    table {
      width: 100%;
      border-collapse: collapse;
      background: var(--card);
      border: 2px solid #d9d6ce;
      border-radius: 14px;
      overflow: hidden;
    }
    th, td {
      text-align: left;
      padding: 10px 12px;
      border-bottom: 1px solid #ece7dd;
      font-size: 0.95rem;
      vertical-align: top;
    }
    th {
      background: #f0ebe0;
      font-size: 0.85rem;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    tr:last-child td { border-bottom: none; }
    .pill {
      display: inline-block;
      padding: 4px 8px;
      border-radius: 999px;
      font-size: 0.8rem;
      font-weight: 700;
    }
    .pill.ok { background: #d5f5df; color: #125c2f; }
    .pill.bad { background: #fee4e2; color: #8e1b12; }
    .error {
      background: #fee4e2;
      color: #8e1b12;
      border: 2px solid #f5b8b2;
      border-radius: 10px;
      padding: 10px;
      display: none;
    }
    .actions {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
      align-items: center;
    }
    button {
      border: 0;
      border-radius: 10px;
      padding: 10px 14px;
      font-weight: 700;
      cursor: pointer;
      background: var(--accent);
      color: #ffffff;
      transition: transform 0.15s ease, opacity 0.15s ease;
    }
    button:hover { transform: translateY(-1px); }
    button:disabled { opacity: 0.6; cursor: not-allowed; }
    .status-line {
      color: var(--muted);
      font-size: 0.92rem;
    }
    .console {
      background: #1e252d;
      color: #e8f0f5;
      border-radius: 12px;
      padding: 12px;
      font-family: \"JetBrains Mono\", \"Fira Code\", \"Consolas\", monospace;
      white-space: pre-wrap;
      min-height: 180px;
      max-height: 320px;
      overflow: auto;
      border: 2px solid #3a4b5c;
    }
    .suite-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
      gap: 10px;
      margin-top: 8px;
    }
    .suite-card {
      border: 2px solid #ddd8cc;
      border-radius: 10px;
      padding: 10px;
      background: #fff9ef;
    }
    .suite-card h4 {
      margin: 0 0 6px;
      font-size: 0.95rem;
    }
    .suite-status {
      font-size: 0.88rem;
      color: var(--muted);
    }
    .suite-controls {
      display: flex;
      gap: 8px;
      align-items: center;
      flex-wrap: wrap;
      margin-top: 10px;
    }
    select {
      border-radius: 8px;
      border: 2px solid #c9c3b7;
      padding: 7px 10px;
      background: #fffdf7;
      color: var(--ink);
      font-weight: 600;
    }
  </style>
</head>
<body>
  <div class=\"wrap\">
    <section class=\"hero\">
      <h1>Multi-Tenant Isolation Live Dashboard</h1>
      <div class=\"meta\">
        <span id=\"base\">BASE_URL: -</span>
        <span id=\"updated\">Updated: -</span>
        <span id=\"refreshLabel\">Auto-refresh: 3s</span>
        <button id=\"pauseBtn\" style=\"margin-left:12px;padding:3px 12px;font-size:0.8rem;\">Pause</button>
      </div>
    </section>

    <section class=\"cards\">
      <article class=\"card\">
        <div>Total scenarios</div>
        <div class=\"value\" id=\"total\">-</div>
      </article>
      <article class=\"card\">
        <div>Passed</div>
        <div class=\"value ok\" id=\"pass\">-</div>
      </article>
      <article class=\"card\">
        <div>Failed</div>
        <div class=\"value bad\" id=\"fail\">-</div>
      </article>
    </section>

    <div id=\"error\" class=\"error\"></div>

    <section>
      <div style=\"display:flex;align-items:center;gap:10px;margin-bottom:8px;\">
        <label for=\"tableSourceSelect\" style=\"font-weight:600;font-size:0.9rem;\">Showing:</label>
        <select id=\"tableSourceSelect\">
          <option value=\"live\">Live scenarios</option>
        </select>
        <span id=\"tableSourceLabel\" style=\"font-size:0.85rem;color:#666;\"></span>
      </div>
      <table>
        <thead>
          <tr>
            <th>#</th>
            <th>Scenario</th>
            <th>Profile</th>
            <th>HTTP</th>
            <th>Expectation</th>
            <th>Status</th>
            <th>Body preview</th>
          </tr>
        </thead>
        <tbody id=\"rows\"></tbody>
      </table>
    </section>

    <section class=\"card\">
      <h3 style=\"margin-top: 0;\">Run Walkthrough from Dashboard</h3>
      <div class=\"actions\">
        <button id=\"runWalkthroughBtn\">Run Demo Walkthrough</button>
        <span class=\"status-line\" id=\"walkthroughStatus\">Status: idle</span>
      </div>
      <div style=\"height: 10px;\"></div>
      <div class=\"console\" id=\"walkthroughOutput\">No walkthrough execution yet.</div>
    </section>

    <section class=\"card\">
      <h3 style=\"margin-top: 0;\">Run Test Suites from Dashboard</h3>
      <div class=\"suite-grid\">
        <article class=\"suite-card\">
          <h4>test-auth-edge</h4>
          <div class=\"suite-status\" id=\"suiteStatus_test-auth-edge\">idle</div>
        </article>
        <article class=\"suite-card\">
          <h4>test-input-validation</h4>
          <div class=\"suite-status\" id=\"suiteStatus_test-input-validation\">idle</div>
        </article>
        <article class=\"suite-card\">
          <h4>test-cross-tenant-writes</h4>
          <div class=\"suite-status\" id=\"suiteStatus_test-cross-tenant-writes\">idle</div>
        </article>
        <article class=\"suite-card\">
          <h4>test-query-hardening</h4>
          <div class=\"suite-status\" id=\"suiteStatus_test-query-hardening\">idle</div>
        </article>
        <article class=\"suite-card\">
          <h4>test-api-surface</h4>
          <div class=\"suite-status\" id=\"suiteStatus_test-api-surface\">idle</div>
        </article>
        <article class=\"suite-card\">
          <h4>test-integrity-consistency</h4>
          <div class=\"suite-status\" id=\"suiteStatus_test-integrity-consistency\">idle</div>
        </article>
        <article class=\"suite-card\">
          <h4>test-security-all</h4>
          <div class=\"suite-status\" id=\"suiteStatus_test-security-all\">idle</div>
        </article>
        <article class=\"suite-card\">
          <h4>test-integrity-all</h4>
          <div class=\"suite-status\" id=\"suiteStatus_test-integrity-all\">idle</div>
        </article>
        <article class=\"suite-card\">
          <h4>test-resilience</h4>
          <div class=\"suite-status\" id=\"suiteStatus_test-resilience\">idle</div>
        </article>
        <article class=\"suite-card\">
          <h4>test-rebuild-baseline (destructive)</h4>
          <div class=\"suite-status\" id=\"suiteStatus_test-rebuild-baseline\">idle</div>
        </article>
        <article class=\"suite-card\">
          <h4>test-all</h4>
          <div class=\"suite-status\" id=\"suiteStatus_test-all\">idle</div>
        </article>
      </div>
      <div class=\"suite-controls\">
        <button id=\"runSuiteBtn\">Run Selected Suite</button>
        <label for=\"suiteSelect\">Output view:</label>
        <select id=\"suiteSelect\">
          <option value=\"test-auth-edge\">test-auth-edge</option>
          <option value=\"test-input-validation\">test-input-validation</option>
          <option value=\"test-cross-tenant-writes\">test-cross-tenant-writes</option>
          <option value=\"test-query-hardening\">test-query-hardening</option>
          <option value=\"test-api-surface\">test-api-surface</option>
          <option value=\"test-integrity-consistency\">test-integrity-consistency</option>
          <option value=\"test-security-all\">test-security-all</option>
          <option value=\"test-integrity-all\">test-integrity-all</option>
          <option value=\"test-resilience\">test-resilience</option>
          <option value=\"test-rebuild-baseline\">test-rebuild-baseline (destructive)</option>
          <option value=\"test-all\">test-all</option>
        </select>
      </div>
      <div style=\"height: 10px;\"></div>
      <div class=\"console\" id=\"suiteOutput\">No suite execution yet.</div>
    </section>
  </div>

  <script>
    let tableSource = 'live';
    const completedSuites = {};

    function renderTableRows(results) {
      const rows = document.getElementById('rows');
      rows.innerHTML = '';
      for (const row of results) {
        const tr = document.createElement('tr');
        const addCell = (text) => {
          const td = document.createElement('td');
          td.textContent = String(text ?? '-');
          tr.appendChild(td);
        };
        addCell(row.id);
        addCell(row.name);
        addCell(row.profile);
        addCell(row.http_code);
        addCell(row.expect_deny === null ? '-' : (row.expect_deny ? 'Deny' : 'Allow'));
        const tdStatus = document.createElement('td');
        const span = document.createElement('span');
        span.className = 'pill ' + (row.passed ? 'ok' : 'bad');
        span.textContent = row.passed ? 'PASS' : 'FAIL';
        tdStatus.appendChild(span);
        tr.appendChild(tdStatus);
        addCell(row.body_preview || '');
        rows.appendChild(tr);
      }
    }

    function updateTableSourceSelector(suiteName, results) {
      const sel = document.getElementById('tableSourceSelect');
      if (!sel.querySelector('option[value="' + suiteName + '"]')) {
        const opt = document.createElement('option');
        opt.value = suiteName;
        opt.textContent = suiteName + ' results';
        sel.appendChild(opt);
      }
      completedSuites[suiteName] = results;
      sel.value = suiteName;
      tableSource = suiteName;
      document.getElementById('tableSourceLabel').textContent =
        results.length + ' tests — ' + results.filter(r => r.passed).length + ' passed, ' +
        results.filter(r => !r.passed).length + ' failed';
      renderTableRows(results);
    }

    document.getElementById('tableSourceSelect').addEventListener('change', (e) => {
      tableSource = e.target.value;
      if (tableSource === 'live') {
        document.getElementById('tableSourceLabel').textContent = '';
      } else if (completedSuites[tableSource]) {
        const results = completedSuites[tableSource];
        document.getElementById('tableSourceLabel').textContent =
          results.length + ' tests — ' + results.filter(r => r.passed).length + ' passed, ' +
          results.filter(r => !r.passed).length + ' failed';
        renderTableRows(results);
      }
    });

    const SUITES = [
      'test-auth-edge',
      'test-input-validation',
      'test-cross-tenant-writes',
      'test-query-hardening',
      'test-api-surface',
      'test-integrity-consistency',
      'test-security-all',
      'test-integrity-all',
      'test-resilience',
      'test-rebuild-baseline',
      'test-all',
    ];

    function formatSuiteStatus(state) {
      if (state.running) {
        return 'running';
      }
      if (state.exit_code === 0) {
        return 'passed';
      }
      if (state.exit_code === null) {
        return 'idle';
      }
      return 'failed (exit ' + state.exit_code + ')';
    }

    async function startWalkthrough() {
      const button = document.getElementById('runWalkthroughBtn');
      button.disabled = true;

      try {
        const response = await fetch('/api/walkthrough/start', { method: 'POST' });
        const payload = await response.json();

        if (!response.ok || !payload.started) {
          throw new Error(payload.message || ('HTTP ' + response.status));
        }
      } catch (err) {
        const status = document.getElementById('walkthroughStatus');
        status.textContent = 'Status: failed to start - ' + err;
      } finally {
        button.disabled = false;
      }
    }

    async function pollWalkthrough() {
      const status = document.getElementById('walkthroughStatus');
      const output = document.getElementById('walkthroughOutput');

      try {
        const response = await fetch('/api/walkthrough/status');
        if (!response.ok) {
          throw new Error('HTTP ' + response.status);
        }

        const data = await response.json();

        if (data.running) {
          status.textContent = 'Status: running';
        } else if (data.exit_code === 0) {
          status.textContent = 'Status: finished successfully';
        } else if (data.exit_code === null) {
          status.textContent = 'Status: idle';
        } else {
          status.textContent = 'Status: finished with errors (exit ' + data.exit_code + ')';
        }

        if (data.last_error) {
          status.textContent += ' | error: ' + data.last_error;
        }

        output.innerHTML = ansiToHtml(data.output || 'No walkthrough execution yet.');
        output.scrollTop = output.scrollHeight;
      } catch (err) {
        status.textContent = 'Status: error while polling - ' + err;
      }
    }

    async function runSelectedSuite() {
      const button = document.getElementById('runSuiteBtn');
      const suite = document.getElementById('suiteSelect').value;
      const output = document.getElementById('suiteOutput');

      if (suite === 'test-rebuild-baseline') {
        const confirmed = window.confirm(
          'test-rebuild-baseline is destructive and will reset containers and data. Continue?'
        );
        if (!confirmed) {
          output.textContent = 'Execution cancelled by user.';
          return;
        }
      }

      button.disabled = true;
      output.textContent = 'Starting ' + suite + '...';

      try {
        const response = await fetch('/api/test-suites/run', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ suite }),
        });
        const payload = await response.json();

        if (!response.ok || !payload.started) {
          throw new Error(payload.message || ('HTTP ' + response.status));
        }
      } catch (err) {
        output.textContent = 'Failed to start suite: ' + err;
      } finally {
        button.disabled = false;
      }
    }

    async function pollSuites() {
      const selectedSuite = document.getElementById('suiteSelect').value;
      const output = document.getElementById('suiteOutput');
      const button = document.getElementById('runSuiteBtn');

      try {
        const response = await fetch('/api/test-suites/status');
        if (!response.ok) {
          throw new Error('HTTP ' + response.status);
        }

        const payload = await response.json();
        const suites = payload.suites || {};

        for (const suite of SUITES) {
          const state = suites[suite] || { running: false, exit_code: null, output: '' };
          const statusNode = document.getElementById('suiteStatus_' + suite);
          if (statusNode) {
            statusNode.textContent = formatSuiteStatus(state);
          }
        }

        for (const [name, state] of Object.entries(suites)) {
          if (state.exit_code !== null && state.results && state.results.length > 0) {
            if (!completedSuites[name]) {
              updateTableSourceSelector(name, state.results);
            } else {
              completedSuites[name] = state.results;
            }
          }
        }

        const active = suites[selectedSuite];
        if (active) {
          output.innerHTML = ansiToHtml(active.output || 'No output yet for this suite.');
          output.scrollTop = output.scrollHeight;
        }

        button.disabled = payload.running_any === true;
      } catch (err) {
        output.textContent = 'Error while polling suites: ' + err;
      }
    }

    async function loadData() {
      const errorBox = document.getElementById('error');
      try {
        const response = await fetch('/api/scenarios');
        if (!response.ok) {
          throw new Error('HTTP ' + response.status);
        }

        const data = await response.json();
        errorBox.style.display = 'none';

        document.getElementById('base').textContent = 'BASE_URL: ' + data.base_url;
        document.getElementById('updated').textContent = 'Updated: ' + new Date(data.timestamp).toLocaleString();
        document.getElementById('total').textContent = String(data.results.length);
        document.getElementById('pass').textContent = String(data.pass_count);
        document.getElementById('fail').textContent = String(data.fail_count);

        if (tableSource === 'live') {
          renderTableRows(data.results);
        }
      } catch (err) {
        errorBox.textContent = 'Dashboard refresh failed: ' + err;
        errorBox.style.display = 'block';
      }
    }

    const ANSI_COLORS = {
      '0;30': '#555', '0;31': '#e06c75', '0;32': '#98c379',
      '0;33': '#e5c07b', '0;34': '#61afef', '0;35': '#c678dd',
      '0;36': '#56b6c2', '0;37': '#abb2bf',
      '1;31': '#e06c75', '1;32': '#98c379', '1;33': '#e5c07b', '1;34': '#61afef',
    };

    function ansiToHtml(text) {
      const escaped = text
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
      let result = '';
      let open = false;
      const parts = escaped.split(/\x1b\[([0-9;]*)m/);
      for (let i = 0; i < parts.length; i++) {
        if (i % 2 === 0) {
          result += parts[i];
        } else {
          if (open) { result += '</span>'; open = false; }
          const color = ANSI_COLORS[parts[i]];
          if (color) { result += '<span style="color:' + color + '">'; open = true; }
        }
      }
      if (open) result += '</span>';
      return result;
    }

    document.getElementById('runWalkthroughBtn').addEventListener('click', startWalkthrough);
    document.getElementById('runSuiteBtn').addEventListener('click', runSelectedSuite);
    document.getElementById('suiteSelect').addEventListener('change', pollSuites);

    loadData();
    pollWalkthrough();
    pollSuites();

    let paused = false;
    const timers = [
      setInterval(loadData, 3000),
      setInterval(pollWalkthrough, 1500),
      setInterval(pollSuites, 1500),
    ];

    document.getElementById('pauseBtn').addEventListener('click', () => {
      paused = !paused;
      if (paused) {
        timers.forEach(clearInterval);
        document.getElementById('pauseBtn').textContent = 'Resume';
        document.getElementById('refreshLabel').textContent = 'Auto-refresh: paused';
      } else {
        timers[0] = setInterval(loadData, 3000);
        timers[1] = setInterval(pollWalkthrough, 1500);
        timers[2] = setInterval(pollSuites, 1500);
        document.getElementById('pauseBtn').textContent = 'Pause';
        document.getElementById('refreshLabel').textContent = 'Auto-refresh: 3s';
        loadData();
        pollWalkthrough();
        pollSuites();
      }
    });
  </script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, payload: dict[str, Any], status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, body: str, status: int = 200) -> None:
        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _read_json_body(self) -> dict[str, Any]:
        MAX_BODY = 65_536
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        if length > MAX_BODY:
            raise ValueError(f"Request body too large: {length} bytes (max {MAX_BODY})")
        raw = self.rfile.read(length).decode("utf-8", errors="replace")
        if not raw.strip():
            return {}
        parsed = json.loads(raw)
        if not isinstance(parsed, dict):
            raise ValueError("JSON body must be an object")
        return parsed

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)

        if parsed.path == "/":
            self._send_html(HTML_PAGE)
            return

        if parsed.path == "/api/scenarios":
            try:
                payload = evaluate_scenarios()
                self._send_json(payload)
            except Exception as exc:
                self._send_json({"error": str(exc)}, status=500)
            return

        if parsed.path == "/api/health":
            self._send_json({"status": "ok", "time": datetime.now(timezone.utc).isoformat()})
            return

        if parsed.path == "/api/walkthrough/status":
            self._send_json(get_walkthrough_state())
            return

        if parsed.path == "/api/test-suites/status":
            self._send_json(get_test_suite_status())
            return

        self._send_json({"error": "Not found"}, status=404)

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)

        if parsed.path == "/api/walkthrough/start":
            started, message = start_walkthrough_run()
            if started:
                self._send_json({"started": True, "message": message})
            else:
                self._send_json({"started": False, "message": message}, status=409)
            return

        if parsed.path == "/api/test-suites/run":
            try:
                payload = self._read_json_body()
            except Exception as exc:
                self._send_json({"started": False, "message": f"Invalid JSON body: {exc}"}, status=400)
                return

            suite = str(payload.get("suite", "")).strip()
            if not suite:
                self._send_json({"started": False, "message": "Field 'suite' is required."}, status=400)
                return

            started, message = start_test_suite_run(suite)
            if started:
                self._send_json({"started": True, "suite": suite, "message": message})
            else:
                status_code = 400 if suite not in TEST_SUITES else 409
                self._send_json({"started": False, "suite": suite, "message": message}, status=status_code)
            return

        self._send_json({"error": "Not found"}, status=404)

    def log_message(self, format: str, *args: Any) -> None:
        sys.stdout.write("[dashboard] " + (format % args) + "\n")


def main() -> None:
    try:
        import jwt  # noqa: F401
    except ImportError:
        print("ERROR: PyJWT is not installed. Run: pip install PyJWT")
        sys.exit(1)

    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print("==============================================================")
    print(" PostgREST Demo Dashboard")
    print("==============================================================")
    print(f"URL: http://{HOST}:{PORT}")
    print(f"PostgREST base URL: {BASE_URL}")
    print("Press Ctrl+C to stop.")
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down dashboard server...")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
