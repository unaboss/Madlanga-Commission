import json

import pytest

import inquiry_config as ic


def write_inquiry(tmp_path, **overrides):
    cfg = {
        "id": "test",
        "short_name": "Test Inquiry",
        "jurisdiction_pack": "za",
        "source_dir": str(tmp_path / "downloads"),
        "focus_person": {"match": "Smith", "legend": "Smith (focus)"},
        "speaker_rules": [
            ["^CHAIR$", "Judge Jones", "commissioner"],
            ["^WITNESS\\s+([A-Z])\\b", "Witness {1} (protected)", "witness_protected"],
        ],
    }
    cfg.update(overrides)
    path = tmp_path / "inquiry.json"
    path.write_text(json.dumps(cfg))
    return path


@pytest.fixture
def use_config(monkeypatch):
    def use(path):
        monkeypatch.setenv("INQUIRY_CONFIG", str(path))
    yield use
    ic._load.cache_clear()
    ic._speaker_rules.cache_clear()


def test_default_config_is_madlanga():
    inq = ic.load_inquiry()
    assert inq["id"] == "madlanga"
    assert inq["pack"]["id"] == "za"
    assert ic.is_focus("Lt Gen Nhlanhla Mkhwanazi")
    assert not ic.is_focus("Lt Gen Khumalo")


def test_another_inquiry_changes_speakers_focus_and_source(tmp_path, use_config):
    use_config(write_inquiry(tmp_path))
    from normalize_speakers import normalize_speaker
    assert normalize_speaker("CHAIR") == ("Judge Jones", "commissioner")
    assert normalize_speaker("WITNESS Q") == ("Witness Q (protected)", "witness_protected")
    assert normalize_speaker("CHAIRPERSON") == ("Chairperson", "other")
    assert ic.is_focus("Mr Smith") and not ic.is_focus("Lt Gen Mkhwanazi")
    assert ic.source_dir() == tmp_path / "downloads"


def test_app_settings_are_written_for_the_dashboard(tmp_path, use_config):
    use_config(write_inquiry(tmp_path, contact={"name": "Ops", "email": "ops@example.com"}))
    out = ic.write_app_config(tmp_path / "app_inquiry.json")
    cfg = json.loads(out.read_text())
    assert cfg["short_name"] == "Test Inquiry"
    assert cfg["focus_person"]["match"] == "Smith"
    assert "speaker_rules" not in cfg


@pytest.mark.parametrize("overrides, message", [
    ({"short_name": ""}, "short_name"),
    ({"speaker_rules": [["^X$", "X"]]}, "speaker_rules\\[0\\]"),
    ({"speaker_rules": [["^X$", "X", "judge"]]}, "role 'judge'"),
    ({"speaker_rules": [["^(X$", "X", "witness"]]}, "Bad regex"),
    ({"exhibit_patterns": ["(unclosed"]}, "Bad regex"),
])
def test_bad_configs_fail_with_a_clear_message(tmp_path, use_config, overrides, message):
    use_config(write_inquiry(tmp_path, **overrides))
    with pytest.raises(ic.InquiryConfigError, match=message):
        ic.load_inquiry()


def test_missing_pack_is_reported(tmp_path, use_config):
    use_config(write_inquiry(tmp_path, jurisdiction_pack="xx"))
    with pytest.raises(ic.InquiryConfigError, match="xx.json"):
        ic.load_inquiry()


def test_committed_app_settings_match_the_madlanga_config(tmp_path):
    expected = json.loads(ic.write_app_config(tmp_path / "fresh.json").read_text())
    assert json.loads(ic.APP_CONFIG.read_text()) == expected
