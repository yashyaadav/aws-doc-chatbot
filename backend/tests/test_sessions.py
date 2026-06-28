from app.sessions import InMemoryStore


def test_inmemory_roundtrip_and_isolation():
    store = InMemoryStore()
    assert store.get("a") == []

    store.put("a", [{"role": "user", "content": [{"text": "hi"}]}])
    assert store.get("a") == [{"role": "user", "content": [{"text": "hi"}]}]

    # get() returns a copy — mutating it must not corrupt stored state
    store.get("a").append("junk")
    assert len(store.get("a")) == 1
