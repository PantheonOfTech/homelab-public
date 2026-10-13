#!/usr/bin/env python3
# ================================================================
#  cuairt.py
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Suite: Cuairt (Irish: round, patrol)
#  Role: Read-only lab sweep: ping, ports, Wazuh agent state
#  Runs: On demand, or scheduled (exit code 1 = attention needed)
#  Created: 2026-10-08
#  Last Modified: 2026-10-12 17:30 CDT
#  Changelog (newest first):
#    2026-10-12 17:30 CDT - v1.0.1: lint pass (exception chaining, explicit subprocess check, f-strings); no behaviour change
#    2026-10-08 16:10 CDT - Initial version (v1.0)
# ================================================================

"""Cuairt - read-only lab sweep: is every node up, are its ports open, what does Wazuh say.

For each host in the inventory: one ping plus a TCP connect to each listed port.
Then, optionally, the Wazuh manager API is asked for agent state. Nothing is
changed anywhere; the only traffic is ICMP echo, TCP connects and two HTTPS
requests to the Wazuh API.

  cuairt.py                    sweep the inventory, print a table
  cuairt.py --csv sweep.csv    also write the host rows to CSV
  cuairt.py --json             machine-readable output (for n8n and friends)
  cuairt.py --discover         also ping the whole subnet and list every device
                               that answers, flagging ones not in the inventory
  cuairt.py --no-wazuh         skip the Wazuh API

Inventory: cuairt.json next to this script, or --config PATH. It holds real
addresses, so keep it out of git; cuairt.example.json is the public template.

Wazuh credentials are never read from the inventory. Set CUAIRT_WAZUH_USER and
CUAIRT_WAZUH_PASS, or run interactively and you will be prompted.

Exit code: 0 all as expected, 1 something is DOWN / WARN / CHANGED or the Wazuh
API call failed, 2 bad config.
Standard library only. Python 3.8+.
"""

import argparse
import base64
import csv
import getpass
import hashlib
import http.client
import ipaddress
import json
import os
import platform
import re
import shutil
import socket
import ssl
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from urllib.parse import urlsplit

IS_WINDOWS = platform.system() == "Windows"
HAVE_PING = shutil.which("ping") is not None
RX_NEIGH = re.compile(r"(\d{1,3}(?:\.\d{1,3}){3})\D.*?\b((?:[0-9A-Fa-f]{1,2}[:-]){5}[0-9A-Fa-f]{1,2})\b")


class ConfigError(Exception):
    pass


# ---------------------------------------------------------------- inventory

def load_config(path):
    try:
        with open(path, encoding="utf-8") as fh:
            cfg = json.load(fh)
    except FileNotFoundError:
        raise ConfigError(f"inventory not found: {path} (copy cuairt.example.json to cuairt.json)") from None
    except json.JSONDecodeError as err:
        raise ConfigError(f"inventory is not valid JSON: {path} ({err})") from err

    hosts = cfg.get("hosts")
    if not isinstance(hosts, list) or not hosts:
        raise ConfigError("inventory needs a non-empty 'hosts' list")
    seen = set()
    for host in hosts:
        name = host.get("name")
        if not name:
            raise ConfigError("every host needs a 'name'")
        if name.lower() in seen:
            raise ConfigError("duplicate host name: " + name)
        seen.add(name.lower())
        if host.get("ip"):
            try:
                ipaddress.ip_address(host["ip"])
            except ValueError as err:
                raise ConfigError("{}: not an IP address: {}".format(name, host["ip"])) from err
        host.setdefault("ports", [])
        for port in host["ports"]:
            if not isinstance(port, int) or not 0 < port < 65536:
                raise ConfigError(f"{name}: bad port: {port!r}")
        host.setdefault("expect", "up")
        if host["expect"] not in ("up", "down"):
            raise ConfigError(f"{name}: 'expect' must be \"up\" or \"down\"")
        if host.get("mac"):
            host["mac"] = norm_mac(host["mac"])
    return cfg


def norm_mac(mac):
    parts = re.split(r"[:-]", mac.strip())
    return ":".join(p.zfill(2).lower() for p in parts)


# ------------------------------------------------------------------- probes

def ping(ip, timeout):
    """True / False, or None when this machine has no ping command."""
    if not HAVE_PING:
        return None
    if IS_WINDOWS:
        cmd = ["ping", "-n", "1", "-w", str(int(timeout * 1000)), ip]
    elif platform.system() == "Darwin":
        cmd = ["ping", "-c", "1", "-W", str(int(timeout * 1000)), ip]
    else:
        cmd = ["ping", "-c", "1", "-W", str(max(1, int(round(timeout)))), ip]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout + 3, check=False)
    except (OSError, subprocess.SubprocessError):
        return False
    if IS_WINDOWS:
        # Windows returns 0 for "Destination host unreachable"; a real reply has a TTL.
        return out.returncode == 0 and "TTL=" in out.stdout.upper()
    return out.returncode == 0


