# Claude Instructions for rubocop-spec_parity

## Code Quality Rules

1. **Never modify `.rubocop.yml`** unless the user explicitly asks to change RuboCop configuration. Always fix the code to satisfy linter rules rather than disabling or modifying the rules.

2. **After any code change**, always run linters and specs:
   ```bash
   bundle exec rubocop
   bundle exec rspec
   ```

3. **A task is only considered complete** when:
   - All RuboCop violations are resolved
   - All RSpec tests pass
   - No new warnings or errors are introduced

## Git Commits

- Keep commit descriptions short but clear: 1-5 sentences
- Focus on what changed and why, not implementation details

## Project Structure

- `lib/rubocop_spec_parity.rb` - Main entry point
- `lib/rubocop/cop/spec_parity/` - Custom RuboCop cops
- `config/default.yml` - Default cop configuration
- `spec/` - RSpec tests
