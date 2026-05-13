# Development Policy

## Release Versioning

- Default every release to the next patch version: `0.x.(y+1)`.
- Do not infer `0.(x+1).0`, `1.0.0`, or any skipped version from the size of a change.
- Use `scripts/release.sh` or `scripts/release.sh patch` for normal releases.
- Use `minor`, `major`, or an explicit higher version only when the user explicitly asks for that exact larger bump.
- When a non-patch release is explicitly requested, run it with `ALLOW_NON_PATCH_BUMP=1`.
- Prefer the release script and GitHub CLI over manually creating releases in the GitHub web UI.
