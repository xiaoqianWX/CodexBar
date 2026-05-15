---
summary: "CodexBar test-suite coverage and repetition audit."
read_when:
  - Reviewing test-suite size
  - Planning test fixture cleanup
  - Deciding where additional coverage is worth adding
---

# Test suite audit

Generated on 2026-05-15 from branch `test-suite-coverage-repetition-audit`.

## Commands

```sh
swift test list > /tmp/codexbar-test-list.txt
swift test --enable-code-coverage
swift test --show-codecov-path
```

Coverage numbers below are source-only, excluding `.build`, `Tests`, and `TestsLinux` files from
`.build/arm64-apple-macosx/debug/codecov/CodexBar.json`.

## Inventory

- 278 macOS test files under `Tests/CodexBarTests`.
- 75,412 lines of macOS test code.
- 116,346 lines of source code.
- 2,525 test declarations found statically: 2,476 Swift Testing `@Test` declarations and 49 XCTest-style
  `func test...` methods.
- 2,511 listable tests from `swift test list`: 2,500 in `CodexBarTests` and 11 in `CodexBarLinuxTests`.
- 2,484 tests executed in the instrumented coverage run; the run passed. The difference from listable tests is
  expected from Linux/conditional/disabled tests such as `LiveAccountTests`.

The suite is large, but the count is not inherently suspicious for this app: the provider matrix, Codex and Claude
account flows, dashboard parsing, plan-utilization history, status-menu modeling, and cost scanner all have real
behavioral surface area. The maintainability issue is repetition in setup and contract-style assertions, not just raw
test count.

## Coverage

Overall source line coverage is 61.8%: 68,985 of 111,699 instrumented source lines.

| Target | Files | Line coverage | Function coverage | Region coverage |
| --- | ---: | ---: | ---: | ---: |
| `CodexBarCore` | 281 | 66.6% | 61.7% | 55.9% |
| `CodexBar` | 237 | 58.6% | 57.1% | 54.1% |
| `CodexBarCLI` | 15 | 44.6% | 57.8% | 43.8% |
| `CodexBarWidget` | 3 | 7.3% | 6.2% | 6.1% |

Coverage is strongest where the repo has stable model/parser seams: usage formatting, provider parsers, dashboard
parsing, plan utilization, menu descriptors, status-menu model descriptors, token accounts, and cost scanning.

The low-coverage areas are mostly expected runtime edges:

- SwiftUI/AppKit view code and controller wiring, especially preferences, menu views, login runners, purchase windows,
  overlays, display links, and widget views.
- Cookie import and browser/WebKit boundaries where unit tests often stop at the pure parser or model layer.
- CLI command entry/dispatch paths that are mostly covered indirectly through renderer and command helper tests.

Largest low-coverage files with meaningful follow-up value:

- `Sources/CodexBarWidget/CodexBarWidgetViews.swift`: 2.2% line coverage. Add pure helper tests for format, color,
  empty state, compact metric selection, and history-chart edge cases before considering rendered widget snapshots.
- `Sources/CodexBarCore/Providers/VertexAI/VertexAIOAuth/VertexAIUsageFetcher.swift`: 0.0%. Add response decoding,
  aggregation, pagination, and auth/error mapping tests.
- `Sources/CodexBarCore/Providers/Doubao/DoubaoUsageFetcher.swift`: 16.1%. Add rate-limit, 200/429, reset parsing,
  model fallback, and API error summary tests.
- `Sources/CodexBarCore/Providers/Abacus/AbacusUsageFetcher.swift`: 0.0%. Existing tests cover descriptor/snapshot/error
  semantics, but not API parsing or session-cookie fallback.
- `Sources/CodexBarCore/Providers/Factory/FactoryLocalStorageImporter.swift`: 0.0%. Add local-storage extraction and
  malformed-profile fixtures if this path remains important.
- `Sources/CodexBarCore/Providers/Bedrock/BedrockAWSSigner.swift`: fetch/parser coverage is decent, but the signer needs
  a golden SigV4 fixture.
