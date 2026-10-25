# frozen_string_literal: true

require_relative '../lib/calculator'

RSpec.describe Calculator do
  subject(:calculator) { described_class.new }

  it 'adds two numbers' do
    expect(calculator.add(2, 3)).to eq(5)
  end

  it 'subtracts two numbers' do
    expect(calculator.subtract(3, 2)).to eq(1)
  end

  it 'averages a list of scores' do
    scores = [90, 85, 77]
    average = calculator.average(scores)

    expect(average).to eq(84)
  end
end
