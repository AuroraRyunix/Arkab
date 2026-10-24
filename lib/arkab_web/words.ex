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
      read_only_title: "Read-only view",
      read_only:
        "You are looking at this bridge from another computer, so you can see everything and change nothing. To join or leave a server, or to update, open this page on the bridge itself, or from your own computer through an SSH port forward (ssh -L 4050:localhost:4050 <the bridge>, then http://localhost:4050).",
      servers: "Servers",
      connected: "connected",
      not_connected: "not connected",
      remove: "Remove",
      confirm_remove: "Leave this server? It stops getting these boards.",
      no_servers: "Joined to no server yet.",
      waiting: "Events waiting:",
      store_dropped:
        "%{n} events were thrown away because the queue could not be kept (a full disk, or a server that never came back). Remove servers that are gone, and look at the disk.",
      store_error: "The disk refused the last write: %{why}",
      join_title: "Join a server",
      join: "Join",
      joining: "Joining...",
      scan: "Scan",
      joined: "Joined.",
      join_hint:
        "In Alnasl: Halls, your hall, Bridges, \"Add a bridge\". Paste the link it shows here, or press Scan and point the camera at its code; that is all.",
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
      err_elsewhere:
        "This bridge is still in another hall on that server. Remove it there first, then use the link again.",
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
      read_only_pin:
        "If the bridge has a remote PIN, you can unlock this page with it: it then works like the bridge itself for 12 hours, on this browser.",
      enter_pin: "Enter PIN",
      unlock_title: "Unlock this bridge",
      unlock_intro:
        "Enter the bridge's remote PIN. This browser then gets every button for 12 hours.",
      pin_label: "PIN",
      unlock: "Unlock",
      lock_again: "Lock again",
      unlocked_note: "Unlocked with the PIN, for 12 hours at most.",
      pin_wrong: "That is not the PIN.",
      pin_locked: "Too many wrong tries. Try again in %{minutes} minutes.",
      pin_none:
        "This bridge has no remote PIN, so it can only be changed from the bridge itself.",
      pin_plain:
        "The page runs on plain HTTP: the PIN crosses the hall's network in clear. It keeps a curious guest out of the buttons; it is not security against the internet.",
      pin_title: "Remote PIN",
      pin_is_set: "A remote PIN is set.",
      pin_is_not_set: "No remote PIN: from another computer this page is read-only.",
      pin_new: "New PIN (at least 4 characters)",
      pin_save: "Save PIN",
      pin_remove: "Remove PIN",
      pin_saved: "PIN saved. Browsers that were unlocked are locked again.",
      pin_removed: "PIN removed. Browsers that were unlocked are locked again.",
      pin_short: "A PIN needs at least 4 characters.",
      pin_hint:
        "With a PIN, a phone or laptop on the hall's network can unlock this page. Setting, changing or removing the PIN works on the bridge itself only.",
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
      read_only_title: "Alleen-lezen weergave",
      read_only:
        "Je kijkt vanaf een andere computer naar deze brug: je ziet alles, maar kunt niets wijzigen. Om aan te sluiten bij een server, een server te verlaten of bij te werken open je deze pagina op de brug zelf, of vanaf je eigen computer via een SSH-poortdoorverwijzing (ssh -L 4050:localhost:4050 <de brug>, daarna http://localhost:4050).",
      servers: "Servers",
      connected: "verbonden",
      not_connected: "niet verbonden",
      remove: "Verwijderen",
      confirm_remove: "Deze server verlaten? Hij krijgt deze borden dan niet meer.",
      no_servers: "Nog bij geen enkele server aangesloten.",
      waiting: "Gebeurtenissen in de wachtrij:",
      store_dropped:
        "%{n} gebeurtenissen zijn weggegooid omdat de wachtrij niet bewaard kon blijven (een volle schijf, of een server die nooit meer terugkwam). Verwijder servers die weg zijn, en kijk naar de schijf.",
      store_error: "De schijf weigerde het laatste schrijven: %{why}",
      join_title: "Aansluiten bij een server",
      join: "Aansluiten",
      joining: "Aansluiten...",
      scan: "Scannen",
      joined: "Aangesloten.",
      join_hint:
        "In Alnasl: Zalen, je zaal, Bruggen, \"Een brug toevoegen\". Plak de link die verschijnt hier, of druk op Scannen en richt de camera op de code; meer is het niet.",
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
      err_elsewhere:
        "Deze brug zit nog in een andere zaal op die server. Haal hem daar eerst weg en gebruik de link dan opnieuw.",
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
      read_only_pin:
        "Heeft de brug een pincode voor op afstand, dan kun je deze pagina daarmee ontgrendelen: ze werkt dan 12 uur lang, in deze browser, als de brug zelf.",
      enter_pin: "Pincode invoeren",
      unlock_title: "Deze brug ontgrendelen",
      unlock_intro:
        "Voer de pincode van de brug in. Deze browser krijgt dan 12 uur lang alle knoppen.",
      pin_label: "Pincode",
      unlock: "Ontgrendelen",
      lock_again: "Weer vergrendelen",
      unlocked_note: "Ontgrendeld met de pincode, hooguit 12 uur.",
      pin_wrong: "Dat is de pincode niet.",
      pin_locked: "Te veel foute pogingen. Probeer het over %{minutes} minuten opnieuw.",
      pin_none:
        "Deze brug heeft geen pincode voor op afstand, dus je kunt hem alleen vanaf de brug zelf wijzigen.",
      pin_plain:
        "De pagina draait op gewoon HTTP: de pincode gaat onversleuteld over het netwerk van de zaal. Hij houdt een nieuwsgierige gast van de knoppen af; het is geen beveiliging tegen het internet.",
      pin_title: "Pincode voor op afstand",
      pin_is_set: "Er is een pincode voor op afstand ingesteld.",
      pin_is_not_set: "Geen pincode: vanaf een andere computer is deze pagina alleen-lezen.",
      pin_new: "Nieuwe pincode (minstens 4 tekens)",
      pin_save: "Pincode opslaan",
      pin_remove: "Pincode verwijderen",
      pin_saved: "Pincode opgeslagen. Ontgrendelde browsers zijn weer vergrendeld.",
      pin_removed: "Pincode verwijderd. Ontgrendelde browsers zijn weer vergrendeld.",
      pin_short: "Een pincode heeft minstens 4 tekens nodig.",
      pin_hint:
        "Met een pincode kan een telefoon of laptop op het netwerk van de zaal deze pagina ontgrendelen. De pincode instellen, wijzigen of verwijderen kan alleen op de brug zelf.",
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
