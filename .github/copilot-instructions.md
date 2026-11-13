# Copilot instructions

This repository vends Microsoft Entra app registrations with a GitOps model. YAML manifests under `apps/` describe the desired state. The PowerShell module in `src/AppVending` validates manifests, computes the difference to the actual state and applies it.

Read `AGENTS.md` for the commands, layout and rules. The points below matter most in review and code generation.

## Design constraints

* A run with no manifest change must not write anything. Treat any code that writes without first comparing state as a defect.
* Decision logic is pure and unit tested. Graph and Azure calls live in thin wrappers.
* There is no state file. Applications are identified by `uniqueName`, which equals the manifest `name`.
* Client secrets are written to the team Key Vault through Azure Resource Manager. The value must never be logged, returned from a function that feeds a comment, or passed between workflow jobs.
* The pipeline does not grant admin consent and does not create federated credentials.

## PowerShell conventions

* PowerShell 7.4, `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`.
* One function per file, approved verbs, comment based help on every function.
* Use `Get-DictionaryValue` for optional manifest keys. Do not index into values that may be missing.
* Return objects, not formatted text. Formatting belongs to the caller.
* New behaviour comes with Pester tests in `tests/unit`. Use `InModuleScope AppVending` for private functions.

## Workflow conventions

* Pin every action to a full commit SHA with the version in a trailing comment.
* Declare `permissions` on every workflow and keep them minimal.
* Never interpolate issue, pull request or manifest content into a `run` step. Pass it through an environment variable or read it from the API.
* Jobs that hold Entra or Azure credentials run only from `main` behind a protected environment.

## Language

`README.md` and `docs/` are in Finnish. Everything else is in English.
