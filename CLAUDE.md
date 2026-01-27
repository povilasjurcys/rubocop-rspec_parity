# Claude Instructions for rubocop-rspec_parity

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
   - CHANGELOG.md has been updated if applicable (see below)

## Changelog Management

**Update CHANGELOG.md ONLY for:**
- New features (Added)
- Bug fixes (Fixed)
- Deprecations (Deprecated)
- Removed features (Removed)
- Dependency updates (Updated)

**DO NOT update for:**
- Refactoring or code quality improvements
- Minor documentation updates
- Internal implementation changes

**Format (compact, one line per change):**
```
Added: Allow passing custom decorator build strategy
Fixed: Better handle render in controller hooks
Updated: GraphQL and gems version dependencies
Removed: NoLetBang cop
```

**During Release:**
- Move items from `[Unreleased]` to: `## [X.Y.Z] - YYYY-MM-DD`
- Leave `[Unreleased]` empty

## Release Process

To release a new version:
1. Update version in `lib/rubocop/rspec_parity/version.rb`
2. Update CHANGELOG.md (move [Unreleased] items to new version section)
3. Run tests: `bundle exec rspec && bundle exec rubocop`
4. Use rake task to release: `bundle exec rake release`
   - This will create a git tag, push commits/tags, and push the gem to rubygems.org
5. **DO NOT** manually run `gem build` or `gem push` - use the rake task

## Git Commits

- Keep commit descriptions short but clear: 1-5 sentences
- Focus on what changed and why, not implementation details

## Project Structure

- `lib/rubocop_rspec_parity.rb` - Main entry point
- `lib/rubocop/cop/spec_rparity/` - Custom RuboCop cops
- `config/default.yml` - Default cop configuration
- `spec/` - RSpec tests
