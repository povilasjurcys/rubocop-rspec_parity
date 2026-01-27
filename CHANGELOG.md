## [Unreleased]

## [1.0.0] - 2026-01-27

Added: `IgnoreMemoization` configuration option for `SufficientContexts` cop to ignore memoization patterns like `@var ||=` and `return @var if defined?(@var)`
Fixed: `SufficientContexts` cop now works with absolute file paths
Removed: `NoLetBang` cop

## [0.1.0] - 2026-01-15

- Initial release
