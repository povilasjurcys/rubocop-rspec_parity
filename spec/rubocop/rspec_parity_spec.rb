# frozen_string_literal: true

RSpec.describe RuboCop::RSpecParity do
  it "has a version number" do
    expect(RuboCop::RSpecParity::VERSION).not_to be_nil
  end

  it "loads the cops" do
    expect(RuboCop::Cop::RSpecParity::NoLetBang).to be_a(Class)
    expect(RuboCop::Cop::RSpecParity::PublicMethodHasSpec).to be_a(Class)
  end
end