def port_open(ip, port, timeout):
    try:
        with socket.create_connection((ip, port), timeout=timeout):
            return True
    except OSError:
        return False


def check_host(host, timeout):
    row = {
        "name": host["name"], "role": host.get("role", ""), "ip": host.get("ip") or "",
        "expect": host["expect"], "ping": "", "open": [], "closed": [], "status": "", "note": "",
    }
    ip = host.get("ip")
    if not ip:
        row["status"] = "NO IP"
        row["note"] = "no address in inventory"
        return row

    alive = ping(ip, timeout)
    row["ping"] = {True: "ok", False: "no", None: "n/a"}[alive]
    for port in host["ports"]:
        (row["open"] if port_open(ip, port, timeout) else row["closed"]).append(port)
    reachable = bool(alive) or bool(row["open"])

    if host["expect"] == "down":
        if reachable:
            row["status"], row["note"] = "CHANGED", "expected down, but it answers"
        else:
            row["status"] = "down (expected)"
    elif not reachable:
        row["status"] = "DOWN"
        if alive is None and not host["ports"]:
            row["note"] = "no ping command here and no ports listed, so nothing was tested"
    elif row["closed"]:
        row["status"] = "WARN"
        row["note"] = "closed: " + ",".join(map(str, row["closed"]))
    else:
        row["status"] = "OK"
    return row


# -------------------------------------------------------------------- wazuh

def wazuh_agents(wz, user, password, timeout):
    """Returns (agents, notes). Raises RuntimeError with a readable message."""
    notes = []
    url = urlsplit(wz["url"])
    host, port = url.hostname, url.port or 55000

    if url.scheme == "http":
        conn = http.client.HTTPConnection(host, port, timeout=timeout)
        notes.append("Wazuh API over plain HTTP: credentials are sent unencrypted")
    else:
        pin = (wz.get("cert_sha256") or "").replace(":", "").lower()
        if wz.get("ca_file"):
            ctx = ssl.create_default_context(cafile=wz["ca_file"])
        elif pin or wz.get("verify_tls") is False:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
        else:
            ctx = ssl.create_default_context()
        conn = http.client.HTTPSConnection(host, port, timeout=timeout, context=ctx)
        try:
            conn.connect()
        except ssl.SSLCertVerificationError as err:
            raise RuntimeError(
                f"TLS certificate not trusted ({err.verify_message}). Set wazuh.cert_sha256 (pin), wazuh.ca_file, "
                "or wazuh.verify_tls=false in the inventory.") from err
        except OSError as err:
            raise RuntimeError(f"cannot reach {host}:{port} ({err})") from err
        seen = hashlib.sha256(conn.sock.getpeercert(binary_form=True)).hexdigest()
        if pin:
            if seen != pin:
                conn.close()
                raise RuntimeError(
                    "certificate does NOT match the pinned cert_sha256; no credentials were sent. "
                    "Presented: " + seen)
        elif not wz.get("ca_file") and wz.get("verify_tls") is False:
            notes.append("Wazuh TLS not verified. To pin this certificate add to the inventory: "
                         f"\"cert_sha256\": \"{seen}\"")

    def call(method, path, headers):
        try:
            conn.request(method, path, headers=headers)
            resp = conn.getresponse()
            body = resp.read()
        except OSError as err:
            raise RuntimeError(f"request failed: {method} {path} ({err})") from err
        if resp.status == 401:
            raise RuntimeError("Wazuh API rejected the credentials (401)")
        if resp.status != 200:
            raise RuntimeError(f"Wazuh API returned {resp.status} for {path}")
        try:
            return json.loads(body)
        except ValueError as err:
            raise RuntimeError("Wazuh API sent a non-JSON reply for " + path) from err

    try:
        basic = base64.b64encode(f"{user}:{password}".encode()).decode()
        token = call("POST", "/security/user/authenticate", {"Authorization": "Basic " + basic})["data"]["token"]
        data = call("GET", "/agents?select=id,name,ip,status,lastKeepAlive,version&limit=500&sort=+id",
                    {"Authorization": "Bearer " + token})
        items = data["data"]["affected_items"]
    except (KeyError, TypeError) as err:
        raise RuntimeError("Wazuh API reply was not in the expected shape") from err
    finally:
        conn.close()

    agents = [{
        "id": a.get("id", ""), "name": a.get("name", ""), "status": a.get("status", ""),
        "ip": a.get("ip", ""), "last_keepalive": a.get("lastKeepAlive", ""), "version": a.get("version", ""),
    } for a in items]
    return agents, notes


