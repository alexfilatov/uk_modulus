# UkModulus

UK bank account modulus checking for Elixir. Validates UK sort code and account number combinations using the official Vocalink algorithm.

## Features

- Validates UK bank account numbers against sort codes
- Ships with official Vocalink data (1,151 weight rules)
- Supports MOD10, MOD11, and DBLAL algorithms
- Handles all Vocalink exceptions (1-14)
- Fast concurrent access via ETS
- Optional auto-update from Vocalink's website

## Installation

Add `uk_modulus` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:uk_modulus, "~> 0.1.0"}
  ]
end
```

## Usage

### Basic Validation

```elixir
# Returns {:ok, true} if valid, {:ok, false} if invalid
UkModulus.validate("20-00-00", "12345678")
# => {:ok, true} or {:ok, false}

# Simple boolean check
UkModulus.valid?("200000", "12345678")
# => true or false
```

### Format Handling

The library accepts sort codes in various formats:

```elixir
UkModulus.validate("200000", "12345678")   # Plain 6 digits
UkModulus.validate("20-00-00", "12345678") # With dashes
UkModulus.validate("20 00 00", "12345678") # With spaces
```

Account numbers can be 6, 7, or 8 digits (shorter numbers are zero-padded):

```elixir
UkModulus.validate("200000", "12345678")  # 8 digits
UkModulus.validate("200000", "1234567")   # 7 digits (padded to 01234567)
UkModulus.validate("200000", "123456")    # 6 digits (padded to 00123456)
```

### Error Handling

```elixir
UkModulus.validate("123", "12345678")
# => {:error, :invalid_sort_code_format}

UkModulus.validate("200000", "123")
# => {:error, :invalid_account_number_format}
```

### Unknown Sort Codes

Sort codes not in the Vocalink data return `{:ok, true}` to allow validation by downstream payment processors:

```elixir
UkModulus.validate("999999", "12345678")
# => {:ok, true}
```

## Configuration

### Auto-Update (Optional)

By default, the library uses bundled Vocalink data. To enable automatic updates from Vocalink's website:

```elixir
# config/config.exs
config :uk_modulus, auto_update: true
```

When enabled, the library checks for updates every 30 days.

### Manual Refresh

Force a refresh of data from Vocalink:

```elixir
UkModulus.refresh()
```

## How It Works

The library implements the UK Modulus Checking algorithm as specified by Vocalink (now part of Mastercard). This algorithm validates that a sort code and account number combination could be legitimate.

### Algorithms

- **MOD10**: Standard modulus 10 check
- **MOD11**: Standard modulus 11 check
- **DBLAL**: Double alternate (Luhn-like) algorithm

### Data Source

The weight table data comes from Vocalink's official modulus checking specification. The library ships with this data bundled in `priv/data/`.

- `valacdos.txt` - Weight table with 1,151 rules
- `scsubtab.txt` - Sort code substitution table for exception handling

Official source: https://www.vocalink.com/tools/modulus-checking/

## Limitations

- This validation catches typos and obvious errors but does not guarantee the account exists
- Some valid accounts may fail validation due to exceptions not yet implemented
- Always use this as a first-pass check before sending to your payment processor

## License

MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

- Vocalink/Mastercard for the modulus checking specification and data
- Inspired by similar libraries in other languages
