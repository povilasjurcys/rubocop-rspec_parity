# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpecParity::FileHasSpec, :config do
  let(:spec_path) { "/project/spec/models/user_spec.rb" }
  let(:source_path) { "/project/app/models/user.rb" }

  def msg(spec_file)
    "Missing spec file. Expected #{spec_file}"
  end

  before do
    allow(File).to receive(:exist?).and_call_original
  end

  context "when spec file exists" do
    before { allow(File).to receive(:exist?).with(spec_path).and_return(true) }

    it "registers no offense" do
      expect_no_offenses(<<~RUBY, source_path)
        class User
        end
      RUBY
    end
  end

  context "when spec file does not exist" do
    before { allow(File).to receive(:exist?).with(spec_path).and_return(false) }

    it "registers an offense" do
      expect_offense(<<~RUBY, source_path)
        class User
        ^^^^^^^^^^ #{msg("spec/models/user_spec.rb")}
        end
      RUBY
    end
  end

  context "when file is not in app/" do
    let(:source_path) { "/project/lib/utils.rb" }

    it "registers no offense" do
      expect_no_offenses(<<~RUBY, source_path)
        class Utils
        end
      RUBY
    end
  end

  context "when file is a spec file" do
    let(:source_path) { "/project/app/models/user_spec.rb" }

    it "registers no offense" do
      expect_no_offenses(<<~RUBY, source_path)
        RSpec.describe User do
        end
      RUBY
    end
  end

  context "when file is in app/controllers" do
    let(:source_path) { "/project/app/controllers/users_controller.rb" }
    let(:spec_path) { "/project/spec/controllers/users_controller_spec.rb" }

    context "when spec file does not exist" do
      before { allow(File).to receive(:exist?).with(spec_path).and_return(false) }

      it "registers an offense" do
        expect_offense(<<~RUBY, source_path)
          class UsersController
          ^^^^^^^^^^^^^^^^^^^^^ #{msg("spec/controllers/users_controller_spec.rb")}
          end
        RUBY
      end
    end
  end

  context "when file is in app/services" do
    let(:source_path) { "/project/app/services/user_service.rb" }
    let(:spec_path) { "/project/spec/services/user_service_spec.rb" }

    context "when spec file exists" do
      before { allow(File).to receive(:exist?).with(spec_path).and_return(true) }

      it "registers no offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserService
          end
        RUBY
      end
    end
  end

  context "when file is in app/jobs" do
    let(:source_path) { "/project/app/jobs/cleanup_job.rb" }
    let(:spec_path) { "/project/spec/jobs/cleanup_job_spec.rb" }

    context "when spec file does not exist" do
      before { allow(File).to receive(:exist?).with(spec_path).and_return(false) }

      it "registers an offense" do
        expect_offense(<<~RUBY, source_path)
          class CleanupJob
          ^^^^^^^^^^^^^^^^ #{msg("spec/jobs/cleanup_job_spec.rb")}
          end
        RUBY
      end
    end
  end

  context "when file is in app/mailers" do
    let(:source_path) { "/project/app/mailers/user_mailer.rb" }
    let(:spec_path) { "/project/spec/mailers/user_mailer_spec.rb" }

    context "when spec file does not exist" do
      before { allow(File).to receive(:exist?).with(spec_path).and_return(false) }

      it "registers an offense" do
        expect_offense(<<~RUBY, source_path)
          class UserMailer
          ^^^^^^^^^^^^^^^^ #{msg("spec/mailers/user_mailer_spec.rb")}
          end
        RUBY
      end
    end
  end

  context "when file is in app/helpers" do
    let(:source_path) { "/project/app/helpers/application_helper.rb" }
    let(:spec_path) { "/project/spec/helpers/application_helper_spec.rb" }

    context "when spec file does not exist" do
      before { allow(File).to receive(:exist?).with(spec_path).and_return(false) }

      it "registers an offense" do
        expect_offense(<<~RUBY, source_path)
          module ApplicationHelper
          ^^^^^^^^^^^^^^^^^^^^^^^^ #{msg("spec/helpers/application_helper_spec.rb")}
          end
        RUBY
      end
    end
  end

  context "when file is in a non-covered directory" do
    let(:source_path) { "/project/app/graphql/types/user_type.rb" }

    it "registers no offense" do
      expect_no_offenses(<<~RUBY, source_path)
        class UserType
        end
      RUBY
    end
  end

  context "when file is in app/channels" do
    let(:source_path) { "/project/app/channels/application_cable/connection.rb" }

    it "registers no offense" do
      expect_no_offenses(<<~RUBY, source_path)
        class Connection
        end
      RUBY
    end
  end
end
