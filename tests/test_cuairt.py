"""cuairt.py: inventory validation and exit codes. No test touches the network."""
import json
import pathlib

import pytest

EXAMPLE = pathlib.Path(__file__).resolve().parent.parent / "Code" / "JSON" / "cuairt.example.json"


def write_inventory(tmp_path, hosts, **extra):
    path = tmp_path / "cuairt.json"
    path.write_text(json.dumps({"hosts": hosts, **extra}), encoding="utf-8")
    return str(path)


def test_example_inventory_is_valid(cuairt):
    cfg = cuairt.load_config(str(EXAMPLE))
    by_name = {h["name"]: h for h in cfg["hosts"]}
    assert by_name["nas"]["expect"] == "down"
    assert by_name["hypervisor"]["expect"] == "up"          # default filled in
    assert by_name["workstation"]["ports"] == []            # default filled in


@pytest.mark.parametrize("raw, expected", [
    ("00-00-5E-00-53-01", "00:00:5e:00:53:01"),
    ("0:0:5e:0:53:1", "00:00:5e:00:53:01"),
])
def test_norm_mac(cuairt, raw, expected):
    assert cuairt.norm_mac(raw) == expected


@pytest.mark.parametrize("hosts, message", [
    ([], "non-empty 'hosts'"),
    ([{"ip": "192.0.2.1"}], "needs a 'name'"),
    ([{"name": "a"}, {"name": "A"}], "duplicate host name"),
    ([{"name": "a", "ip": "192.0.2.999"}], "not an IP address"),
    ([{"name": "a", "ports": [70000]}], "bad port"),
    ([{"name": "a", "ports": ["22"]}], "bad port"),
    ([{"name": "a", "expect": "maybe"}], "'expect' must be"),
])
def test_bad_inventory_rejected(cuairt, tmp_path, hosts, message):
    with pytest.raises(cuairt.ConfigError, match=message):
        cuairt.load_config(write_inventory(tmp_path, hosts))


def test_missing_inventory_exits_2(cuairt, tmp_path, capsys):
    assert cuairt.main(["-c", str(tmp_path / "nope.json"), "--no-wazuh"]) == 2
    assert "inventory not found" in capsys.readouterr().err


def test_unknown_only_host_exits_2(cuairt, tmp_path, capsys):
    inv = write_inventory(tmp_path, [{"name": "dc", "ip": "192.0.2.60"}])
    assert cuairt.main(["-c", inv, "--only", "ghost", "--no-wazuh"]) == 2
    assert "not in inventory: ghost" in capsys.readouterr().err


def test_parse_neighbours_skips_broadcast_and_multicast(cuairt):
    text = (
        "192.0.2.10 dev eth0 lladdr 00:00:5e:00:53:0a REACHABLE\n"
        "192.0.2.255 dev eth0 lladdr ff:ff:ff:ff:ff:ff PERMANENT\n"
        "  192.0.2.251        01-00-5e-00-00-fb     static\n"
    )
    assert cuairt.parse_neighbours(text) == {"192.0.2.10": "00:00:5e:00:53:0a"}
