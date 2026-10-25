# frozen_string_literal: true

require_relative '../lib/temperature'

RSpec.describe Temperature do
  describe '.to_fahrenheit' do
    it 'converts freezing' do
      expect(described_class.to_fahrenheit(0)).to eq(32)
    end

    it 'converts boiling' do
      expect(described_class.to_fahrenheit(100)).to eq(212)
    end
  end

  describe '.to_celsius' do
    it 'converts body temperature' do
      expect(described_class.to_celsius(98.6)).to be_within(0.01).of(37)
    end

    it 'converts negative values' do
      expect(described_class.to_celsius(-40)).to eq(-40)
    end
  end
end
