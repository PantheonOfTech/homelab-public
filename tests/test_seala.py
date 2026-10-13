"""seala.py: header stamping is idempotent, keeps the shebang on top, and --dry-run writes nothing."""
import pytest

SCRIPT = '#!/usr/bin/env python3\nprint("hi")\n'


@pytest.fixture
def target(tmp_path, monkeypatch):
    monkeypatch.setenv("SEALA_OWNER", "tester")
    path = tmp_path / "t.py"
    path.write_text(SCRIPT, encoding="utf-8")
    return path


def test_stamp_adds_header_below_shebang(seala, target):
    assert seala.main([str(target), "--role", "Test role", "-n", "first"]) in (0, None)
    lines = target.read_text(encoding="utf-8").splitlines()
    assert lines[0] == "#!/usr/bin/env python3"
    assert "#  Role: Test role" in lines
    assert any(line.endswith(" - first") for line in lines)
    assert lines[-1] == 'print("hi")'


def test_restamp_keeps_one_header_and_rolls_changelog(seala, target):
    seala.main([str(target), "--role", "Test role", "-n", "first"])
    seala.main([str(target), "-n", "second"])
    text = target.read_text(encoding="utf-8")
    assert text.count("#  Role: Test role") == 1
    assert text.index(" - second") < text.index(" - first")   # newest first
    assert text.count('print("hi")') == 1


def test_max_changelog_trims_old_entries(seala, target):
    for n in range(4):
        seala.main([str(target), "--max-changelog", "2", "-n", f"entry{n}"])
    text = target.read_text(encoding="utf-8")
    assert " - entry3" in text and " - entry2" in text
    assert " - entry1" not in text and " - entry0" not in text


def test_dry_run_writes_nothing(seala, target):
    seala.main([str(target), "--dry-run", "-n", "nope"])
    assert target.read_text(encoding="utf-8") == SCRIPT
