# frozen_string_literal: true

class Temperature
  def self.to_fahrenheit(celsius)
    (celsius * 9.0 / 5) + 32
  end

  def self.to_celsius(fahrenheit)
    (fahrenheit - 32) * 5.0 / 9
  end
end