- `Sources/CodexBarMacros/ProviderRegistrationMacros.swift`: no macro expansion tests found. Add
  `SwiftSyntaxMacrosTestSupport` coverage for happy path and diagnostics.

Resource gaps:

- `ProviderIconResourcesTests` hard-codes only a subset of icon slugs. Prefer iterating provider descriptors and asserting
  each referenced `ProviderIcon-*.svg` exists and loads.
- Localization tests check bundle loading, but not key parity. If partial translation is intentional, keep it as an audit;
  otherwise add a parity test for `en`, `pt-BR`, and `zh-Hans`.

## Repetition

The biggest duplication is repeated fixtures and contract-style tests. These are good candidates for extraction because
they reduce maintenance cost without deleting behavior coverage.

High-confidence hotspots:

- Isolated store setup: about 394 `SettingsStore(` and 301 `UsageStore(` call sites. The same in-memory store shape is
  repeated across files like `CodexManagedRoutingTests.swift`, `ProvidersPaneCoverageTests.swift`, and
  `CodexAccountScopedRefreshTestSupport.swift`.
- Codex auth fixture creation: `fakeJWT`, `base64URL`, and `writeCodexAuthFile` repeat across Codex routing,
  presentation, dashboard, provider pane, and account promotion tests.
- `URLProtocol` stubs: fetcher tests repeat the same handler, `canInit`, `startLoading`, and `stopLoading` body across
  many providers.
- API-key settings readers and token resolvers: DeepSeek, Venice, Kimi K2, Moonshot, StepFun, Zai, Alibaba, and similar
  providers repeat trim, quote stripping, primary/fallback environment priority, empty, and missing-key cases.
- Provider descriptor tests: identity, dashboard URL, source-mode, token-cost, and primary-provider assertions are mostly
  contract checks and could be table-driven.
- Status menu/AppKit fixtures: `makeStatusBarForTesting`, menu-card disabling, `StatusItemController` creation, and
  teardown repeat across the status-menu suites.
- `UsageMenuCardView.Model.make` setup is verbose and repeated in menu-card/model/storage tests.
- Codex OpenAI web characterization tests overlap with newer targeted dashboard/cache-scope tests. Keep one
  presentation-level smoke test, then map assertions before deleting anything.

Near-duplicate static clusters found by token similarity:

- `DeepSeekSettingsReaderTests.swift` and `VeniceSettingsReaderTests.swift`.
- `OpenCodeUsageParserTests.swift` and `OpenCodeGoUsageParserTests.swift`.
- `OpenCodeUsageFetcherErrorTests.swift` and `OpenCodeGoUsageFetcherErrorTests.swift`.
- `MenuDescriptorAntigravityTests.swift` and `MenuDescriptorKiloTests.swift`.
- `CLIOpenAIDashboardCacheTests.swift`, `CodexDashboardWorkedExampleParityTests.swift`, and
  `CodexWebDashboardStrategyAuthorityTests.swift`.
- `MenuCardModelCodexProjectionTests.swift`, `MenuCardOptionalUsageModelTests.swift`, and
  `MenuCardQuotaWarningMarkerTests.swift`.

## Recommended cleanup order

1. Add shared test-store factories in `TestStores.swift`: `makeIsolatedSettingsStore(...)` and `makeTestUsageStore(...)`.
2. Add a shared Codex auth fixture helper for writing auth files with optional email, plan, account ID, API key, and
   nested auth claims.
3. Add a shared HTTP stub/router for provider fetcher tests with request recording, response helpers, and body capture.
4. Convert provider API-key reader tests to a small table-driven token-reader contract.
5. Add provider descriptor contract tests for shared descriptor invariants.
6. Centralize status-menu/controller test fixtures.
7. Only then review overlapping characterization tests assertion-by-assertion for deletion.

Avoid a broad pruning pass before the fixture work. The current suite is repetitive, but much of the repetition protects
real provider and account-routing behavior. The fastest safe win is extracting shared fixtures and contracts, then using
the resulting smaller surface area to spot genuinely redundant tests.

