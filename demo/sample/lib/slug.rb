# frozen_string_literal: true

module Slug
  def self.call(text)
    text.downcase.strip.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
  end
end
