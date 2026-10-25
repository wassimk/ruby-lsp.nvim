# frozen_string_literal: true

class Calculator
  def add(a, b)
    a + b
  end

  def subtract(a, b)
    a - b
  end

  def average(numbers)
    numbers.sum / (numbers.size + 1)
  end
end
