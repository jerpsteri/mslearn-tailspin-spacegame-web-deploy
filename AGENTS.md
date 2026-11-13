# Agent instructions

This repository vends Microsoft Entra app registrations from YAML manifests. A PowerShell module reconciles Entra with the manifests stored in Git.

## Commands

Run these from the repository root with PowerShell 7.4 or later.

```powershell
./scripts/Install-Dependencies.ps1
Invoke-Pester -Path tests
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

Both the tests and the analyzer must pass with no findings before a change is complete.

## Layout

| Path | Content |
| --- | --- |
| `apps/<team>/<name>.yaml` | Manifests, one per app registration |
| `config/policy.yaml` | Guardrails and secret lifecycle settings |
| `schemas/app.schema.json` | Manifest schema |
| `src/AppVending/Public` | Exported functions, one per file |
| `src/AppVending/Private` | Internal functions, one per file, grouped by concern |
| `tests/unit` | Pester tests, one file per function |

## Rules

1. Idempotency is the core requirement. A second run with no manifest change must produce no writes. Any change to the reconcile or secret logic needs a test that applies a plan and asserts the next plan is empty.
2. Keep decision logic pure. `Compare-AppRegistration` and `Get-SecretPlan` take state as parameters and return actions. They never call Graph or Azure. Network access belongs in thin wrapper functions.
3. Plan and apply share the same code path. Do not add logic that only runs in one of them.
4. Secret values never reach logs, output, comments, files or test fixtures.
5. No state files. All state is read from Entra and Key Vault at run time.
6. Every new manifest field needs a schema entry, a policy decision, handling in the diff and tests for all three.
7. Add a new policy rule to `Test-ManifestPolicy` with a stable rule identifier and tests for the passing and the failing case.
8. Pin versions. Module versions live in `requirements.psd1`. Workflow actions are pinned to a commit SHA.

## Language

`README.md` and everything under `docs/` are written in Finnish, in a plain professional style without semicolons or dashes as punctuation. Everything else is written in English, including code, comments, manifests, configuration, commit messages and pull request text.

## Out of scope for automated changes

Do not change `config/tenant.yaml`, `.github/CODEOWNERS` or the constants in `src/AppVending/AppVending.psm1` unless the task explicitly asks for it. The constants identify resources the pipeline already manages, and changing them orphans those resources.
