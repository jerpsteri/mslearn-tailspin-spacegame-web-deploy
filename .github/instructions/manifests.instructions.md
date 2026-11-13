---
applyTo: "apps/**/*.yaml"
---

# Reviewing app registration manifests

Schema and policy violations are caught by CI. Focus the review on judgement calls that automated checks cannot make.

## What to assess

* **Purpose.** The `description` should say what the application does and who uses it. Ask for more detail when it is vague, because approvers rely on it.
* **Is an app registration needed at all.** When the described purpose is a GitHub workflow that deploys to Azure, point the author to `docs/notes/uami-github.md`. A user assigned managed identity with a federated credential fits that case and needs no manifest here.
* **Permissions.** Compare `requiredResourceAccess` with the stated purpose. Flag permissions the description does not justify and suggest a narrower one when it exists. Application permissions deserve more scrutiny than delegated ones.
* **Secrets.** A secret is appropriate for workloads that run outside Azure or cannot use a managed identity. Mention it when the description suggests an Azure hosted workload that could avoid a secret. Do not block on it.
* **Key Vault.** Check that the vault name and resource group in `keyVault.resourceId` plausibly belong to the team that owns the manifest folder. A resource ID copied from another team's manifest sends the secret to the wrong vault.
* **Owners.** Owners should be people from the owning team, not shared mailboxes or service accounts.
* **Redirect URIs.** Host names should belong to the organisation and match the environment implied by the application name.

## What not to do

* Do not suggest fields that are not in `schemas/app.schema.json`.
* Do not suggest changing `name` on an existing manifest. The name is immutable, and a rename deletes the application and creates a new one.
* Do not ask for lifetime or rotation settings in the manifest. They come from `config/policy.yaml`.
