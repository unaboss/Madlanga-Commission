from normalize_speakers import normalize_speaker


def test_known_speakers_get_canonical_names_and_roles():
    assert normalize_speaker("CHAIRPERSON") == ("Justice Mbuyiseli Madlanga", "commissioner")
    assert normalize_speaker("ADV SELLO SC") == ("Adv Sello SC", "evidence_leader")
    assert normalize_speaker("LT GEN MKHWANAZI") == ("Lt Gen Nhlanhla Mkhwanazi", "witness")


def test_unknown_speaker_is_title_cased_as_other():
    assert normalize_speaker("MR  NEW   PERSON") == ("Mr New Person", "other")
