# Muistio: GitHub workflow Azureen ilman sovellusrekisteröintiä

Kun GitHub workflow tekee deployn Azureen, sovellusrekisteröintiä ei tarvita. Käytä käyttäjän määrittämää hallittua identiteettiä (UAMI) ja federoitua tunnistetta. Tiimi luo ne itse omaan tilaukseensa, eikä tästä reposta tilata mitään.

## Milloin tämä polku sopii

* Workflow luo tai päivittää Azuren resursseja
* Workflow julkaisee sovelluksen App Serviceen, Container Appsiin, AKS:ään tai vastaavaan
* Tunnistautujana on workflow, ei käyttäjä

## Milloin tarvitaan sovellusrekisteröinti

* Sovellukseen kirjaudutaan käyttäjänä (redirect URI)
* Sovellus tarvitsee delegoituja oikeuksia
* Työkuorma ajetaan Azuren ulkopuolella ja tarvitsee client secretin

Näissä tapauksissa tee tilaus tämän repon issue lomakkeella.

## Vaiheet

1. Luo identiteetti.

   ```bash
   az identity create --name id-myapp-deploy --resource-group rg-myapp
   ```

2. Lisää federoitu tunniste. Kentän `subject` arvo rajaa, mikä repo ja haara tai environment saa käyttää identiteettiä.

   ```bash
   az identity federated-credential create \
     --name github-main \
     --identity-name id-myapp-deploy \
     --resource-group rg-myapp \
     --issuer https://token.actions.githubusercontent.com \
     --subject repo:<organisaatio>/<repo>:ref:refs/heads/main \
     --audiences api://AzureADTokenExchange
   ```

   Jos workflow käyttää environmentia, subject on muotoa `repo:<organisaatio>/<repo>:environment:<nimi>`.

3. Anna identiteetille rooli kohteeseen. Rajaa rooli resurssiryhmään, älä koko tilaukseen.

   ```bash
   az role assignment create \
     --assignee <identiteetin principalId> \
     --role Contributor \
     --scope /subscriptions/<tilaus>/resourceGroups/rg-myapp
   ```

4. Kirjaudu workflowssa.

   ```yaml
   permissions:
     id-token: write
     contents: read

   steps:
     - uses: azure/login@v2
       with:
         client-id: ${{ vars.AZURE_CLIENT_ID }}
         tenant-id: ${{ vars.AZURE_TENANT_ID }}
         subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
   ```

   Arvot eivät ole salaisia, joten ne voi tallentaa repon muuttujiin.

## Huomioita

* Tallennettuja salaisuuksia ei ole, joten mitään ei tarvitse kierrättää
* Subject ei tue jokerimerkkejä. Jokainen haara tai environment tarvitsee oman tunnisteensa.
* Suosi environmentia haaran sijaan, koska environmentille voi asettaa hyväksyjät
