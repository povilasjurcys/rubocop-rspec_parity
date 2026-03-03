# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpecParity::FileHasSpec, :config do
  let(:source_path) { "/project/app/models/user.rb" }
  let(:spec_path) { "/project/spec/models/user_spec.rb" }

  before do
    allow(File).to receive(:exist?).and_call_original
  end

  context "when spec file does not exist" do
    before { allow(File).to receive(:exist?).with(spec_path).and_return(false) }

    it "registers an offense" do
      expect_offense(<<~RUBY, source_path)
        class User
        ^^^^^^^^^^ Missing spec file. Expected spec/models/user_spec.rb to exist
        end
      RUBY
    end
  end

  context "when spec file exists" do
    before { allow(File).to receive(:exist?).with(spec_path).and_return(true) }

    it "does not register an offense" do
      expect_no_offenses(<<~RUBY, source_path)
        class User
        end
      RUBY
    end
  end

  context "when file is outside app/" do
    let(:source_path) { "/project/lib/something.rb" }

    it "does not register an offense" do
      expect_no_offenses(<<~RUBY, source_path)
        class Something
        end
      RUBY
    end
  end

  context "when file is a spec file itself" do
    let(:source_path) { "/project/app/models/user_spec.rb" }

    it "does not register an offense" do
      expect_no_offenses(<<~RUBY, source_path)
        RSpec.describe User do
        end
      RUBY
    end
  end

  context "when file is in app/services" do
    let(:source_path) { "/project/app/services/user_creator.rb" }
    let(:spec_path) { "/project/spec/services/user_creator_spec.rb" }

    before { allow(File).to receive(:exist?).with(spec_path).and_return(false) }

    it "registers an offense with correct spec path" do
      expect_offense(<<~RUBY, source_path)
        class UserCreator
        ^^^^^^^^^^^^^^^^^ Missing spec file. Expected spec/services/user_creator_spec.rb to exist
        end
      RUBY
    end
  end

  context "when file is in a deeply nested path" do
    let(:source_path) { "/project/app/models/concerns/authenticatable.rb" }
    let(:spec_path) { "/project/spec/models/concerns/authenticatable_spec.rb" }

    before { allow(File).to receive(:exist?).with(spec_path).and_return(false) }

    it "registers an offense with correct spec path" do
      expect_offense(<<~RUBY, source_path)
        module Authenticatable
        ^^^^^^^^^^^^^^^^^^^^^^ Missing spec file. Expected spec/models/concerns/authenticatable_spec.rb to exist
        end
      RUBY
    end
  end
end
