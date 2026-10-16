defmodule ArkabWeb.Components do
  @moduledoc "The little the two pages share: the foot with the help link and the language."

  use Phoenix.Component

  alias ArkabWeb.Words

  attr :locale, :string, required: true
  attr :page, :atom, values: [:status, :help], required: true

  def foot(assigns) do
    ~H"""
    <footer id="foot" class="foot">
      <a :if={@page == :status} id="help-link" href="/help">{Words.t(@locale, :help)}</a>
      <a :if={@page == :help} id="back-link" href="/">{Words.t(@locale, :back)}</a>
      <span class="note">{Words.t(@locale, :language)}:</span>
      <a id="lang-en" href="/lang/en" aria-current={to_string(@locale == "en")}>EN</a>
      <a id="lang-nl" href="/lang/nl" aria-current={to_string(@locale == "nl")}>NL</a>
    </footer>
    """
  end
end
