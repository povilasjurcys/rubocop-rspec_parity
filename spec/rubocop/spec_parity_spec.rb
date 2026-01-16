# frozen_string_literal: true

RSpec.describe Rubocop::SpecParity do
  it "has a version number" do
    expect(Rubocop::SpecParity::VERSION).not_to be_nil
  end

  it "loads the cops" do
    expect(RuboCop::Cop::SpecParity::NoLetBang).to be_a(Class)
    expect(RuboCop::Cop::SpecParity::PublicMethodHasSpec).to be_a(Class)
  end
end
