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

    context "when public section reopens after private section" do
      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "registers offenses only for public methods" do
        expect_offense(<<~RUBY, source_path)
          class User
            private

            def some_method
            end

            public

            def some_public_method1
            ^^^^^^^^^^^^^^^^^^^^^^^ #{msg("some_public_method1")}
            end

            def some_public_method2
            ^^^^^^^^^^^^^^^^^^^^^^^ #{msg("some_public_method2")}
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

    context "when method is made private with post-hoc private :method_name" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def perform
            end

            private :perform
          end
        RUBY
      end
    end

    context "when method is made protected with post-hoc protected :method_name" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def perform
            end

            protected :perform
          end
        RUBY
      end
    end

    context "when method after post-hoc private :other remains public" do
      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "registers an offense for the public method" do
        expect_offense(<<~RUBY, source_path)
          class User
            def secret
            end

            private :secret

            def perform
            ^^^^^^^^^^^ #{msg("perform")}
            end
          end
        RUBY
      end
    end

    context "when method after post-hoc protected :other remains public" do
      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "registers an offense for the public method" do
        expect_offense(<<~RUBY, source_path)
          class User
            def secret
            end

            protected :secret

            def perform
            ^^^^^^^^^^^ #{msg("perform")}
            end
          end
        RUBY
      end
    end

    context "when method is made private with inline private def" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            private def perform
            end
          end
        RUBY
      end
    end

    context "when method is made protected with inline protected def" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            protected def perform
            end
          end
        RUBY
      end
    end

    context "when method after inline private def other remains public" do
      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "registers an offense for the public method" do
        expect_offense(<<~RUBY, source_path)
          class User
            private def secret
            end

            def perform
            ^^^^^^^^^^^ #{msg("perform")}
            end
          end
        RUBY
      end
    end

    context "when method after inline protected def other remains public" do
      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "registers an offense for the public method" do
        expect_offense(<<~RUBY, source_path)
          class User
            protected def secret
            end

            def perform
            ^^^^^^^^^^^ #{msg("perform")}
            end
          end
        RUBY
      end
    end

    context "when method is private inside class << self" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            class << self
              private

              def find_by_name
              end
            end
          end
        RUBY
      end
    end

    context "when method is protected inside class << self" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            class << self
              protected

              def find_by_name
              end
            end
          end
        RUBY
      end
    end

    context "when method is re-publicized with public :method_name after private section" do
      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "registers an offense for the public method" do
        expect_offense(<<~RUBY, source_path)
          class User
            private

            def perform
            ^^^^^^^^^^^ #{msg("perform")}
            end

            public :perform
          end
        RUBY
      end
    end

    context "when method is re-publicized with public def after private section" do
      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "registers an offense for the public method" do
        expect_offense(<<~RUBY, source_path)
          class User
            private

            public def perform
                   ^^^^^^^^^^^ #{msg("perform")}
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

    context "when spec has only one-liner it blocks without descriptions" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            describe '#perform' do
              it { is_expected.to be_truthy }
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

    context "when spec has one-liner it block without method describe" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe User do
            it { is_expected.to be_truthy }
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

    context "with self.included hook method" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          module UserMethods
            def self.included(base)
            end
          end
        RUBY
      end
    end

    context "with self.extended hook method" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          module UserMethods
            def self.extended(base)
            end
          end
        RUBY
      end
    end

    context "with self.inherited hook method" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def self.inherited(subclass)
            end
          end
        RUBY
      end
    end

    context "with self.prepended hook method" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          module UserMethods
            def self.prepended(base)
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

    context "when class method is marked with private_class_method (post-hoc)" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            def self.find_by_name
            end

            private_class_method :find_by_name
          end
        RUBY
      end
    end

    context "when class method is marked with private_class_method (inline)" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class User
            private_class_method def self.find_by_name
            end
          end
        RUBY
      end
    end

    context "when only some class methods are private_class_method" do
      before { allow(File).to receive(:read).with(spec_path).and_return("") }

      it "registers an offense only for the public class method" do
        expect_offense(<<~RUBY, source_path)
          class User
            def self.public_finder
            ^^^^^^^^^^^^^^^^^^^^^^ Missing spec for public method `public_finder`. Expected describe '#public_finder' or describe '.public_finder' in spec/models/user_spec.rb
            end

            def self.secret_finder
            end

            private_class_method :secret_finder
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

  describe "DescribeAliases configuration" do
    let(:source_path) { "/project/app/services/user_service.rb" }
    let(:spec_path) { "/project/spec/services/user_service_spec.rb" }

    before do
      allow(Dir).to receive(:glob).and_call_original
      allow(Dir).to receive(:glob)
        .with("/project/spec/services/user_service_*_spec.rb")
        .and_return([])
    end

    context "with same-name alias ('#call' => '.call')" do
      let(:cop_config) { { "DescribeAliases" => { "#call" => ".call" } } }

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

      it "does not register an offense for instance def call with .call spec" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserService
            def call
            end
          end
        RUBY
      end
    end

    context "with different-name alias ('#perform' => '.perform_later')" do
      let(:source_path) { "/project/app/jobs/user_job.rb" }
      let(:spec_path) { "/project/spec/jobs/user_job_spec.rb" }
      let(:cop_config) { { "DescribeAliases" => { "#perform" => ".perform_later" } } }

      before do
        allow(Dir).to receive(:glob).and_call_original
        allow(Dir).to receive(:glob)
          .with("/project/spec/jobs/user_job_*_spec.rb")
          .and_return([])
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe UserJob do
            describe '.perform_later' do
              it 'works' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense for instance def perform with .perform_later spec" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserJob
            def perform
            end
          end
        RUBY
      end
    end

    context "with array alias ('#perform' => ['.perform_later', '.perform_now'])" do
      let(:source_path) { "/project/app/jobs/user_job.rb" }
      let(:spec_path) { "/project/spec/jobs/user_job_spec.rb" }
      let(:cop_config) { { "DescribeAliases" => { "#perform" => [".perform_later", ".perform_now"] } } }

      before do
        allow(Dir).to receive(:glob).and_call_original
        allow(Dir).to receive(:glob)
          .with("/project/spec/jobs/user_job_*_spec.rb")
          .and_return([])
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe UserJob do
            describe '.perform_now' do
              it 'works' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense when any alias matches" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserJob
            def perform
            end
          end
        RUBY
      end
    end

    context "with no alias configured" do
      let(:cop_config) { { "DescribeAliases" => {} } }

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

      it "registers an offense for instance def call with only .call spec" do
        expect_offense(<<~RUBY, source_path)
          class UserService
            def call
            ^^^^^^^^ Missing spec for public method `call`. Expected describe '#call' or describe '.call' in spec/services/user_service_spec.rb
            end
          end
        RUBY
      end
    end

    context "when alias does not apply to class methods (def self.call)" do
      let(:cop_config) { { "DescribeAliases" => { "#call" => ".call" } } }

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

      it "registers an offense for def self.call with only #call spec" do
        expect_offense(<<~RUBY, source_path)
          class UserService
            def self.call
            ^^^^^^^^^^^^^ Missing spec for public method `call`. Expected describe '#call' or describe '.call' in spec/services/user_service_spec.rb
            end
          end
        RUBY
      end
    end

    context "when neither original nor alias matches" do
      let(:cop_config) { { "DescribeAliases" => { "#call" => ".call" } } }

      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe UserService do
            describe '#other_method' do
              it 'works' do
              end
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

    context "when instance method spec exists (no alias needed)" do
      let(:cop_config) { { "DescribeAliases" => { "#call" => ".call" } } }

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

    context "when wildcard spec uses module wrapping instead of fully qualified class name" do
      let(:source_path) { "/project/app/services/authentication/create_session.rb" }
      let(:spec_path) { "/project/spec/services/authentication/create_session_spec.rb" }
      let(:wildcard_spec_path) { "/project/spec/services/authentication/create_session_edge_cases_spec.rb" }

      before do
        allow(File).to receive(:exist?).with(spec_path).and_return(true)
        allow(File).to receive(:read).with(spec_path).and_return("")
        allow(Dir).to receive(:glob).and_call_original
        allow(Dir).to receive(:glob)
          .with("/project/spec/services/authentication/create_session_*_spec.rb")
          .and_return([wildcard_spec_path])
        allow(File).to receive(:exist?).with(wildcard_spec_path).and_return(true)
        allow(File).to receive(:read).with(wildcard_spec_path).and_return(<<~RUBY)
          module Authentication
            RSpec.describe CreateSession do
              describe '#call' do
              end
            end
          end
        RUBY
      end

      it "finds the method in the module-wrapped wildcard spec" do
        expect_no_offenses(<<~RUBY, source_path)
          module Authentication
            class CreateSession
              def call
              end
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

    context "single method class using public :method_name to re-publicize" do
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
            private

            def call
            end

            public :call
          end
        RUBY
      end
    end

    context "single method class using public def to re-publicize" do
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
            private

            public def call
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

    context "single method class with one-liner it blocks" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe UserCreator do
            it { is_expected.to be_truthy }
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

    context "single method class with one-liner it block inside context" do
      before do
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe UserCreator do
            context 'when valid' do
              it { is_expected.to be_truthy }
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

    context "nested module class with method describe in spec" do
      let(:source_path) { "/project/app/services/calendar/user_creator.rb" }
      let(:spec_path) { "/project/spec/services/calendar/user_creator_spec.rb" }

      before do
        allow(File).to receive(:exist?).with(spec_path).and_return(true)
        allow(Dir).to receive(:glob)
          .with("/project/spec/services/calendar/user_creator_*_spec.rb")
          .and_return([])
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          RSpec.describe Calendar::UserCreator do
            describe '#call' do
              it 'works' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense when spec has describe '#call'" do
        expect_no_offenses(<<~RUBY, source_path)
          module Calendar
            class UserCreator
              def call
              end
            end
          end
        RUBY
      end
    end

    context "nested module class with direct examples in spec" do
      let(:source_path) { "/project/app/services/calendar/user_creator.rb" }
      let(:spec_path) { "/project/spec/services/calendar/user_creator_spec.rb" }

      before do
        allow(File).to receive(:exist?).with(spec_path).and_return(true)
        allow(Dir).to receive(:glob)
          .with("/project/spec/services/calendar/user_creator_*_spec.rb")
          .and_return([])
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          RSpec.describe Calendar::UserCreator do
            it 'creates a user' do
            end
          end
        RUBY
      end

      it "does not register an offense for single-method class with examples" do
        expect_no_offenses(<<~RUBY, source_path)
          module Calendar
            class UserCreator
              def call
              end
            end
          end
        RUBY
      end
    end

    context "nested module class without SkipMethodDescribeFor" do
      let(:source_path) { "/project/app/models/calendar/user.rb" }
      let(:spec_path) { "/project/spec/models/calendar/user_spec.rb" }
      let(:cop_config) { { "SkipMethodDescribeFor" => [] } }

      before do
        allow(File).to receive(:exist?).with(spec_path).and_return(true)
        allow(Dir).to receive(:glob)
          .with("/project/spec/models/calendar/user_*_spec.rb")
          .and_return([])
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          RSpec.describe Calendar::User do
            describe '#call' do
              it 'works' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense (normal validation finds describe '#call')" do
        expect_no_offenses(<<~RUBY, source_path)
          module Calendar
            class User
              def call
              end
            end
          end
        RUBY
      end
    end

    context "when spec uses module wrapping instead of fully qualified class name" do
      let(:source_path) { "/project/app/services/authentication/create_session.rb" }
      let(:spec_path) { "/project/spec/services/authentication/create_session_spec.rb" }

      before do
        allow(File).to receive(:exist?).with(spec_path).and_return(true)
        allow(Dir).to receive(:glob)
          .with("/project/spec/services/authentication/create_session_*_spec.rb")
          .and_return([])
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          module Authentication
            RSpec.describe CreateSession do
              it 'creates a session' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense for single-method class with examples" do
        expect_no_offenses(<<~RUBY, source_path)
          module Authentication
            class CreateSession
              def call
              end
            end
          end
        RUBY
      end
    end

    context "when spec uses module wrapping and DescribeAliases are configured" do
      let(:source_path) { "/project/app/services/authentication/create_session.rb" }
      let(:spec_path) { "/project/spec/services/authentication/create_session_spec.rb" }
      let(:cop_config) do
        {
          "SkipMethodDescribeFor" => ["app/services/**/*"],
          "DescribeAliases" => { "#call" => ".call" }
        }
      end

      before do
        allow(File).to receive(:exist?).with(spec_path).and_return(true)
        allow(Dir).to receive(:glob)
          .with("/project/spec/services/authentication/create_session_*_spec.rb")
          .and_return([])
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          module Authentication
            RSpec.describe CreateSession do
              describe '.call' do
                it 'creates a session' do
                end
              end
            end
          end
        RUBY
      end

      it "does not register an offense when alias matches via describe" do
        expect_no_offenses(<<~RUBY, source_path)
          module Authentication
            class CreateSession
              def call
              end
            end
          end
        RUBY
      end
    end
  end
end
