# frozen_string_literal: true

require_relative '../lib/slug'

RSpec.describe Slug do
  it 'lowercases words' do
    expect(described_class.call('Hello World')).to eq('hello-world')
  end

  it 'removes punctuation' do
    expect(described_class.call('Ruby, Rails & Neovim!')).to eq('ruby-rails-neovim')
  end

  it 'trims surrounding dashes' do
    expect(described_class.call('  -- spaced out --  ')).to eq('spaced-out')
  end
end