def wazuh_credentials():
    user, password = os.environ.get("CUAIRT_WAZUH_USER"), os.environ.get("CUAIRT_WAZUH_PASS")
    if user and password:
        return user, password
    if sys.stdin.isatty() and sys.stderr.isatty():
        user = user or input("Wazuh API user: ").strip()
        password = getpass.getpass("Wazuh API password: ")
        if user and password:
            return user, password
    return None


# ---------------------------------------------------------------- discovery

def neighbour_table():
    """ip -> mac from the OS neighbour cache. Never raises."""
    text = ""
    try:
        with open("/proc/net/arp", encoding="ascii", errors="replace") as fh:
            text = fh.read()
    except OSError:
        for cmd in (["arp", "-a"], ["ip", "neigh"]):
            if shutil.which(cmd[0]):
                try:
                    text = subprocess.run(cmd, capture_output=True, text=True, timeout=10, check=False).stdout
                    break
                except (OSError, subprocess.SubprocessError):
                    pass
    return parse_neighbours(text)


def parse_neighbours(text):
    table = {}
    for line in text.splitlines():
        m = RX_NEIGH.search(line)
        if not m:
            continue
        mac = norm_mac(m.group(2))
        if mac in ("00:00:00:00:00:00", "ff:ff:ff:ff:ff:ff") or mac.startswith("01:00:5e"):
            continue
        table[m.group(1)] = mac
    return table


def discover(cfg, timeout):
    """Ping every address in the subnet; return rows for everything that answers or is cached."""
    try:
        net = ipaddress.ip_network(cfg.get("subnet", ""), strict=False)
    except ValueError as err:
        raise ConfigError("--discover needs a valid 'subnet' in the inventory, e.g. \"192.0.2.0/24\"") from err
    if not net.is_private and not net.is_link_local:
        raise ConfigError("--discover only runs on private address space, not " + str(net))
    if net.num_addresses > 1024:
        raise ConfigError("--discover is limited to a /22 or smaller, not " + str(net))

    addrs = [str(a) for a in net.hosts()]
    with ThreadPoolExecutor(max_workers=64) as pool:
        answered = {ip for ip, ok in zip(addrs, pool.map(lambda a: ping(a, timeout), addrs)) if ok}
    neigh = {ip: mac for ip, mac in neighbour_table().items() if ipaddress.ip_address(ip) in net}

    by_ip = {h["ip"]: h["name"] for h in cfg["hosts"] if h.get("ip")}
    by_mac = {h["mac"]: h["name"] for h in cfg["hosts"] if h.get("mac")}
    rows = []
    for ip in sorted(answered | set(neigh), key=ipaddress.ip_address):
        mac = neigh.get(ip, "")
        name = by_ip.get(ip) or by_mac.get(mac) or ""
        note = ""
        if not name:
            note = "NOT IN INVENTORY"
        elif ip not in by_ip:
            note = "matched by MAC: put this IP in the inventory"
        elif mac and mac in by_mac and by_mac[mac] != name:
            note = f"MAC belongs to {by_mac[mac]} in the inventory"
        rows.append({"ip": ip, "mac": mac, "ping": "ok" if ip in answered else "no", "name": name, "note": note})
    return rows


# ------------------------------------------------------------------- output

def table(rows, columns):
    if not rows:
        return "  (none)"
    cells = [[str(r.get(key, "")) for key, _ in columns] for r in rows]
    widths = [max(len(title), *(len(c[i]) for c in cells)) for i, (_, title) in enumerate(columns)]

    def line(vals):
        return "  " + "  ".join(v.ljust(w) for v, w in zip(vals, widths)).rstrip()

    out = [line([t for _, t in columns]), line(["-" * w for w in widths])]
    out.extend(line(c) for c in cells)
    return "\n".join(out)


def now_stamp():
    now = datetime.now().astimezone()
    name = now.tzname() or ""
    abbr = "".join(w[0] for w in name.split()) if " " in name else name
    return f"{now:%Y-%m-%d %H:%M:%S} {abbr.upper()}".rstrip()


