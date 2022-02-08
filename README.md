# Normalizer

[![Module Version](https://img.shields.io/hexpm/v/normalizer.svg)](https://hex.pm/packages/normalizer)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/normalizer/)
[![Total Download](https://img.shields.io/hexpm/dt/normalizer.svg)](https://hex.pm/packages/normalizer)
[![License](https://img.shields.io/hexpm/l/normalizer.svg)](https://github.com/myskoach/normalizer/blob/master/LICENSE)

Normalizes string-keyed maps to atom-keyed maps while converting values
according to a given schema. Particularly useful when working with param maps.

## Usage

```elixir
iex> schema = %{
  user_id: {:number, required: true},
  name: :string,
  admin: {:boolean, default: false},
  languages: [:string]
}

iex> params = %{
  "user_id" => "42",
  "name" => "Neo",
  "languages" => ["en"],
  "age" => "55"
}

iex> Normalizer.normalize(params, schema)
{:ok, %{
  user_id: 42,
  name: "Neo",
  admin: false,
  languages: ["en"]
}}
```

## Properties

* **Converts** types whenever possible and reasonable;
* **Ensures** required values are given;
* **Filters** keys and values not in the schema;
* **Supports** basic types, lists, maps, and nested lists/maps.

See docs for `Normalizer.normalize/2` for more details.

## Installation

Add `normalizer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:normalizer, "~> 0.2.0"}
  ]
end
```

## Contributing

PRs welcome, unit tests required.

## Copyright and License

Copyright (c) 2022 João Ferreira

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

