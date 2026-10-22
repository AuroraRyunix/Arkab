# Every entry says why. A new finding is not added here by reflex.
[
  # Mint.WebSocket.new/4's own spec and success typing leave only the {:error, ...}
  # branch for our arguments (the same happens with a literal 101), so the
  # {:ok, ...} clause "can never match". It does match, on every upgrade that
  # works; the tests open a real socket. A false positive from the dependency's typing.
  {"lib/arkab/bridge/link.ex", :pattern_match}
]
