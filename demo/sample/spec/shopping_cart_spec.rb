# frozen_string_literal: true

require_relative '../lib/shopping_cart'

RSpec.describe ShoppingCart do
  subject(:cart) { described_class.new }

  context 'when empty' do
    it 'has no items' do
      expect(cart).to be_empty
    end

    it 'totals zero' do
      expect(cart.total).to eq(0)
    end
  end

  context 'with items' do
    before do
      cart.add('Coffee', 4, quantity: 2)
      cart.add('Bagel', 3)
    end

    it 'counts each item' do
      expect(cart.items.size).to eq(2)
    end

    it 'totals price times quantity' do
      expect(cart.total).to eq(11)
    end
  end
end
