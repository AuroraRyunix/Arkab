defmodule ArkabWeb.HelpLive do
  @moduledoc """
  The bridge's short help, at `/help`, in English and Dutch: what Arkab is,
  how to join a server, what the page shows, and what to do when a server is
  red. Nothing is read from the bridge: it is text, and it stays right when
  the bridge itself is the thing that is wrong.

  The same family as the manual of Alnasl (`/help` there), at the size of
  this page: one screen of sections, no search, no chapters.
  """

  use ArkabWeb, :live_view

  import ArkabWeb.Components, only: [foot: 1, logo: 1]

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(%{locale: "nl"} = assigns) do
    ~H"""
    <main id="help">
      <header>
        <h1><.logo /> Arkab <span class="name">Help</span></h1>

        <p class="note">Een korte handleiding voor de brug in je zaal.</p>
      </header>

      <section id="help-what">
        <h2>Wat Arkab is</h2>

        <p>
          Arkab is de brug: een klein programma op een computer naast de elektronische borden (vaak een Raspberry Pi). Het leest de borden en stuurt ze via internet door naar één of meer Alnasl-servers, waar de partijen gevolgd, hersteld en doorgegeven worden. Wie tegen wie speelt en wat de uitslag is, beslis je daar, niet hier.
        </p>

        <p>
          De brug belt zelf naar de server. In het netwerk van de zaal hoeft niets open te staan.
        </p>
      </section>

      <section id="help-join">
        <h2>Aansluiten bij een server</h2>

        <ol>
          <li>
            Open in Alnasl Zalen, dan je zaal, dan het tabblad Bruggen, en druk op "Een brug toevoegen". (De Installatiewizard van Alnasl, het eerste onderdeel van Instellingen, leidt er ook heen.) Er verschijnt een link met een QR-code, goed voor één brug en vijftien minuten.
          </li>

          <li>
            Plak de link in het veld "Aansluiten bij een server" op deze pagina, of druk op "Scannen" en richt de camera op de QR-code (de knop is er alleen als de browser dat kan).
          </li>

          <li>
            Druk op "Aansluiten". Staat er "Aangesloten.", dan is het klaar: de server staat in de lijst.
          </li>
        </ol>

        <p>
          Een sleutel hoef je nooit te zien of te typen; de brug haalt hem zelf op. Is de link verlopen of al gebruikt, vraag de server dan om een nieuwe.
        </p>

        <p>
          Eén brug kan bij meer dan één server horen, bijvoorbeeld het kastje van de club en de gehoste server. Sluit gewoon nog eens aan met de link van de volgende.
        </p>
      </section>

      <section id="help-servers">
        <h2>De lijst van servers</h2>

        <p>
          Elke server heeft een stip: <span class="dot up"></span>
          groen is verbonden, <span class="dot down"></span>
          rood is niet verbonden. Naast een rode stip staat meestal waarom.
        </p>

        <p>
          "Verwijderen" verlaat een server. Het beëindigt de verbinding hier en op de server zelf, en de borden van deze brug verdwijnen daar. Je kunt later opnieuw aansluiten met een nieuwe link; de brug komt dan terug als dezelfde brug.
        </p>
      </section>

      <section id="help-queue">
        <h2>Gebeurtenissen in de wachtrij</h2>

        <p>
          Alles wat de borden zeggen, gaat eerst in een wachtrij op de schijf van de brug en pas daarna naar de servers. Het getal bij "Gebeurtenissen in de wachtrij" is wat nog door geen enkele server bevestigd is. Het loopt even op en zakt weer; gaat het steeds hoger, dan bereikt minstens één server de brug niet.
        </p>
      </section>

      <section id="help-ports">
        <h2>Poorten en borden</h2>

        <p>
          Onder "Poorten en borden" staan de seriële poorten die de brug ziet, met de borden die erop antwoorden: een groene stip voor een bord dat antwoordt, een rode voor een bord dat niet antwoordt. "(wordt niet gelezen)" betekent dat de brug die poort niet leest; een server kan de brug vragen haar te lezen. Welke poort bij welk bord hoort en welke tafelnummers ze krijgen, regel je op de server, niet hier.
        </p>

        <p>
          "Opnemen" zegt of de brug alles wat de borden zeggen ruw bewaart, om later te kunnen herhalen.
        </p>
      </section>

      <section id="help-update">
        <h2>Een nieuwere versie</h2>

        <p>
          Een geïnstalleerde brug kijkt af en toe op GitHub of er een nieuwere versie is en meldt dat bovenaan de pagina, met de grootte van de download. Er wordt niets geïnstalleerd zonder dat jij op "Downloaden en installeren" drukt. Tijdens het installeren, ongeveer een minuut, worden de borden niet gelezen: kies dus een moment tussen de rondes. Een portable kopie krijgt een link in plaats van een knop. Onder "Dit programma" kun je het kijken uitzetten.
        </p>
      </section>

      <section id="help-red">
        <h2>Als een server rood is</h2>

        <ol>
          <li>Lees wat naast de stip staat. Het zegt in woorden wat er misging.</li>

          <li>
            Kijk of de brug zelf internet heeft. Zonder verbinding wordt alles bewaard en gestuurd zodra de lijn terug is; er gaat niets verloren.
          </li>

          <li>
            Is de brug op de server verwijderd, sluit dan opnieuw aan met een nieuwe link: "Verwijderen" hier, en "Een brug toevoegen" op de server.
          </li>

          <li>
            Blijft één server rood terwijl de andere groen zijn, dan ligt het aan die ene server. De anderen houden geen last van hem.
          </li>
        </ol>
      </section>
      <.foot locale={@locale} page={:help} />
    </main>
    """
  end

  def render(assigns) do
    ~H"""
    <main id="help">
      <header>
        <h1><.logo /> Arkab <span class="name">Help</span></h1>

        <p class="note">A short guide to the bridge in your hall.</p>
      </header>

      <section id="help-what">
        <h2>What Arkab is</h2>

        <p>
          Arkab is the bridge: a small program on a computer beside the electronic boards (often a Raspberry Pi). It reads the boards and sends them over the internet to one or more Alnasl servers, where the games are followed, repaired and passed on. Who plays whom and what the result is you decide there, not here.
        </p>

        <p>
          The bridge dials out to the server. Nothing has to be opened in the hall's network.
        </p>
      </section>

      <section id="help-join">
        <h2>Joining a server</h2>

        <ol>
          <li>
            In Alnasl, open Halls, then your hall, then its Bridges tab, and press "Add a bridge". (Alnasl's Setup wizard, the first section of Setup, leads there too.) A link appears with a QR code, good for one bridge and fifteen minutes.
          </li>

          <li>
            Paste the link in the "Join a server" field on this page, or press "Scan" and point the camera at the QR code (the button is only there where the browser can do it).
          </li>

          <li>Press "Join". When it says "Joined." you are done: the server is in the list.</li>
        </ol>

        <p>
          You never see or type a key; the bridge fetches it itself. If the link has expired or was used already, ask the server for a new one.
        </p>

        <p>
          One bridge can belong to more than one server, say the club's own box and the hosted server. Just join again with the next one's link.
        </p>
      </section>

      <section id="help-servers">
        <h2>The list of servers</h2>

        <p>
          Every server has a dot: <span class="dot up"></span>
          green is connected, <span class="dot down"></span>
          red is not connected. Beside a red dot there is usually the reason.
        </p>

        <p>
          "Remove" leaves a server. It ends the link here and on the server, and this bridge's boards go from there. You can join again later with a new link; the bridge comes back as the same bridge.
        </p>
      </section>

      <section id="help-queue">
        <h2>Events waiting</h2>

        <p>
          Everything the boards say goes into a queue on the bridge's disk first, and only then to the servers. The number beside "Events waiting" is what no server has confirmed yet. It rises a little and falls again; if it keeps climbing, at least one server is not reaching the bridge.
        </p>
      </section>

      <section id="help-ports">
        <h2>Ports and boards</h2>

        <p>
          "Ports and boards" lists the serial ports the bridge sees with the boards that answer on them: a green dot for a board that answers, a red one for a board that does not. "(not read)" means the bridge is not reading that port; a server can ask the bridge to read it. Which port is which board and what table numbers they get is arranged on the server, not here.
        </p>

        <p>
          "Recording" says whether the bridge keeps everything the boards say, raw, so it can be replayed later.
        </p>
      </section>

      <section id="help-update">
        <h2>A newer version</h2>

        <p>
          An installed bridge now and then looks on GitHub for a newer version and says so at the top of the page, with the size of the download. Nothing is installed until you press "Download and install". While it installs, about a minute, the boards are not read, so pick a moment between rounds. A portable copy gets a link instead of a button. Under "This program" you can switch the looking off.
        </p>
      </section>

      <section id="help-red">
        <h2>When a server shows red</h2>

        <ol>
          <li>Read what is beside the dot. It says in words what went wrong.</li>

          <li>
            Check that the bridge itself has internet. Without it everything is kept and sent when the line is back; nothing is lost.
          </li>

          <li>
            If the bridge was removed on the server, join again with a new link: "Remove" here, then "Add a bridge" on the server.
          </li>

          <li>
            If one server stays red while the others are green, the trouble is that one server. The others are not held up by it.
          </li>
        </ol>
      </section>
      <.foot locale={@locale} page={:help} />
    </main>
    """
  end
end