## CI runtime plan

The macOS CI lane was running the suite sharder with `--group-size 1`, which means one `swift test --filter ...`
process per discovered suite. On this branch, `swift test` completes locally in about 21 seconds, but the suite sharder
discovers 315 macOS CI-filtered suites. Even when each suite has only a few milliseconds of actual test work, each
separate SwiftPM invocation pays package loading, build planning, test harness startup, and log overhead.

Immediate change:

- Run grouped shards in CI with `--group-size 12 --timeout 180`.
- Keep the existing timeout fallback: if a grouped shard times out, the script retries that shard suite-by-suite so the
  failing or hanging suite is still isolated.
- Emit a timing summary from `Scripts/ci_swift_test_by_suite.py` so future CI runs identify the slowest shards/suites.

Local smoke comparison on a warm build for the first eight CI-filtered suites:

- `--group-size 1 --limit-groups 8`: eight separate SwiftPM invocations.
- `--group-size 8 --limit-groups 1`: one SwiftPM invocation for the same eight suites.

The grouped run removes seven process startups for that slice while preserving the same selected tests. On CI, this is
the lowest-risk first cut at the 27-minute runtime before changing broader test behavior.

Full local CI-path simulation with `GITHUB_ACTIONS=true python3 Scripts/ci_swift_test_by_suite.py --group-size 8
--timeout 180 --timing-summary-limit 10` passed in 40 grouped shards without fallback before the first timeout-test
optimization pass. The slowest local shards were:

- 14.5s: `StatusMenuTests` through `SubprocessRunnerTests`, mostly timeout/subprocess and AppKit-ish menu tests.
- 9.1s: Claude OAuth credentials/keychain policy shard.
- 9.0s: CLI output/provider selection through Claude debug diagnostics, including Claude auto-fetch characterization.
- 7.1s: Codex account promotion/settings shard.
- 6.0s: cost usage fetcher/scanner shard.

Follow-up optimization pass:

- Lowered deliberate subprocess timeout-test budgets while preserving generous failure bounds.
- Avoided default PTY startup/settle waits in targeted TTY runner tests.
- Replaced one Claude auto-fetch characterization's fake CLI PTY execution with the existing `ClaudeStatusProbe` test
  override, preserving the CLI-before-web assertion without launching the test shell script.
- Switched the CI grouping target to `--group-size 12`, which reduces macOS CI SwiftPM test invocations to 27 grouped
  shards for the current suite count.

Current local CI-path simulation with `GITHUB_ACTIONS=true python3 Scripts/ci_swift_test_by_suite.py --group-size 12
--timeout 180 --timing-summary-limit 10` discovered 315 suites after skipping the macOS CI-only `CLIEntryTests`, then
passed all 27 grouped shards without fallback. The slowest local shards after the timeout cleanup were:

- 10.3s: `StatusMenuSwitcherClickTests` through `SyntheticSettingsReaderTests`.
- 9.2s: `ClaudeAutoFetcherCharacterizationTests` through `ClaudeOAuthFetchStrategyAvailabilityTests`.
- 5.5s: `CopilotExternalIdentifierTests` through `CostUsageScannerCodexPriorityTests`.
- 5.2s: `ClaudeWebEnterpriseUsageTests` through `CodexAccountsSectionStateTests`.
- 4.9s: `StatusItemAnimationCodexCreditsTests` through `StatusMenuPersistentRefreshTests`.

Next runtime work:

- Use the new CI timing summary to rank slow suites by real wall time.
- Replace fixed sleeps and polling loops with injectable clocks or deterministic store notifications where practical.
- Move live AppKit/WebKit/status-item behavior out of default PR tests unless the AppKit wiring itself is under test.
- Convert repeated provider contract suites to table-driven helpers once fixture extraction makes the overlap obvious.
- Add a deliberately small coverage lane for source-only coverage trends rather than running coverage on every PR shard.
