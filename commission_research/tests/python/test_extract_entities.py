from extract_entities import extract_entities


def values(text, etype):
    return {e["value"] for e in extract_entities(text) if e["type"] == etype}


def test_organisations_and_locations():
    text = "Crime Intelligence officers met the Hawks in Pretoria."
    assert {"Crime Intelligence", "HAWKS"} <= values(text, "organization")
    assert values(text, "location") == {"Pretoria"}


def test_money_and_exhibits():
    text = "He was paid R5 million, see Exhibit MK12 and Annexure B."
    assert values(text, "money") == {"R5 million"}
    assert {"MK12", "Annexure B"} <= values(text, "exhibit")
