defmodule ArkabWeb.PinHTML do
  @moduledoc "The unlock page: one field, in the visitor's language."

  use Phoenix.Component

  import ArkabWeb.Components, only: [foot: 1, logo: 1]

  alias ArkabWeb.Words

  def unlock(assigns) do
    # Called by the controller with a plain map, hence no `assign/3`.
    assigns = Map.merge(assigns, %{__changed__: nil, token: Plug.CSRFProtection.get_csrf_token()})

    ~H"""
    <main id="bridge">
      <header>
        <h1><.logo /> Arkab</h1>
      </header>

      <section id="unlock">
        <h2>{Words.t(@locale, :unlock_title)}</h2>

        <p>{Words.t(@locale, :unlock_intro)}</p>

        <form id="unlock-form" method="post" action="/unlock">
          <input type="hidden" name="_csrf_token" value={@token} />
          <input
            id="pin"
            type="password"
            name="pin"
            autocomplete="off"
            autocapitalize="off"
            aria-label={Words.t(@locale, :pin_label)}
            placeholder={Words.t(@locale, :pin_label)}
            required
          /> <button id="unlock-button" type="submit">{Words.t(@locale, :unlock)}</button>
        </form>

        <p :if={@error == :wrong} id="pin-error" class="error">{Words.t(@locale, :pin_wrong)}</p>

        <p :if={@error == :none} id="pin-error" class="error">{Words.t(@locale, :pin_none)}</p>

        <p :if={match?({:locked, _}, @error)} id="pin-error" class="error">
          {Words.t(@locale, :pin_locked, minutes: elem(@error, 1))}
        </p>

        <p class="note">{Words.t(@locale, :pin_plain)}</p>
      </section>
      <.foot locale={@locale} page={:help} />
    </main>
    """
  end
end
