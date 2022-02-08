defmodule NormalizerTest do
  use ExUnit.Case, async: true
  doctest Normalizer

  describe "normalize/2" do
    test "converts keys to atoms" do
      schema = %{name: :string}
      result = normalize!(%{"name" => "Neo"}, schema)
      assert result == %{name: "Neo"}
    end

    test "removes keys not in the schema" do
      schema = %{name: :string}
      result = normalize!(%{"name" => "Neo", "age" => 23}, schema)
      assert result == %{name: "Neo"}
    end

    test "normalizes numbers" do
      schema = %{age: :number}
      assert normalize!(%{"age" => 42}, schema) == %{age: 42}
      assert normalize!(%{"age" => "42"}, schema) == %{age: 42}
      assert normalize!(%{"age" => "42.0"}, schema) == %{age: 42.0}
      assert fail_normalize!(%{"age" => "42.0.0"}, schema) == %{age: "expected number"}
      assert fail_normalize!(%{"age" => ""}, schema) == %{age: "expected number"}
      assert fail_normalize!(%{"age" => []}, schema) == %{age: "expected number"}
    end

    test "normalizes booleans" do
      schema = %{admin: :boolean}
      assert normalize!(%{"admin" => "true"}, schema) == %{admin: true}
      assert normalize!(%{"admin" => "false"}, schema) == %{admin: false}
      assert normalize!(%{"admin" => nil}, schema) == %{admin: nil}
      assert normalize!(%{"admin" => "1"}, schema) == %{admin: true}
      assert normalize!(%{"admin" => "0"}, schema) == %{admin: false}
      assert normalize!(%{"admin" => true}, schema) == %{admin: true}
      assert normalize!(%{"admin" => false}, schema) == %{admin: false}
      assert fail_normalize!(%{"admin" => "2"}, schema) == %{admin: "expected boolean"}
      assert fail_normalize!(%{"admin" => "asd"}, schema) == %{admin: "expected boolean"}
    end

    test "normalizes datetimes" do
      schema = %{created: :datetime}

      assert normalize!(%{"created" => "2020-12-30T12:00:00Z"}, schema) ==
               %{created: ~U[2020-12-30T12:00:00Z]}

      assert normalize!(%{"created" => "2020-12-30T12:00:00+0100"}, schema) ==
               %{created: ~U[2020-12-30T11:00:00Z]}

      assert fail_normalize!(%{"created" => "2020-12-30T12:00:00"}, schema) ==
               %{created: "expected datetime (missing_offset)"}
    end

    test "normalizes dates" do
      schema = %{created: :date}

      assert normalize!(%{"created" => "2020-12-30"}, schema) ==
               %{created: ~D[2020-12-30]}

      assert fail_normalize!(%{"created" => "2020-12-30T12:00:00Z"}, schema) ==
               %{created: "expected date (invalid_format)"}
    end

    test "enforces required params" do
      schema = %{name: {:string, required: true}, sign: {:string, required: true}}
      result = fail_normalize!(%{}, schema)
      assert result == %{name: "required string", sign: "required string"}
    end

    test "applies defaults" do
      schema = %{age: {:number, default: 42}}
      assert normalize!(%{}, schema) == %{age: 42}
      assert normalize!(%{"age" => 1}, schema) == %{age: 1}
      assert normalize!(%{"name" => "Neo"}, schema) == %{age: 42}
    end

    test "can keep datetime offsets" do
      schema = %{created: {:datetime, with_offset: true}}

      assert normalize!(%{"created" => "2020-12-30T12:00:00Z"}, schema) ==
               %{created: {~U[2020-12-30T12:00:00Z], 0}}

      assert normalize!(%{"created" => "2020-12-30T12:00:00+0100"}, schema) ==
               %{created: {~U[2020-12-30T11:00:00Z], 3600}}
    end

    test "can combine options" do
      schema = %{created: {:datetime, with_offset: true, required: true}}

      assert fail_normalize!(%{}, schema) == %{created: "required datetime"}

      assert normalize!(%{"created" => "2020-12-30T12:00:00Z"}, schema) ==
               %{created: {~U[2020-12-30T12:00:00Z], 0}}
    end

    test "normalizes lists" do
      schema = %{langs: [:string]}
      assert normalize!(%{"langs" => ["pt", "en"]}, schema) == %{langs: ["pt", "en"]}
      assert normalize!(%{"langs" => [42, 43]}, schema) == %{langs: ["42", "43"]}
      assert fail_normalize!(%{"langs" => "pt"}, schema) == %{langs: "expected string list"}
      assert fail_normalize!(%{"langs" => [[], "a"]}, schema) == %{langs: "expected string list"}
    end

    test "can require lists and values in lists" do
      schema = %{langs: {[:string], required: true}}
      assert normalize!(%{"langs" => ["pt", nil]}, schema) == %{langs: ["pt", nil]}
      assert fail_normalize!(%{}, schema) == %{langs: "required string list"}
      assert fail_normalize!(%{"langs" => nil}, schema) == %{langs: "required string list"}

      # Sanity check:
      assert normalize!(%{"langs" => ["en", "pt"]}, schema) == %{langs: ["en", "pt"]}

      schema = %{langs: {[{:string, required: true}], required: true}}

      assert fail_normalize!(%{"langs" => ["a", nil]}, schema) == %{langs: "required string list"}
      assert fail_normalize!(%{"langs" => nil}, schema) == %{langs: "required string list"}

      # Sanity check:
      assert normalize!(%{"langs" => ["pt", "en"]}, schema) == %{langs: ["pt", "en"]}
    end

    test "can fill lists with defaults" do
      schema = %{ages: [{:number, default: 42}]}
      assert normalize!(%{"ages" => [42, nil]}, schema) == %{ages: [42, 42]}
    end

    test "normalizes maps" do
      schema = %{
        profile: %{
          age: :number,
          name: :string
        }
      }

      assert normalize!(%{"profile" => %{"age" => 42, "name" => "Neo"}}, schema) == %{
               profile: %{
                 age: 42,
                 name: "Neo"
               }
             }

      assert fail_normalize!(%{"profile" => %{"age" => "abc"}}, schema) == %{
               profile: %{
                 age: "expected number"
               }
             }
    end

    test "normalizes lists of maps" do
      schema = %{
        posts: [
          %{
            text: :string,
            length: :number
          }
        ]
      }

      params = %{
        "posts" => [
          %{
            "text" => "lorem ipsum",
            "length" => "11"
          },
          %{
            "text" => "dolor amet",
            "length" => 10
          }
        ]
      }

      assert normalize!(params, schema) == %{
               posts: [
                 %{
                   text: "lorem ipsum",
                   length: 11
                 },
                 %{
                   text: "dolor amet",
                   length: 10
                 }
               ]
             }
    end
  end

  defp normalize!(params, schema) do
    assert {:ok, result} = Normalizer.normalize(params, schema)
    result
  end

  defp fail_normalize!(params, schema) do
    assert {:error, result} = Normalizer.normalize(params, schema)
    result
  end
end
