defmodule Arkab.Board do
  @moduledoc """
  What a board reports: 64 squares, each a piece or nothing. No side to
  move, no castling rights - a board does not know those, and neither does
  anything in Arkab.

  A 64-tuple, index 0 = a8 through 63 = h1, each entry `nil` or
  `{colour, kind}` (`{:w, :p}` ... `{:b, :k}`). As text it is 64 characters,
  FEN letters and `.` for an empty square: how the capture files, the link
  and Alnasl's database hold it. Alnasl's `Alnasl.Position` is this plus the
  chess.
  """

  @type t :: tuple()

  @letters %{
    {:w, :p} => ?P,
    {:w, :n} => ?N,
    {:w, :b} => ?B,
    {:w, :r} => ?R,
    {:w, :q} => ?Q,
    {:w, :k} => ?K,
    {:b, :p} => ?p,
    {:b, :n} => ?n,
    {:b, :b} => ?b,
    {:b, :r} => ?r,
    {:b, :q} => ?q,
    {:b, :k} => ?k
  }
  @pieces Map.new(@letters, fn {piece, letter} -> {letter, piece} end)

  @start_text "rnbqkbnrpppppppp" <> String.duplicate(".", 32) <> "PPPPPPPPRNBQKBNR"

  @doc "The starting position, as a board."
  def start do
    {:ok, board} = from_text(@start_text)
    board
  end

  @doc "A board with nothing on it."
  def empty, do: Tuple.duplicate(nil, 64)

  @doc "64 characters: FEN letters, `.` for empty."
  def to_text(board) when is_tuple(board) do
    for i <- 0..63, into: "" do
      case elem(board, i) do
        nil -> "."
        piece -> <<Map.fetch!(@letters, piece)>>
      end
    end
  end

  @doc "Reads what `to_text/1` writes. `:error` for anything else."
  def from_text(<<text::binary-size(64)>>) do
    squares =
      for <<c <- text>> do
        cond do
          c == ?. -> nil
          is_map_key(@pieces, c) -> Map.fetch!(@pieces, c)
          true -> :bad
        end
      end

    if :bad in squares, do: :error, else: {:ok, List.to_tuple(squares)}
  end

  def from_text(_other), do: :error

  @doc "The board as seen from the other side: a board plugged in turned round."
  def rotate(board), do: board |> Tuple.to_list() |> Enum.reverse() |> List.to_tuple()

  @doc "The squares on which two boards differ."
  def diff(a, b), do: for(i <- 0..63, elem(a, i) != elem(b, i), do: i)
end
