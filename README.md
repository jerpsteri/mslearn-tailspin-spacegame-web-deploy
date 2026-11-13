# Entra App Registration Vending

Tämä repo hallitsee Microsoft Entran sovellusrekisteröintejä GitOps mallilla. Jokainen sovellusrekisteröinti kuvataan omassa manifestissaan, ja putki pitää Entran tilan manifestien mukaisena. Git on ainoa totuuden lähde, ja kaikki muutokset kulkevat pull requestin kautta.

## Toimintaperiaate

* Manifesti kuvaa yhden sovellusrekisteröinnin halutun tilan. Tiedostot sijaitsevat polussa `apps/<tiimi>/<nimi>.yaml`.
* Moottori lukee nykytilan, laskee eron haluttuun tilaan ja kirjoittaa vain muuttuneet kohdat. Toinen ajo ilman muutoksia ei kirjoita mitään.
* Tilatiedostoa ei ole. Sovellus tunnistetaan manifestin `name` kentästä, joka tallennetaan Entraan muuttumattomana tunnisteena.
* Client secret toimitetaan tiimin omaan Key Vaultiin. Arvo ei näy Gitissä, lokeissa eikä kommenteissa.
* Secretin elinkaari ja kierrätys määräytyvät tiedostosta `config/policy.yaml`. Oletuksena secret on voimassa 730 päivää ja uusi luodaan 30 päivää ennen vanhan päättymistä.

## Toteutuksen tila

Repo rakennetaan vaiheittain. Valmiina on vaihe 1.

1. Runko, schema, policy, vertailumoottori ja secretien tilakone yksikkötesteineen (valmis)
2. CI, plan kommentti pull requestiin ja tilaus issuen kautta
3. Putken identiteettien käyttöönotto ja deploy
4. Toimitus Key Vaultiin ja ajastettu kierrätys
5. Dokumentaatio kansioon `docs`

Kehittäjän muistio GitHub workflown tunnistautumisesta Azureen ilman sovellusrekisteröintiä löytyy tiedostosta `docs/notes/uami-github.md`.

## Rakenne

```
.github/              Copilotin ohjeet ja CODEOWNERS
apps/                 Manifestit tiimeittäin
config/               Tenantin asetukset ja policy
docs/                 Dokumentaatio ja muistiot
schemas/              Manifestin JSON Schema
scripts/              Apuskriptit
src/AppVending/       PowerShell moduuli
  Public/             Moduulin julkiset funktiot
  Private/            Validointi, vertailu ja secretien tilakone
tests/                Yksikkötestit ja testiaineisto
AGENTS.md             Ohjeet koodausagenteille
```

## Manifestin esimerkki

```yaml
apiVersion: appvending/v1
name: payments-api-prod
displayName: Payments API (prod)
description: Backend API for payment processing.
owners:
  - alice@contoso.com
  - bob@contoso.com
web:
  redirectUris:
    - https://payments.contoso.com/signin-oidc
requiredResourceAccess:
  - resource: Microsoft Graph
    delegated:
      - User.Read
keyVault:
  resourceId: /subscriptions/<tilaus>/resourceGroups/<ryhmä>/providers/Microsoft.KeyVault/vaults/<vault>
secrets:
  - name: backend
```

Kaikki kentät ja niiden rajoitteet on kuvattu tiedostossa `schemas/app.schema.json`.

## Paikallinen kehitys

Vaatimuksena on PowerShell 7.4 tai uudempi. Tarvittavat moduulit ja niiden versiot on lueteltu tiedostossa `requirements.psd1`.

```powershell
./scripts/Install-Dependencies.ps1
Invoke-Pester -Path tests
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

Manifestien validointi samoilla säännöillä kuin putkessa:

```powershell
Import-Module ./src/AppVending/AppVending.psd1
Test-AppManifest -Path apps
```

Komento ei tulosta mitään, kun kaikki manifestit ovat kunnossa. Muussa tapauksessa se palauttaa yhden rivin jokaisesta rikkeestä.

## Kielikäytäntö

README ja `docs` kansion sisältö kirjoitetaan suomeksi. Koodi, kommentit, manifestit, asetukset ja commit viestit kirjoitetaan englanniksi.
