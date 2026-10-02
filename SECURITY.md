# Security Policy

## Supported Versions

Only the [latest release](https://github.com/smarty-kiki/watch_your_claude/releases) is supported with security fixes.

## Reporting a Vulnerability

Please report vulnerabilities privately via [GitHub Security Advisories](https://github.com/smarty-kiki/watch_your_claude/security/advisories/new) rather than a public issue. Include a description of the impact and, if possible, steps to reproduce.

You can expect an initial response within 7 days.

## Scope Notes

WatchYourClaude runs locally and reads session data from `~/.claude/`. It performs no network requests. Reports involving local files it can already read with user-level permissions are out of scope unless the app exposes that data beyond the user's own session.
