defmodule Arkab.Contract do
  @moduledoc """
  The bridge-protocol contract (`priv/contracts/bridge-protocol-v1/`) for
  the tests: its schemas, resolved without the network, and a check that
  a frame fits one of them.

  A schema's `$ref` to `common.schema.json` is a URL on GitHub once the
  `$id` is applied. `resolve/1` is ex_json_schema's remote resolver
  (`config/test.exs`) and answers every such URL from this directory, so
  a test never asks GitHub what the file next to it says.
  """

  import ExUnit.Assertions

  @dir Path.expand("../../priv/contracts/bridge-protocol-v1", __DIR__)

  def dir, do: @dir

  @doc "Every file in the contract directory, relative and sorted, `index.json` left out."
  def files do
    Path.wildcard(Path.join(@dir, "**/*"))
    |> Enum.reject(&File.dir?/1)
    |> Enum.map(&Path.relative_to(&1, @dir))
    |> Enum.reject(&(&1 == "index.json"))
    |> Enum.sort()
  end

  def read!(file), do: @dir |> Path.join(file) |> File.read!() |> Jason.decode!()

  @doc "The names of the schemas: `\"hello\"` for `hello.schema.json`."
  def schemas do
    for file <- files(),
        String.ends_with?(file, ".schema.json"),
        file != "common.schema.json",
        do: String.replace_suffix(file, ".schema.json", "")
  end

  @doc "`[{schema, file, data}]` for every example: `hello.json` and `hello.<variant>.json` are hello's."
  def examples do
    for "examples/" <> name = file <- files() do
      [schema | _] = String.split(name, ".")
      {schema, file, read!(file)}
    end
  end

  @doc "The schema `name`, resolved."
  def schema(name) do
    key = {__MODULE__, name}

    case :persistent_term.get(key, nil) do
      nil ->
        root = ExJsonSchema.Schema.resolve(read!("#{name}.schema.json"))
        :persistent_term.put(key, root)
        root

      root ->
        root
    end
  end

  @doc "`:ok`, or `{:error, [{message, path}]}`."
  def validate(name, data), do: ExJsonSchema.Validator.validate(schema(name), data)

  @doc """
  Asserts that `data` fits schema `name`. `data` may be a map with atom or
  string keys or JSON text: it is put through JSON first, as the wire would.
  """
  def assert_valid!(name, data) do
    json =
      if is_binary(data),
        do: Jason.decode!(data),
        else: data |> Jason.encode!() |> Jason.decode!()

    case validate(name, json) do
      :ok ->
        json

      {:error, errors} ->
        flunk("""
        does not fit #{name}.schema.json:
        #{Enum.map_join(errors, "\n", fn {message, path} -> "  #{path}: #{message}" end)}
        in: #{Jason.encode!(json)}
        """)
    end
  end

  @doc "The schema a frame of the link belongs to, by its type."
  def schema_of(%{"type" => type})
      when type in ~w(hello events boards reply leave welcome refused ack command),
      do: type

  @doc false
  # ex_json_schema's remote resolver: a $ref's URL, answered from this directory.
  def resolve(url) do
    %URI{path: path} = URI.parse(url)
    read!(Path.basename(path))
  end
end
