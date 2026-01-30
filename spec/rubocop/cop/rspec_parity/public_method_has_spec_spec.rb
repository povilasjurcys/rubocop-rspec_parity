# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpecParity::PublicMethodHasSpec, :config do
  let(:spec_path) { "/project/spec/models/user_spec.rb" }
  let(:source_path) { "/project/app/models/user.rb" }

  def msg(method_name, spec_file = "spec/models/user_spec.rb")
    "Missing spec for public method `#{method_name}`. " \
      "Expected describe '##{method_name}' or describe '.#{method_name}' in #{spec_file}"
  end

  before do
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(spec_path).and_return(true)
    allow(File).to receive(:read).and_call_original
  end

  describe "file path filtering" do
    context "when file is in app/models" do
      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "checks the file" do
        expect_offense(<<~RUBY, source_path)
          class User
            def perform
            ^^^^^^^^^^^ #{msg("perform")}
            end
          end
        RUBY
      end
    end

    context "when file is in app/controllers" do
      let(:source_path) { "/project/app/controllers/users_controller.rb" }
      let(:spec_path) { "/project/spec/controllers/users_controller_spec.rb" }

      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "checks the file" do
        expect_offense(<<~RUBY, source_path)
          class UsersController
            def index
            ^^^^^^^^^ #{msg("index", "spec/controllers/users_controller_spec.rb")}
            end
          end
        RUBY
      end
    end

    context "when file is in app/services" do
      let(:source_path) { "/project/app/services/user_service.rb" }
      let(:spec_path) { "/project/spec/services/user_service_spec.rb" }

      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "checks the file" do
        expect_offense(<<~RUBY, source_path)
          class UserService
            def execute
            ^^^^^^^^^^^ #{msg("execute", "spec/services/user_service_spec.rb")}
            end
          end
        RUBY
      end
    end

    context "when file is in app/jobs" do
      let(:source_path) { "/project/app/jobs/user_job.rb" }
      let(:spec_path) { "/project/spec/jobs/user_job_spec.rb" }

      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "checks the file" do
        expect_offense(<<~RUBY, source_path)
          class UserJob
            def perform
            ^^^^^^^^^^^ #{msg("perform", "spec/jobs/user_job_spec.rb")}
            end
          end
        RUBY
      end
    end

    context "when file is in app/mailers" do
      let(:source_path) { "/project/app/mailers/user_mailer.rb" }
      let(:spec_path) { "/project/spec/mailers/user_mailer_spec.rb" }

      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "checks the file" do
        expect_offense(<<~RUBY, source_path)
          class UserMailer
            def welcome
            ^^^^^^^^^^^ #{msg("welcome", "spec/mailers/user_mailer_spec.rb")}
            end
          end
        RUBY
      end
    end

    context "when file is in app/helpers" do
      let(:source_path) { "/project/app/helpers/users_helper.rb" }
      let(:spec_path) { "/project/spec/helpers/users_helper_spec.rb" }

      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "checks the file" do
        expect_offense(<<~RUBY, source_path)
          module UsersHelper
            def format_name
            ^^^^^^^^^^^^^^^ #{msg("format_name", "spec/helpers/users_helper_spec.rb")}
            end
          end
        RUBY
      end
    end

    context "when file is a spec file" do
      let(:source_path) { "/project/app/models/user_spec.rb" }

      it "does not check the file" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def perform
            end
          end
        RUBY
      end
    end

    context "when file is not in app directory" do
      let(:source_path) { "/project/lib/user.rb" }

      it "does not check the file" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def perform
            end
          end
        RUBY
      end
    end

    context "when file is in non-covered directory" do
      let(:source_path) { "/project/app/views/users.rb" }

      it "does not check the file" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def perform
            end
          end
        RUBY
      end
    end

    context "when spec file does not exist" do
      before { allow(File).to receive(:exist?).with(spec_path).and_return(false) }

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def perform
            end
          end
        RUBY
      end
    end
  end

  describe "visibility detection" do
    context "when method is public by default" do
      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "registers an offense" do
        expect_offense(<<~RUBY, source_path)
          class User
            def perform
            ^^^^^^^^^^^ #{msg("perform")}
            end
          end
        RUBY
      end
    end

    context "when method is explicitly public" do
      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "registers an offense" do
        expect_offense(<<~RUBY, source_path)
          class User
            public

            def perform
            ^^^^^^^^^^^ #{msg("perform")}
            end
          end
        RUBY
      end
    end

    context "when method is private" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            private

            def perform
            end
          end
        RUBY
      end
    end

    context "when method is protected" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            protected

            def perform
            end
          end
        RUBY
      end
    end

    context "when visibility changes throughout the class" do
      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "registers an offense only for public methods" do
        expect_offense(<<~RUBY, source_path)
          class User
            def public_method
            ^^^^^^^^^^^^^^^^^ #{msg("public_method")}
            end

            private

            def private_method
            end

            public

            def another_public_method
            ^^^^^^^^^^^^^^^^^^^^^^^^^ #{msg("another_public_method")}
            end
          end
        RUBY
      end
    end

    context "when method is after multiple visibility changes" do
      it "respects the last visibility change" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            public

            protected

            private

            def perform
            end
          end
        RUBY
      end
    end
  end

  describe "spec pattern matching" do
    context "when spec has describe '#method_name'" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            describe '#perform' do
              it 'works' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def perform
            end
          end
        RUBY
      end
    end

    context "when spec has describe with double quotes" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            describe "#perform" do
              it 'works' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def perform
            end
          end
        RUBY
      end
    end

    context "when spec has context '#method_name'" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            context '#perform' do
              it 'works' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def perform
            end
          end
        RUBY
      end
    end

    context "when spec has describe 'method_name' without prefix" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            describe 'perform' do
              it 'works' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def perform
            end
          end
        RUBY
      end
    end

    context "when spec has it 'tests method_name'" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            it 'tests perform correctly' do
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def perform
            end
          end
        RUBY
      end
    end

    context "when spec has it 'checks method_name'" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            it 'checks perform' do
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def perform
            end
          end
        RUBY
      end
    end

    context "when spec has it 'verifies method_name'" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            it 'verifies perform' do
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def perform
            end
          end
        RUBY
      end
    end

    context "when spec has it 'validates method_name'" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            it 'validates perform' do
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def perform
            end
          end
        RUBY
      end
    end

    context "when spec pattern is case insensitive" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            it 'TESTS perform' do
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def perform
            end
          end
        RUBY
      end
    end

    context "when spec does not cover the method" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            describe '#other_method' do
              it 'works' do
              end
            end
          end
        RUBY
      end

      it "registers an offense" do
        expect_offense(<<~RUBY, source_path)
          class User
            def perform
            ^^^^^^^^^^^ #{msg("perform")}
            end
          end
        RUBY
      end
    end
  end

  describe "method exclusions" do
    context "with initialize method" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def initialize
            end
          end
        RUBY
      end
    end

    context "with before_* callback" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def before_save
            end
          end
        RUBY
      end
    end

    context "with after_* callback" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def after_create
            end
          end
        RUBY
      end
    end

    context "with around_* callback" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def around_save
            end
          end
        RUBY
      end
    end

    context "with validate_* method" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def validate_name
            end
          end
        RUBY
      end
    end

    context "with autosave_* method" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def autosave_associated_records
            end
          end
        RUBY
      end
    end
  end

  describe "class methods" do
    context "when class method is defined with self." do
      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "registers an offense expecting '.method_name' pattern" do
        expect_offense(<<~RUBY, source_path)
          class User
            def self.find_by_name
            ^^^^^^^^^^^^^^^^^^^^^ Missing spec for public method `find_by_name`. Expected describe '#find_by_name' or describe '.find_by_name' in spec/models/user_spec.rb
            end
          end
        RUBY
      end
    end

    context "when spec has describe '.method_name'" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            describe '.find_by_name' do
              it 'works' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def self.find_by_name
            end
          end
        RUBY
      end
    end

    context "when class method is defined inside eigenclass" do
      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "registers an offense expecting '.method_name' pattern" do
        expect_offense(<<~RUBY, source_path)
          class User
            class << self
              def find_by_name
              ^^^^^^^^^^^^^^^^ Missing spec for public method `find_by_name`. Expected describe '#find_by_name' or describe '.find_by_name' in spec/models/user_spec.rb
              end
            end
          end
        RUBY
      end
    end

    context "when eigenclass method has matching spec" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            describe '.find_by_name' do
              it 'works' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            class << self
              def find_by_name
              end
            end
          end
        RUBY
      end
    end
  end

  describe "service call method special handling" do
    let(:source_path) { "/project/app/services/user_service.rb" }
    let(:spec_path) { "/project/spec/services/user_service_spec.rb" }

    context "when service has call method with class method spec" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe UserService do
            describe '.call' do
              it 'works' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense for instance call method" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserService
            def call
            end
          end
        RUBY
      end
    end

    context "when service has call method with instance method spec" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe UserService do
            describe '#call' do
              it 'works' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserService
            def call
            end
          end
        RUBY
      end
    end

    context "when service has call method with no spec" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe UserService do
            describe '#other_method' do
            end
          end
        RUBY
      end

      it "registers an offense" do
        expect_offense(<<~RUBY, source_path)
          class UserService
            def call
            ^^^^^^^^ Missing spec for public method `call`. Expected describe '#call' or describe '.call' in spec/services/user_service_spec.rb
            end
          end
        RUBY
      end
    end

    context "when non-service has call method" do
      let(:source_path) { "/project/app/models/user.rb" }
      let(:spec_path) { "/project/spec/models/user_spec.rb" }

      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            describe '.call' do
            end
          end
        RUBY
      end

      it "registers an offense when only class method spec exists" do
        expect_offense(<<~RUBY, source_path)
          class User
            def call
            ^^^^^^^^ #{msg("call")}
            end
          end
        RUBY
      end
    end
  end

  describe "multiple methods" do
    before do
      allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
        describe User do
          describe '#covered_method' do
          end
        end
      RUBY
    end

    it "registers offenses for each uncovered public method" do
      expect_offense(<<~RUBY, source_path)
        class User
          def covered_method
          end

          def uncovered_method
          ^^^^^^^^^^^^^^^^^^^^ #{msg("uncovered_method")}
          end

          def another_uncovered
          ^^^^^^^^^^^^^^^^^^^^^ #{msg("another_uncovered")}
          end
        end
      RUBY
    end
  end

  describe "modules" do
    before { allow(File).to receive(:read).with(spec_path).and_return("") }

    it "checks methods in modules" do
      expect_offense(<<~RUBY, source_path)
        module UserMethods
          def perform
          ^^^^^^^^^^^ #{msg("perform")}
          end
        end
      RUBY
    end
  end

  describe "methods with special characters" do
    before { allow(File).to receive(:read).with(spec_path).and_return("") }

    it "checks predicate methods" do
      expect_offense(<<~RUBY, source_path)
        class User
          def valid?
          ^^^^^^^^^^ Missing spec for public method `valid?`. Expected describe '#valid?' or describe '.valid?' in spec/models/user_spec.rb
          end
        end
      RUBY
    end

    it "checks bang methods" do
      expect_offense(<<~RUBY, source_path)
        class User
          def save!
          ^^^^^^^^^ Missing spec for public method `save!`. Expected describe '#save!' or describe '.save!' in spec/models/user_spec.rb
          end
        end
      RUBY
    end

    it "checks setter methods" do
      expect_offense(<<~RUBY, source_path)
        class User
          def name=(value)
          ^^^^^^^^^ Missing spec for public method `name=`. Expected describe '#name=' or describe '.name=' in spec/models/user_spec.rb
          end
        end
      RUBY
    end
  end

  describe "methods with specs containing special characters" do
    context "when predicate method has matching spec" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            describe '#valid?' do
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def valid?
            end
          end
        RUBY
      end
    end

    context "when bang method has matching spec" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            describe '#save!' do
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def save!
            end
          end
        RUBY
      end
    end
  end

  describe "wildcard spec files" do
    let(:wildcard_spec_path) { "/project/spec/models/user_updates_spec.rb" }

    before do
      allow(Dir).to receive(:glob).and_call_original
      allow(Dir).to receive(:glob)
        .with("/project/spec/models/user_*_spec.rb")
        .and_return([wildcard_spec_path])
    end

    context "when wildcard spec file describes the same class" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return("")
        allow(File).to receive(:exist?).with(wildcard_spec_path).and_return(true)
        allow(File).to receive(:read).with(wildcard_spec_path).and_return(<<~RUBY)
          RSpec.describe User do
            describe '#update' do
            end
          end
        RUBY
      end

      it "finds the method in wildcard spec file" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def update
            end
          end
        RUBY
      end

      it "still registers offense for methods not in any spec" do
        expect_offense(<<~RUBY, source_path)
          class User
            def delete
            ^^^^^^^^^^ #{msg("delete")}
            end
          end
        RUBY
      end
    end

    context "when wildcard spec file describes a different class" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return("")
        allow(File).to receive(:exist?).with(wildcard_spec_path).and_return(true)
        allow(File).to receive(:read).with(wildcard_spec_path).and_return(<<~RUBY)
          RSpec.describe UserUpdates do
            describe '#update' do
            end
          end
        RUBY
      end

      it "does not use wildcard spec file" do
        expect_offense(<<~RUBY, source_path)
          class User
            def update
            ^^^^^^^^^^ #{msg("update")}
            end
          end
        RUBY
      end
    end

    context "when method is in wildcard spec but not in base spec" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          RSpec.describe User do
            describe '#create' do
            end
          end
        RUBY
        allow(File).to receive(:exist?).with(wildcard_spec_path).and_return(true)
        allow(File).to receive(:read).with(wildcard_spec_path).and_return(<<~RUBY)
          RSpec.describe User do
            describe '#update' do
            end
          end
        RUBY
      end

      it "finds method in wildcard spec" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def update
            end
          end
        RUBY
      end
    end

    context "when base spec file does not exist but wildcard spec does" do
      before do
        allow(File).to receive(:exist?).with(spec_path).and_return(false)
        allow(File).to receive(:exist?).with(wildcard_spec_path).and_return(true)
        allow(File).to receive(:read).with(wildcard_spec_path).and_return(<<~RUBY)
          RSpec.describe User do
            describe '#perform' do
            end
          end
        RUBY
      end

      it "still finds the method in wildcard spec" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def perform
            end
          end
        RUBY
      end
    end
  end

  describe "SkipMethodDescribeFor configuration" do
    let(:source_path) { "/project/app/services/user_creator.rb" }
    let(:spec_path) { "/project/spec/services/user_creator_spec.rb" }
    let(:cop_config) do
      { "SkipMethodDescribeFor" => ["app/services/**/*"] }
    end

    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(spec_path).and_return(true)
      allow(File).to receive(:read).and_call_original
      allow(Dir).to receive(:glob).and_call_original
      allow(Dir).to receive(:glob)
        .with("/project/spec/services/user_creator_*_spec.rb")
        .and_return([])
    end

    context "single method class with direct examples" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe UserCreator do
            it 'creates a user' do
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserCreator
            def call
            end
          end
        RUBY
      end
    end

    context "single method class with contexts but no method describe" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe UserCreator do
            context 'when valid' do
              it 'works' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserCreator
            def call
              do_something
            end

            private

            def do_something
            end
          end
        RUBY
      end
    end

    context "single method class with traditional method describe" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe UserCreator do
            describe '#call' do
              it 'works' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserCreator
            def call
            end
          end
        RUBY
      end
    end

    context "multiple public methods" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe UserCreator do
            it 'works' do
            end
          end
        RUBY
      end

      it "registers offense for uncovered methods" do
        expect_offense(<<~RUBY, source_path)
          class UserCreator
            def call
            ^^^^^^^^ Missing spec for public method `call`. Expected describe '#call' or describe '.call' in spec/services/user_creator_spec.rb
            end

            def another_method
            ^^^^^^^^^^^^^^^^^^ Missing spec for public method `another_method`. Expected describe '#another_method' or describe '.another_method' in spec/services/user_creator_spec.rb
            end
          end
        RUBY
      end
    end

    context "single method but no examples in spec" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe UserCreator do
            # No examples
          end
        RUBY
      end

      it "registers an offense" do
        expect_offense(<<~RUBY, source_path)
          class UserCreator
            def call
            ^^^^^^^^ Missing spec for public method `call`. Expected describe '#call' or describe '.call' in spec/services/user_creator_spec.rb
            end
          end
        RUBY
      end
    end

    context "path does not match configuration" do
      let(:source_path) { "/project/app/models/user.rb" }
      let(:spec_path) { "/project/spec/models/user_spec.rb" }

      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            it 'works' do
            end
          end
        RUBY
      end

      it "registers an offense" do
        expect_offense(<<~RUBY, source_path)
          class User
            def call
            ^^^^^^^^ Missing spec for public method `call`. Expected describe '#call' or describe '.call' in spec/models/user_spec.rb
            end
          end
        RUBY
      end
    end

    context "configuration is empty array" do
      let(:cop_config) { { "SkipMethodDescribeFor" => [] } }

      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe UserCreator do
            it 'works' do
            end
          end
        RUBY
      end

      it "registers an offense" do
        expect_offense(<<~RUBY, source_path)
          class UserCreator
            def call
            ^^^^^^^^ Missing spec for public method `call`. Expected describe '#call' or describe '.call' in spec/services/user_creator_spec.rb
            end
          end
        RUBY
      end
    end
  end
end
