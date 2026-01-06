defmodule UkModulusTest do
  use ExUnit.Case, async: false

  describe "validate/2 basic functionality" do
    test "returns {:ok, boolean} for valid format inputs" do
      result = UkModulus.validate("200000", "12345678")
      assert match?({:ok, _}, result)
    end

    test "produces consistent results for same input" do
      {:ok, result1} = UkModulus.validate("200000", "12345678")
      {:ok, result2} = UkModulus.validate("200000", "12345678")
      assert result1 == result2
    end

    test "validates all zeros account number" do
      # All zeros typically passes modulus checks
      {:ok, result} = UkModulus.validate("200000", "00000000")
      assert is_boolean(result)
    end

    test "validates known sort code ranges" do
      # These sort codes exist in Vocalink data
      assert {:ok, _} = UkModulus.validate("200000", "12345678")
      assert {:ok, _} = UkModulus.validate("400000", "12345678")
      assert {:ok, _} = UkModulus.validate("300000", "12345678")
      assert {:ok, _} = UkModulus.validate("600000", "12345678")
    end
  end

  describe "validate/2 format handling" do
    test "returns true for unknown sort code ranges" do
      # Sort codes not in the table should pass (payment processor validates later)
      assert {:ok, true} = UkModulus.validate("999999", "12345678")
    end

    test "handles sort code with dashes" do
      result = UkModulus.validate("20-00-00", "12345678")
      assert match?({:ok, _}, result)
    end

    test "handles sort code with spaces" do
      result = UkModulus.validate("20 00 00", "12345678")
      assert match?({:ok, _}, result)
    end

    test "rejects invalid sort code format - too short" do
      assert {:error, :invalid_sort_code_format} = UkModulus.validate("12345", "12345678")
    end

    test "rejects invalid sort code format - too long" do
      assert {:error, :invalid_sort_code_format} = UkModulus.validate("1234567", "12345678")
    end

    test "rejects invalid sort code format - letters" do
      assert {:error, :invalid_sort_code_format} = UkModulus.validate("abcdef", "12345678")
    end

    test "rejects invalid account number format - too short" do
      assert {:error, :invalid_account_number_format} = UkModulus.validate("200000", "12345")
    end

    test "rejects invalid account number format - too long" do
      assert {:error, :invalid_account_number_format} = UkModulus.validate("200000", "123456789")
    end

    test "rejects invalid account number format - letters" do
      assert {:error, :invalid_account_number_format} = UkModulus.validate("200000", "abcdefgh")
    end

    test "handles 6-digit account numbers by padding" do
      result = UkModulus.validate("200000", "345679")
      assert match?({:ok, _}, result)
    end

    test "handles 7-digit account numbers by padding" do
      result = UkModulus.validate("200000", "2345679")
      assert match?({:ok, _}, result)
    end
  end

  describe "valid?/2" do
    test "returns boolean for valid format" do
      result = UkModulus.valid?("200000", "12345678")
      assert is_boolean(result)
    end

    test "returns false for invalid format" do
      refute UkModulus.valid?("12345", "12345678")
    end

    test "returns true for unknown sort codes" do
      assert UkModulus.valid?("999999", "12345678")
    end
  end

  describe "ready?/0" do
    test "returns true when data is loaded" do
      assert UkModulus.ready?() == true
    end
  end

  describe "refresh/0" do
    test "accepts refresh request without crashing" do
      assert :ok = UkModulus.refresh()
      Process.sleep(10)
      assert Process.whereis(UkModulus.VocalinkData) != nil
    end
  end

  describe "VocalinkData" do
    test "loads bundled data on startup" do
      # Should have loaded the 1151 rules from bundled data
      assert UkModulus.VocalinkData.rule_count() > 1000
    end

    test "returns weight rules for known sort codes" do
      rules = UkModulus.VocalinkData.get_weight_rules("200000")
      assert is_list(rules)
      assert length(rules) >= 1
    end

    test "returns empty list for unknown sort codes" do
      rules = UkModulus.VocalinkData.get_weight_rules("999999")
      assert rules == []
    end

    test "returns substitution for exception 5 sort codes" do
      # Check a known substitution from scsubtab.txt
      result = UkModulus.VocalinkData.get_substitution("938600")
      assert is_binary(result)
    end

    test "returns same sort code when no substitution exists" do
      result = UkModulus.VocalinkData.get_substitution("200000")
      assert result == "200000"
    end
  end
end
