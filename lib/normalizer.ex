defmodule Normalizer do
  @moduledoc """
  # Normalizer

  Normalizes string-keyed maps to atom-keyed maps while converting values
  according to a given schema. Particularly useful when working with param maps.

  ### Usage

      schema = %{
        user_id: {:number, required: true},
        name: :string,
        admin: {:boolean, default: false},
        languages: [:string]
      }

      params = %{
        "user_id" => "42",
        "name" => "Neo",
        "languages" => ["en"],
        "age" => "55"
      }

      > Normalizer.normalize(params, schema)
      %{
        user_id: 42,
        name: "Neo",
        admin: false,
        languages: ["en"]
      }

  ### Properties

  * **Converts** types whenever possible and reasonable;
  * **Ensures** required values are given;
  * **Filters** keys and values not in the schema;
  * **Supports** basic types, lists, maps, and nested lists/maps.

  See `Normalizer.normalize/2` for more details.
  """

  alias Normalizer.MissingValue

  @type value_type :: atom() | [atom()] | map()

  @type value_options :: [
          required: boolean(),
          default: any(),
          with_offset: boolean()
        ]

  @type value_schema :: value_type() | {value_type(), value_options()}

  @type schema :: %{
          required(atom()) => value_schema()
        }

  defmacrop is_type(type) do
    quote do
      is_atom(unquote(type)) or is_list(unquote(type)) or is_map(unquote(type))
    end
  end

  defmacrop is_schema(schema) do
    quote do
      is_type(unquote(schema)) or is_tuple(unquote(schema))
    end
  end

  @doc """
  Normalizes a string-map using the given schema.

  The schema is expected to be a map where each key is an atom representing an
  expected string key in `params`, pointing to the type to which the respective
  value in the params should be normalized.

  The return is a normalized map, in case of success, or a map with each
  erroring key and a description, in case of failure.

  ## Types

  Types can be one of:
  * **Primitives**: `:string`, `:number`, `:boolean`.
  * **Parseable values**: `:datetime`, `:date`.
  * **Maps**: a nested schema for a nested map.
  * **Lists**: one-element lists that contain any of the other types.
  * **Tuples**: two-element tuples where the first element is one of the other types, and the second element a keyword list of options.

  ### Primitives

  **Strings** are somewhat of a catch all that ensures anything but lists and
  maps are converted to strings:

      iex> Normalizer.normalize(%{"key" => 42}, %{key: :string})
      {:ok, %{key: "42"}}

  **Numbers** are kept as is, if possible, or parsed:

      iex> Normalizer.normalize(%{"key" => 42}, %{key: :number})
      {:ok, %{key: 42}}

      iex> Normalizer.normalize(%{"key" => "42.5"}, %{key: :number})
      {:ok, %{key: 42.5}}

  **Booleans** accept native values, "true" and "false" strings, and "1" and "0"
  strings:

      iex> Normalizer.normalize(%{"key" => true}, %{key: :boolean})
      {:ok, %{key: true}}

      iex> Normalizer.normalize(%{"key" => "false"}, %{key: :boolean})
      {:ok, %{key: false}}

  ### Parseable Values

  Only `:datetime` and `:date` are supported right now.

      iex> Normalizer.normalize(%{"key" => "2020-02-11T00:00:00+0100"}, %{key: :datetime})
      {:ok, %{key: ~U[2020-02-10T23:00:00Z]}}

      iex> Normalizer.normalize(%{"key" => "2020-02-11"}, %{key: :date})
      {:ok, %{key: ~D[2020-02-11]}}

  The offset can be extracted as well by passing the `with_offset` option:

      iex> Normalizer.normalize(
      ...>   %{"key" => "2020-02-11T00:00:00+0100"},
      ...>   %{key: {:datetime, with_offset: true}}
      ...> )
      {:ok, %{key: {~U[2020-02-10T23:00:00Z], 3600}}}

  ### Maps

  Nested schemas are supported:

      iex> Normalizer.normalize(
      ...>   %{"key" => %{"age" => "42"}},
      ...>   %{key: %{age: :number}}
      ...> )
      {:ok, %{key: %{age: 42}}}

  ### Lists

  Lists are represented in the schema by a single-element list:

      iex> Normalizer.normalize(
      ...>   %{"key" => ["42", 52]},
      ...>   %{key: [:number]}
      ...> )
      {:ok, %{key: [42, 52]}}

  We can normalize lists of any one of the other types.

  ## Options

  Per-value options can be specified by passing a two-element tuple in the type
  specification. The three available options are `:required`, `:default`, and
  `:with_offset`.

  `:required` fails the validation process if the key is missing or nil:

      iex> Normalizer.normalize(%{"key" => nil}, %{key: :number})
      {:ok, %{key: nil}}

      iex> Normalizer.normalize(%{"key" => nil}, %{key: {:number, required: true}})
      {:error, %{key: "required number, got nil"}}

      iex> Normalizer.normalize(%{}, %{key: {:number, required: true}})
      {:error, %{key: "required number"}}

  `:default` ensures a value in a given key, if nil or missing:

      iex> Normalizer.normalize(%{}, %{key: {:number, default: 42}})
      {:ok, %{key: 42}}

      iex> Normalizer.normalize(%{"key" => 24}, %{key: {:number, default: 42}})
      {:ok, %{key: 24}}

  `:with_offset` is explained in the `:datetime` type above.
  """
  @spec normalize(params :: %{String.t() => any()}, schema :: schema()) ::
          {:ok, %{required(atom()) => any()}} | {:error, String.t()}
  def normalize(params, schema) do
    case apply_schema(params, schema) do
      %{errors: errors, normalized: normalized} when map_size(errors) == 0 -> {:ok, normalized}
      %{errors: errors} -> {:error, errors}
    end
  end

  defp apply_schema(params, schema) do
    for {key, value_schema} <- schema, reduce: %{normalized: %{}, errors: %{}} do
      %{normalized: normalized, errors: errors} ->
        value = Map.get(params, Atom.to_string(key), %MissingValue{})

        case normalize_value(value, value_schema) do
          {:ok, %MissingValue{}} ->
            %{normalized: normalized, errors: errors}

          {:ok, normalized_value} ->
            %{normalized: Map.put(normalized, key, normalized_value), errors: errors}

          {:error, value_error} ->
            %{normalized: normalized, errors: Map.put(errors, key, value_error)}
        end
    end
  end

  defp normalize_value(value, {type, options}) when is_type(type) and is_list(options) do
    with {:ok, value} <- convert_type(value, type),
         {:ok, value} <- apply_options(value, type, options),
         do: {:ok, value}
  end

  defp normalize_value(value, type) when is_type(type),
    do: normalize_value(value, {type, []})

  # Return nil for all types if value is nil:
  defp convert_type(nil, _type),
    do: {:ok, nil}

  # Pass-through for a missing value:
  defp convert_type(%MissingValue{}, _type),
    do: {:ok, %MissingValue{}}

  # Convert strings:
  defp convert_type(value, :string) when is_binary(value),
    do: {:ok, value}

  defp convert_type(value, :string) when not is_map(value) and not is_list(value),
    do: {:ok, to_string(value)}

  defp convert_type(_value, :string),
    do: {:error, "expected string"}

  # Convert numbers:
  defp convert_type(value, :number) when is_number(value),
    do: {:ok, value}

  defp convert_type(value, :number) when is_binary(value) do
    ret =
      if String.contains?(value, "."),
        do: Float.parse(value),
        else: Integer.parse(value)

    case ret do
      {value, ""} -> {:ok, value}
      _ -> {:error, "expected number"}
    end
  end

  # Convert booleans:
  defp convert_type(value, :boolean) when is_boolean(value),
    do: {:ok, value}

  defp convert_type(value, :boolean) when is_binary(value) do
    case value do
      truthy when truthy in ["1", "true"] -> {:ok, true}
      falsy when falsy in ["0", "false"] -> {:ok, false}
      _ -> {:error, "expected boolean"}
    end
  end

  # Convert datetimes:
  defp convert_type(value, :datetime) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, offset} -> {:ok, {datetime, offset}}
      {:error, error} -> {:error, "expected datetime (#{error})"}
    end
  end

  # Convert dates:
  defp convert_type(value, :date) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, error} -> {:error, "expected date (#{error})"}
    end
  end

  # Convert lists:
  defp convert_type(values, [schema]) when is_list(values) and is_schema(schema) do
    values
    |> Enum.reduce_while([], fn value, out ->
      case normalize_value(value, schema) do
        {:ok, normalized} -> {:cont, [normalized | out]}
        {:error, error} -> {:halt, error <> " list"}
      end
    end)
    |> case do
      out when is_list(out) -> {:ok, Enum.reverse(out)}
      error when is_binary(error) -> {:error, error}
    end
  end

  # Convert maps (just recurse):
  defp convert_type(map, map_schema) when is_map(map) and is_map(map_schema),
    do: normalize(map, map_schema)

  defp convert_type(_value, type),
    do: {:error, "expected #{type_string(type)}"}

  defp apply_options(value, type, options) when is_list(options) and is_type(type) do
    options
    |> full_type_options(type)
    |> Enum.reduce_while({:ok, value}, fn {opt_key, opt_value}, {:ok, value} ->
      case apply_option(value, type, opt_key, opt_value) do
        {:ok, value} -> {:cont, {:ok, value}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp apply_option(nil, type, :required, true),
    do: {:error, "required #{type_string(type)}, got nil"}

  defp apply_option(%MissingValue{}, type, :required, true),
    do: {:error, "required #{type_string(type)}"}

  defp apply_option(nil, _type, :default, value),
    do: {:ok, value}

  defp apply_option(%MissingValue{}, _type, :default, value),
    do: {:ok, value}

  defp apply_option(datetime_with_offset, :datetime, :with_offset, true),
    do: {:ok, datetime_with_offset}

  defp apply_option({datetime, _offset}, :datetime, :with_offset, false),
    do: {:ok, datetime}

  defp apply_option(value, _type, _option, _option_value),
    do: {:ok, value}

  defp full_type_options(options, :datetime), do: Keyword.put_new(options, :with_offset, false)
  defp full_type_options(options, _type), do: options

  defp type_string(type) when is_atom(type),
    do: "#{type}"

  defp type_string([type]) when is_atom(type),
    do: "#{type} list"

  defp type_string([{type, _options}]) when is_atom(type),
    do: "#{type} list"

  defp type_string(type) when is_map(type),
    do: "map"
end
