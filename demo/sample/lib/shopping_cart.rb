# frozen_string_literal: true

class ShoppingCart
  attr_reader :items

  def initialize
    @items = []
  end

  def add(name, price, quantity: 1)
    @items << { name:, price:, quantity: }
  end

  def total
    @items.sum { |item| item[:price] * item[:quantity] }
  end

  def empty?
    @items.empty?
  end
end
