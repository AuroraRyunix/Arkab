defmodule ArkabWeb.Words do
  @moduledoc """
  The page's words, in English and Dutch. Two languages and about thirty
  strings do not need gettext, which would be a dependency, a build step and
  four files for the bridge's one page; a map does. `t/2` falls back to
  English for a key the language lacks, and a test makes sure none does.

  The language is the visitor's: a cookie set by `/lang/nl` or `/lang/en`
  (the links at the foot of the page), or, until they choose, what the
  browser asks for (`ArkabWeb.Locale`).
  """

  @locales ~w(en nl)

  @words %{
    "en" => %{
      tagline: "Reads the boards in this hall and sends them on.",
      servers: "Servers",
      connected: "connected",
      not_connected: "not connected",
      remove: "Remove",
      confirm_remove: "Leave this server? It stops getting these boards.",
      no_servers: "Joined to no server yet.",
      waiting: "Events waiting:",
      join_title: "Join a server",
      join: "Join",
      joining: "Joining...",
      scan: "Scan",
      joined: "Joined.",
      join_hint:
        "On the server: Halls, Add a bridge. Paste or scan the link it shows; that is all.",
      ports_title: "Ports and boards",
      no_ports: "No ports.",
      not_read: "(not read)",
      board: "Board",
      board_no: "Board no. %{n}",
      serial: "serial",
      recording: "Recording:",
      on: "on",
      off: "off",
      help: "Help",
      back: "Back to the bridge",
      language: "Language",
      err_not_a_link: "That is not a join link. It looks like https://server/join/K7Q-4MD.",
      err_used_or_expired: "That link is used up or expired. Ask the server for a new one.",
      err_unreachable: "The server in that link does not answer from here.",
      err_version: "That server speaks another version of the link. Update one of the two.",
      err_other: "That address answered, but not like a server.",
      update_available: "Arkab %{version} is out.",
      update_size: "The download is %{mb} MB.",
      update_cost: "The boards are not read for about a minute while it installs.",
      update_install: "Download and install",
      update_later: "Later",
      update_manual: "This copy is updated by hand: download the new one and replace this.",
      update_releases: "Releases",
      update_started: "Updating. This page reconnects when the bridge is back.",
      update_no_build: "There is no build for this machine.",
      update_failed: "The last update, to %{version}, did not work: %{why}",
      program_title: "This program",
      version: "Version",
      update_check: "Look for a newer version now and then",
      check_now: "Look now",
      checking: "Looking...",
      up_to_date: "This is the newest version.",
      check_failed: "Could not reach the release page.",
      autostart: "Start Arkab when Windows starts",
      autostart_failed: "Windows would not take that setting."
    },
    "nl" => %{
      tagline: "Leest de borden in deze zaal en stuurt ze door.",
      servers: "Servers",
      connected: "verbonden",
      not_connected: "niet verbonden",
      remove: "Verwijderen",
      confirm_remove: "Deze server verlaten? Hij krijgt deze borden dan niet meer.",
      no_servers: "Nog bij geen enkele server aangesloten.",
      waiting: "Gebeurtenissen in de wachtrij:",
      join_title: "Aansluiten bij een server",
      join: "Aansluiten",
      joining: "Aansluiten...",
      scan: "Scannen",
      joined: "Aangesloten.",
      join_hint:
        "Op de server: Zalen, Een brug toevoegen. Plak of scan de link die verschijnt; meer is het niet.",
      ports_title: "Poorten en borden",
      no_ports: "Geen poorten.",
      not_read: "(wordt niet gelezen)",
      board: "Bord",
      board_no: "Bord nr. %{n}",
      serial: "serienummer",
      recording: "Opnemen:",
      on: "aan",
      off: "uit",
      help: "Help",
      back: "Terug naar de brug",
      language: "Taal",
      err_not_a_link:
        "Dat is geen aansluitlink. Zo'n link ziet eruit als https://server/join/K7Q-4MD.",
      err_used_or_expired: "Die link is al gebruikt of verlopen. Vraag de server om een nieuwe.",
      err_unreachable: "De server in die link antwoordt niet vanaf hier.",
      err_version: "Die server spreekt een andere versie van de link. Werk een van de twee bij.",
      err_other: "Dat adres antwoordde, maar niet als een server.",
      update_available: "Arkab %{version} is uit.",
      update_size: "De download is %{mb} MB.",
      update_cost: "De borden worden ongeveer een minuut niet gelezen terwijl het installeert.",
      update_install: "Downloaden en installeren",
      update_later: "Later",
      update_manual: "Deze kopie werk je met de hand bij: download de nieuwe en vervang deze.",
      update_releases: "Uitgaven",
      update_started: "Bijwerken. Deze pagina verbindt opnieuw zodra de brug terug is.",
      update_no_build: "Voor deze machine bestaat geen versie.",
      update_failed: "De laatste update, naar %{version}, is mislukt: %{why}",
      program_title: "Dit programma",
      version: "Versie",
      update_check: "Af en toe naar een nieuwere versie kijken",
      check_now: "Nu kijken",
      checking: "Kijken...",
      up_to_date: "Dit is de nieuwste versie.",
      check_failed: "De uitgavenpagina is niet te bereiken.",
      autostart: "Arkab starten als Windows start",
      autostart_failed: "Windows wilde die instelling niet aannemen."
    }
  }

  def locales, do: @locales

  @doc "The word for `key` in `locale`, English if the language lacks it."
  def t(locale, key, bindings \\ []) do
    text = get_in(@words, [locale, key]) || @words["en"][key]

    Enum.reduce(bindings, text, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
  end

  @doc "Every key of English, for the test that checks Dutch has them all."
  def keys(locale), do: @words |> Map.fetch!(locale) |> Map.keys() |> Enum.sort()
end