def main(argv=None):
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(prog="cuairt", description="Read-only lab sweep: ping, ports, Wazuh agent state.")
    ap.add_argument("-c", "--config", default=os.path.join(here, "cuairt.json"), help="inventory file (default: cuairt.json next to this script)")
    ap.add_argument("-t", "--timeout", type=float, help="seconds per ping / port (default: inventory 'timeout' or 1.0)")
    ap.add_argument("--only", metavar="NAME", action="append", help="check only this host (repeatable)")
    ap.add_argument("--discover", action="store_true", help="also ping the whole subnet and list every device found")
    ap.add_argument("--no-wazuh", action="store_true", help="skip the Wazuh API")
    ap.add_argument("--csv", metavar="FILE", help="also write the host rows to this CSV file")
    ap.add_argument("--json", action="store_true", help="print JSON instead of tables")
    args = ap.parse_args(argv)

    try:
        cfg = load_config(args.config)
        timeout = args.timeout or float(cfg.get("timeout", 1.0))
        if timeout <= 0:
            raise ConfigError("timeout must be greater than 0")
        hosts = cfg["hosts"]
        if args.only:
            want = {n.lower() for n in args.only}
            hosts = [h for h in hosts if h["name"].lower() in want]
            missing = want - {h["name"].lower() for h in hosts}
            if missing:
                raise ConfigError("not in inventory: " + ", ".join(sorted(missing)))

        notes = []
        if not HAVE_PING:
            notes.append("no ping command on this machine: hosts are judged by their TCP ports only")

        with ThreadPoolExecutor(max_workers=32) as pool:
            rows = list(pool.map(lambda h: check_host(h, timeout), hosts))

        found = discover(cfg, timeout) if args.discover else None
        if args.discover and not HAVE_PING:
            notes.append("--discover without ping only shows what the OS already had cached")
    except ConfigError as err:
        print("cuairt: " + str(err), file=sys.stderr)
        return 2

    agents, wazuh_state = None, "skipped (--no-wazuh)"
    wz = cfg.get("wazuh") or {}
    if not args.no_wazuh:
        if not wz.get("url"):
            wazuh_state = "skipped (no wazuh.url in inventory)"
        else:
            creds = wazuh_credentials()
            if not creds:
                wazuh_state = "skipped (set CUAIRT_WAZUH_USER and CUAIRT_WAZUH_PASS)"
            else:
                try:
                    agents, wz_notes = wazuh_agents(wz, creds[0], creds[1], max(timeout, 5.0))
                    notes.extend(wz_notes)
                    wazuh_state = "ok"
                except RuntimeError as err:
                    wazuh_state = "FAILED: " + str(err)

    # Join Wazuh onto the host rows; let agent-reported IPs fill inventory gaps.
    by_agent = {a["name"].lower(): a for a in agents or []}
    for host, row in zip(hosts, rows):
        agent = by_agent.get((host.get("agent") or host["name"]).lower())
        row["wazuh"] = agent["status"] if agent else ("-" if agents is not None else "")
        if agent and not row["ip"] and agent["ip"] not in ("", "any"):
            row["note"] = "Wazuh agent reports " + agent["ip"]
    known = {(h.get("agent") or h["name"]).lower() for h in cfg["hosts"]}

    bad = [r for r in rows if r["status"] in ("DOWN", "WARN", "CHANGED")]
    failed = bool(bad) or wazuh_state.startswith("FAILED")
    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8") as fh:
            writer = csv.writer(fh)
            writer.writerow(["timestamp", "name", "role", "ip", "expect", "status", "ping", "open", "closed", "wazuh", "note"])
            stamp = now_stamp()
            for r in rows:
                writer.writerow([stamp, r["name"], r["role"], r["ip"], r["expect"], r["status"], r["ping"],
                                 " ".join(map(str, r["open"])), " ".join(map(str, r["closed"])), r["wazuh"], r["note"]])

    if args.json:
        json.dump({"timestamp": now_stamp(), "ok": not failed, "hosts": rows, "wazuh": wazuh_state,
                   "agents": agents, "discovered": found, "notes": notes}, sys.stdout, indent=2)
        print()
        return 1 if failed else 0

    print(f"Cuairt sweep  {now_stamp()}  from {socket.gethostname()}")
    print()
    for r in rows:
        r["ports"] = " ".join(map(str, r["open"])) or ("-" if not r["closed"] else "none")
    print(table(rows, [("name", "HOST"), ("ip", "IP"), ("status", "STATUS"), ("ping", "PING"),
                       ("ports", "OPEN"), ("wazuh", "WAZUH"), ("note", "NOTE")]))
    print()
    print("Wazuh agents: " + wazuh_state)
    if agents is not None:
        for a in agents:
            a["note"] = "" if a["name"].lower() in known or a["id"] == "000" else "not in inventory"
        print(table(agents, [("id", "ID"), ("name", "NAME"), ("status", "STATUS"), ("ip", "IP"),
                             ("last_keepalive", "LAST KEEPALIVE"), ("version", "VERSION"), ("note", "NOTE")]))
    if found is not None:
        print()
        print("Discovered on {}:".format(cfg.get("subnet")))
        print(table(found, [("ip", "IP"), ("mac", "MAC"), ("ping", "PING"), ("name", "KNOWN AS"), ("note", "NOTE")]))
    for note in notes:
        print()
        print("note: " + note)
    print()
    print("{} hosts checked, {} need attention{}".format(
        len(rows), len(bad), ": " + ", ".join(r["name"] for r in bad) if bad else ""))
    if args.csv:
        print("CSV written: " + args.csv)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
