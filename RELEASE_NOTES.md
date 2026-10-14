# Deploy Kit release notes

## v1.1.0

First release with the versioned update system. Includes deployment failure guards, safe backups,
release checks and notifications, explicit manual updates and recoverable updates.
Each installation keeps its own config, credentials and update policy.

An earlier v1.0.0 tag is preserved. This version is not published merely by committing this file. A maintainer must
run the test-gated release command on main to publish its tag and GitHub Release.

Stable tags use vMAJOR.MINOR.PATCH. Patch releases must stay compatible with the
existing config and deployment interface. Minor releases require manual review.
Major releases may break compatibility and require explicit --allow-major.
Prerelease tags are ignored by installation checkers.
