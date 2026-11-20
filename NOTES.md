# Notițe: Terraform, AWS, GitHub

Ce am învățat pe parcursul proiectului, pe scurt. Se actualizează la fiecare etapă.

## Harta proiectului (etapa 5, după partea B)

```
LAPTOP (D:\Projects\terraform-url-shortener)           AWS (eu-north-1, IAM e global)
┌──────────────────────────────────────┐
│ bootstrap/  (state LOCAL)            │ ── apply ──►  url-shortener-tfstate-…   (versioning, criptare,
│   main.tf, outputs.tf                │                 └─ dev/terraform.tfstate   fără acces public)
└──────────────────────────────────────┘                    ▲        │
┌──────────────────────────────────────┐                    │ citește/scrie state
│ rădăcina  (state REMOTE, în S3)      │ ───────────────────┘        │ + .tflock cât rulează
│   versions.tf backend.tf providers.tf│
│   variables.tf locals.tf             │ ── apply ──►  url-shortener-dev-links      (tabel DynamoDB)
│   dynamodb.tf iam.tf outputs.tf      │               url-shortener-dev-lambda     (rol IAM + politică)
└──────────────────────────────────────┘
        │ git push → PR → squash merge
        ▼
GITHUB: catalinstefanoiu/terraform-url-shortener   (codul, fără state și fără secrete)
```

## Fișierele proiectului

| Fișier | Ce conține | Pe scurt |
|---|---|---|
| `versions.tf` | blocul `terraform { required_version, required_providers }` | ce versiune de Terraform și de provider AWS cere proiectul |
| `backend.tf` | blocul `backend "s3"` | unde stă state-ul: `s3://url-shortener-tfstate-…/dev/terraform.tfstate`, cu lock |
| `providers.tf` | `provider "aws"` | regiunea și tag-urile puse automat pe toate resursele |
| `variables.tf` | `aws_region`, `project_name`, `environment` | intrările: valori care se pot schimba din exterior, cu validări |
| `locals.tf` | `data "aws_caller_identity"` + `locals` | calcule interne: ID-ul contului, prefixul de nume, tag-urile comune |
| `dynamodb.tf` | `resource "aws_dynamodb_table" "links"` | baza de date: cod scurt → URL lung |
| `iam.tf` | 2 × `data "aws_iam_policy_document"`, `aws_iam_role`, `aws_iam_role_policy` | identitatea lui Lambda (cine o poate purta) + ce are voie să facă |
| `outputs.tf` | `account_id`, `table_name` | ce afișează Terraform după `apply` |
| `bootstrap/main.tf` | bucket de state + versioning, criptare, acces public blocat | rulat o singură dată, cu state local |
| `bootstrap/outputs.tf` | `state_bucket_name` | numele bucket-ului de state (copiat în `backend.tf`) |
| `.gitignore` | ce NU urcă pe GitHub | state, `.terraform/`, `*.tfvars`, planuri salvate |
| `.terraform.lock.hcl` | versiunea exactă a providerilor + hash-uri | generat de `init`; se pune în Git, ca toți să folosească aceeași versiune |
| `NOTES.md` / `README.md` | documentație | notițele mele / prezentarea proiectului (refăcută în etapa 10) |

## Cum se compun valorile

**Numele bucket-ului**
```
variables.tf   project_name = "url-shortener"   environment = "dev"
     ↓                          ↓
locals.tf      name_prefix = "${var.project_name}-${var.environment}" = "url-shortener-dev"
     ↓
locals.tf      account_id  = data.aws_caller_identity.current.account_id = "145050022460"
     ↓
main.tf        bucket = "${local.name_prefix}-${local.account_id}-first"
               = "url-shortener-dev-145050022460-first"
```

**ID-ul contului**
```
~/.aws/credentials  (cheia userului admin)
     ↓
locals.tf      data "aws_caller_identity" "current"   ← întreabă AWS „cine sunt?”
     ↓
locals.tf      account_id = "145050022460"
     ↓                                ↓
main.tf        numele bucket-ului     outputs.tf   output "account_id"
```

**Tag-urile**
```
variables.tf   project_name = "url-shortener"   environment = "dev"
     ↓
locals.tf      common_tags = { Project = "url-shortener", Environment = "dev", ManagedBy = "terraform" }
     ↓
providers.tf   default_tags { tags = local.common_tags }
     ↓
ORICE resursă  tags_all = cele 3 tag-uri   (fără să scrii `tags` în main.tf)
```

**Regiunea**
```
variables.tf   aws_region = "eu-north-1"
     ↓
providers.tf   region = var.aws_region
     ↓
ORICE resursă  e creată în eu-north-1
(backend.tf are regiunea scrisă separat: backend-ul nu poate folosi variabile)
```

**Outputs**
```
main.tf        aws_s3_bucket.first   ── apply ──►  AWS creează bucket-ul
     ↓
               .bucket = "url-shortener-dev-…-first"     .arn = "arn:aws:s3:::url-shortener-dev-…-first"
     ↓
outputs.tf     bucket_name, bucket_arn
     ↓
terminal       terraform output  /  terraform output -raw bucket_name
```

**Bucket-ul de state și backend-ul**
```
bootstrap/main.tf   bucket = "url-shortener-tfstate-${data.aws_caller_identity.current.account_id}"
     ↓
bootstrap/outputs   state_bucket_name = "url-shortener-tfstate-145050022460"
     ↓  (copiat de mână: backend-ul nu acceptă variabile)
backend.tf          bucket = "url-shortener-tfstate-145050022460"
                    key    = "dev/terraform.tfstate"
     ↓
S3                  s3://url-shortener-tfstate-145050022460/dev/terraform.tfstate
```

**Ordinea în care lucrează Terraform**

Fișierele `.tf` din folder sunt citite **toate odată**, ca unul singur. Nu există ordine între fișiere; contează doar fazele comenzii și dependențele.

```
terraform init
  └─ citește blocurile terraform { } și backend "s3" { }
     (de aici: providerii de descărcat și unde e state-ul)

terraform plan / apply
  1. variabilele primesc valori   (default → TF_VAR_ → .tfvars → -var)
  2. validation                    (se oprește aici dacă o valoare e greșită)
  3. data sources + locals         (după dependențe)
  4. resursele                     (după dependențe, în paralel unde se poate)
  5. outputs
```

- Numele trebuie să fie unice în tot folderul (două `variable "environment"` în fișiere diferite = eroare).
- Subfolderele (`bootstrap/`) nu intră: fiecare folder e un proiect separat.

**Cine depinde de cine (ordinea calculată de Terraform)**
```
var.project_name ─┐
var.environment  ─┼─► local.name_prefix ─┐
                  └─► local.common_tags ─┼─► provider default_tags ─┐
data.aws_caller_identity ─► local.account_id ─┴─────────────────────┼─► aws_s3_bucket.first ─► outputs
var.aws_region ─► provider region ──────────────────────────────────┘
```

---

## Documentație (unde mă uit)

**Terraform Registry**: o pagină pentru fiecare resursă și data source.
- Adresa: `registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/<tip-fără-aws_>`, iar pentru data sources `.../docs/data-sources/<tip>`.
- Secțiunile unei pagini:
  - **Example Usage**: cod gata de adaptat.
  - **Argument Reference**: ce **scrii** în bloc (*Required* = obligatoriu, *Optional* = opțional).
  - **Attribute Reference**: ce poți **citi** după creare (`.arn`, `.id`, `.json`).
  - **Import**: cum aduci în Terraform o resursă creată manual.
  - Pe paginile generate automat (de exemplu providerul `archive`), aceleași informații stau sub **Schema**: *Required* + *Optional* = ce scrii, *Read-Only* = ce citești.
- Metoda mea: copiez din **Example Usage** exemplul cel mai apropiat, apoi verific fiecare linie în Argument Reference (sau Schema). Example Usage arată adesea și alte resurse legate între ele, de exemplu Lambda + rol + zip.
- Versiunea providerului se alege din meniul din stânga sus. `latest` e ok cât timp suntem pe 6.x.
- În VS Code: mouse-ul pe tipul resursei arată descrierea și un link spre documentație.
- **Cum adaug un provider nou** (de exemplu `archive`):
  - Pe pagina providerului (`registry.terraform.io/providers/hashicorp/archive`), butonul **USE PROVIDER** (dreapta sus) dă blocul gata făcut pentru `required_providers`.
  - Acolo versiunea e fixată exact (`"2.8.1"`). Eu o schimb în `"~> 2.8"`, ca să accept versiunile noi compatibile (2.8.x, 2.9…), dar nu 3.0, care poate strica ceva.
  - Al doilea bloc din snippet, `provider "archive" {}`, poate lipsi dacă pagina **Overview** spune *„requires no configuration”*. AWS, în schimb, are nevoie de `region`, deci de `providers.tf`.
  - Fără declarare, Terraform ghicește singur `hashicorp/archive` (după prefixul `archive_` din `archive_file`), dar fără limită de versiune. De aceea îl declarăm explicit.

**Limbajul Terraform**: developer.hashicorp.com/terraform/language (variabile, data sources, `lifecycle`…).

**AWS**:
- docs.aws.amazon.com: ghidul fiecărui serviciu.
- **Service Authorization Reference**: lista exactă de acțiuni IAM ale unui serviciu (de exemplu `dynamodb:GetItem`) și pe ce ARN-uri se aplică.
- **Rețeta pentru un `statement` IAM** (exemplu: logurile Lambda):
  1. **Ce acțiuni?** Ghidul serviciului sau politica gestionată de AWS pentru cazul meu. `AWSLambdaBasicExecutionRole` = `logs:CreateLogGroup`, `CreateLogStream`, `PutLogEvents` pe `"*"`.
  2. **Pe ce ARN?** Service Authorization Reference, secțiunea **Actions** (nu *Operations*: acolo scrie doar ce permisiuni cere un apel API). Steluța din `log-group*` înseamnă **obligatoriu** (antetul coloanei e *Resource types (\*required)*), nu „orice”. Coloana *Resource types* spune pe ce resursă lucrează acțiunea: `CreateLogStream` și `PutLogEvents` → `log-stream*`, cu ARN-ul `…:log-group:<grup>:log-stream:<stream>`. De aici vine `"${…log_group.arn}:*"`.
  3. **Cum scriu în Terraform?** Pagina `aws_iam_policy_document` (statement, sid, effect, actions, resources) + Attribute Reference la resursa țintă (`aws_cloudwatch_log_group.arn`, fără `:*` la final).
  4. **Strâng drepturile:** exemplele din documentație sunt largi (`"*"`, `arn:aws:logs:*:*:*`). Eu scot ce face deja Terraform (`CreateLogGroup`) și limitez resursa la grupul meu.

| Subiect | Link |
|---|---|
| `aws_caller_identity` | https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity |
| `aws_iam_policy_document` | https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document |
| `aws_iam_role` | https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role |
| `aws_iam_role_policy` | https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy |
| `aws_dynamodb_table` | https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table |
| `aws_lambda_function` | https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function |
| `aws_cloudwatch_log_group` | https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group |
| `archive_file` | https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file |
| Providerul `archive` (USE PROVIDER) | https://registry.terraform.io/providers/hashicorp/archive/latest |
| `required_providers` | https://developer.hashicorp.com/terraform/language/providers/requirements |
| Variabilele puse automat de Lambda | https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-runtime.html |
| Constrângeri de versiune (`~>`) | https://developer.hashicorp.com/terraform/language/expressions/version-constraints |
| Data sources (limbaj) | https://developer.hashicorp.com/terraform/language/data-sources |
| `TF_LOG` (debugging) | https://developer.hashicorp.com/terraform/internals/debugging |
| Roluri IAM | https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html |
| Chei temporare (STS) | https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp.html |
| Rolul de execuție Lambda | https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html |
| Elementele unei politici JSON | https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements.html |
| Acțiunile IAM pentru DynamoDB | https://docs.aws.amazon.com/service-authorization/latest/reference/list_dynamodb.html |
| Acțiunile IAM pentru CloudWatch Logs | https://docs.aws.amazon.com/service-authorization/latest/reference/list_logs.html |
| Politica `AWSLambdaBasicExecutionRole` | https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AWSLambdaBasicExecutionRole.html |
| Formatul ARN | https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_identifiers.html |

---

## Terraform

### Piesele de bază

Terraform lucrează cu trei piese:

- **Provider**: plugin-ul care știe să vorbească cu un anumit serviciu. Pentru AWS e `hashicorp/aws` și transformă codul tău în apeluri către API-ul AWS.
- **Resource**: un obiect real pe care Terraform îl creează și îl administrează, de exemplu un bucket S3.
- **State**: fișierul `terraform.tfstate`, în care Terraform ține minte ce a creat. La fiecare rulare compară trei lucruri: codul (ce vrei), state-ul (ce știe că a creat) și realitatea din AWS. Din diferența lor rezultă planul.

### Sintaxa

- **HCL** (HashiCorp Configuration Language) = limbajul fișierelor `.tf`. E **declarativ**: descrii *ce* vrei să existe, nu pașii prin care se creează.
- Blocul `terraform { ... }` spune ce versiune de Terraform și ce provideri folosește proiectul.
- Blocul `provider "aws" { ... }` configurează providerul (de exemplu regiunea). Cheile de acces **nu** se scriu aici: providerul le citește singur din `~/.aws`.
- `resource "aws_s3_bucket" "first"`: primul nume e **tipul** (definit de provider), al doilea e **numele local**, ales de tine. Împreună formează adresa resursei: `aws_s3_bucket.first`.
- Constrângeri de versiune: `~> 6.0` înseamnă „orice 6.x, dar nu 7.0”. Versiunile majore pot aduce schimbări incompatibile, de aceea le limităm.

### Organizarea fișierelor

- Terraform citește **toate** fișierele `.tf` din folder și le tratează ca pe unul singur. Numele fișierelor sunt doar o convenție, pentru oameni.
- Convenția uzuală: `versions.tf`, `providers.tf`, `variables.tf`, `locals.tf`, `main.tf`, `outputs.tf`.

### Variabile, locals, outputs, data sources

- **`variable`**: o valoare de intrare, care se poate schimba fără să editezi codul. Are `type`, `description`, `default` și, opțional, `validation`. Se folosește cu `var.nume`.
- **`validation`**: o regulă verificată înainte de orice schimbare. Dacă nu e respectată, Terraform se oprește cu mesajul tău de eroare.
- **`locals`**: valori calculate o singură dată și refolosite (prefixe de nume, tag-uri comune). Se folosesc cu `local.nume`. Nu pot fi schimbate din exterior.
- **`output`**: o valoare afișată după `apply`, pe care o citești cu `terraform output`. Pe outputs se bazează legătura cu alte unelte și, mai târziu, cu alte module.
- **`data`** (data source): **citește** informații care există deja (de exemplu ID-ul contului), fără să creeze nimic. Se folosește cu `data.tip.nume.atribut`.
- Data sources de două feluri: unele **întreabă AWS** (`aws_caller_identity` face un apel STS `GetCallerIdentity` la fiecare `plan`), altele doar **calculează local** (`aws_iam_policy_document`, `archive_file`, care face zip-ul pe laptop). Cum le deosebești:
  - **Regula:** dacă rezultatul conține ceva ce n-ai scris nicăieri (ID-ul contului), vine din AWS. Dacă e făcut doar din ce i-ai dat, e calcul local.
  - **Documentația** (registry.terraform.io): „Use this data source to **get**…” înseamnă că întreabă AWS, „**Generates**…” înseamnă că calculează local.
  - **Dovada:** `TF_LOG=DEBUG terraform plan 2>&1 | grep "HTTP Request Sent" | grep -o "rpc.method=[^ ]*" | sort | uniq -c` listează fiecare apel API pe care îl face planul.
- Un `plan` face apeluri pentru: citirea state-ului din S3 (`S3/GetObject`), verificarea identității (`STS/GetCallerIdentity`) și **refresh**, adică citirea fiecărei resurse din state ca să vadă dacă s-a schimbat ceva în AWS (`DynamoDB/DescribeTable`).
- `data "aws_iam_policy_document"`: scrii politica IAM în HCL în loc de JSON, iar `.json` ți-o dă gata convertită. Nu întreabă AWS nimic, doar generează text local, verificat de Terraform.
- **Interpolare**: `"${var.a}-${local.b}"` construiește un string din alte valori.
- Poți avea **mai multe blocuri `locals`**, în fișiere diferite. Terraform le adună pe toate.
- `path.module` = folderul în care stă fișierul `.tf`. Se folosește la căi relative (`"${path.module}/app/dist/index.js"`).
- `depends_on = [...]` = dependență explicită, pentru cazul în care Terraform nu o poate deduce din referințe.
- Resursele **independente** se creează **în paralel** (până la 10 odată). La C3, funcția Lambda a început să se creeze înainte să se termine actualizarea politicii, pentru că nu depinde de ea. De aceea exemplul oficial pune și politica în `depends_on`: funcția nu poate rula fără drepturile de log.
- Un **provider nou** (de exemplu `hashicorp/archive`) cere `terraform init`, care îl descarcă și îl adaugă în lock file.
- **`default_tags`** în provider: tag-uri puse automat pe **toate** resursele, ca să nu le repeți la fiecare.
- Variabilă **fără `default`** = obligatorie: Terraform cere valoarea la `plan`.
- Prefixe: `var.x`, `local.x`, `data.tip.nume.atribut`. O resursă se referă fără prefix: `aws_s3_bucket.first.arn`.
- **`tip.nume.atribut`**: `aws_dynamodb_table.links.name` = tipul (din provider) + numele local (ales de mine, `"links"`) + atributul citit (din Attribute Reference).
  - Orice **argument** pe care îl scriu se poate citi și ca atribut: `aws_lambda_function.api.function_name`. La Attribute Reference scrie *„…exports the following attributes in addition to the arguments above”*.
  - Data sources au în plus prefixul `data.`, deci 4 bucăți: `data.archive_file.lambda.output_path`.
  - Ce atribut pun într-un argument îmi spune **Argument Reference**-ul resursei care îl primește. Exemple: `aws_lambda_function.role` cere **ARN**-ul rolului (`.arn`), iar `aws_iam_role_policy.role` cere **numele** (`.id`, care la rol e chiar numele).
- `local` vs `variable`: variabila vine din exterior, local-ul e un calcul intern, pe care nu-l poate suprascrie nimeni.

### Valori pentru variabile (de la cea mai slabă la cea mai puternică)

1. `default` din `variables.tf`
2. variabilă de mediu `TF_VAR_environment=prod`
3. fișierul `terraform.tfvars` (citit automat)
4. fișiere `*.auto.tfvars` (citite automat)
5. `-var="environment=prod"` sau `-var-file=prod.tfvars` în linia de comandă

Ultima sursă câștigă.

### Tipuri

- `string` (text), `number`, `bool` (`true`/`false`).
- `list(string)`: listă ordonată, `["dev", "prod"]`.
- **`map(string)`**: set de perechi cheie = valoare, `{ Project = "x", Environment = "dev" }`.
- `object({...})`: structură cu câmpuri de tipuri diferite.

### Funcții utile

- `contains(listă, valoare)`: `true` dacă valoarea e în listă.
- `regex(tipar, text)`: verifică textul după un tipar; **dă eroare** dacă nu se potrivește. `^` = început, `$` = sfârșit, `[a-z0-9-]` = un caracter permis, `+` = unul sau mai multe.
- `can(expresie)`: `true` dacă expresia merge, `false` dacă dă eroare. Se folosește des cu `regex` în `validation`.
- `\"` = ghilimele în interiorul unui text.

### Graful de dependențe

- Ordinea fișierelor nu contează. Terraform deduce ordinea din **referințe**: dacă A folosește o valoare din B, B se face întâi (*dependență implicită*).
- Fluxul logic: `variables` (intrări) → `locals` + `data` (calcule, citiri) → `resource` (creare) → `output` (ieșiri).
- Exemplu, numele bucket-ului:

```
variables.tf:  environment = "dev" (default)
     ↓
locals.tf:     name_prefix = "${var.project_name}-${var.environment}" = "url-shortener-dev"
     ↓
main.tf:       bucket = "${local.name_prefix}-${local.account_id}-first" = "url-shortener-dev-145050022460-first"
     ↓
outputs.tf:    bucket_name = aws_s3_bucket.first.bucket
```

- `plan` cu altă valoare nu schimbă nimic; `terraform output` arată mereu ce e creat de fapt (din state).
- `terraform console` → `var.environment`: vezi ce valoare folosește Terraform acum.
- `No changes. Your infrastructure matches the configuration.` = codul, state-ul și AWS sunt identice.
- Cu un singur state, `dev` și `prod` nu pot exista în același timp: schimbarea mediului înlocuiește resursele (rezolvăm în etapa 7).

### Remote state

- State-ul local, ținut pe laptop, are trei probleme: se pierde odată cu laptopul, nu-l poate folosi altcineva (coleg, CI) și poate conține secrete.
- **Backend**: locul unde Terraform ține state-ul. `backend "s3"` îl ține într-un bucket S3.
- **Locking**: cât timp o rulare modifică state-ul, alta nu poate. Cu `use_lockfile = true` (Terraform 1.10+), lock-ul e un fișier `.tflock` în S3.
- **Problema oul-găina**: bucket-ul pentru state trebuie să existe *înainte* ca vreun proiect să-și pună state-ul în el. De aceea se creează separat, dintr-un folder `bootstrap/` cu state local.
- Bucket-ul de state nu e administrat de proiectul care își ține state-ul în el: un `destroy` ar șterge și locul unde e ținută evidența.

- Blocul `backend` **nu acceptă** variabile sau locals: valorile se scriu direct.
- `key` = calea fișierului de state în bucket (de exemplu `dev/terraform.tfstate`). Un bucket poate ține state-urile mai multor proiecte sau medii, fiecare la alt `key`.
- `terraform init -migrate-state` mută state-ul existent din vechiul backend (local) în cel nou (S3). După migrare, `terraform.tfstate` local rămâne gol (0 bytes), iar `.backup` are copia veche; amândouă se pot șterge.
- `.terraform/terraform.tfstate` **nu** e state-ul: e doar notița lui Terraform despre ce backend folosește folderul.
- Comenzile Terraform lucrează în folderul curent: verifică promptul înainte de `init`, `plan`, `apply`.
- Lock-ul apare în S3 ca `dev/terraform.tfstate.tflock` doar cât rulează o comandă; cu versioning, rămâne vizibil în istoric (Show versions).
- Cum funcționează lock-ul în S3: Terraform scrie `.tflock` cu condiția „doar dacă nu există deja”. Dacă există, S3 răspunde `412 PreconditionFailed` și Terraform afișează `Error acquiring the state lock`.
- Eroarea arată cine ține lock-ul: `Who` (user@calculator), `Operation` (apply, plan), `Created` (de când, în UTC), `ID` (pentru `force-unlock`).
- `apply` fără schimbări nu cere `yes` și eliberează lock-ul imediat.
- `-lock=false` dezactivează lock-ul: nu se folosește în practică.
- `terraform force-unlock <LOCK_ID>`: scoate un lock rămas blocat (de exemplu după un crash). Doar dacă ești sigur că nu mai rulează nimeni.

### Lifecycle

- `lifecycle { prevent_destroy = true }`: Terraform refuză orice plan care ar șterge resursa. Pentru resurse critice (state, baze de date).

### Comenzi

| Comandă | Ce face |
|---|---|
| `terraform init` | Descarcă providerii în `.terraform/` și creează lock file-ul. Se rulează prima dată și după orice schimbare de provideri. |
| `terraform fmt` | Formatează codul (indentare, aliniere). |
| `terraform validate` | Verifică sintaxa, fără să contacteze AWS. |
| `terraform plan` | Arată ce **ar** schimba. Nu modifică nimic. |
| `terraform apply` | Calculează planul, cere confirmare (`yes`) și execută schimbările. |
| `terraform output` | Afișează toate outputs-urile. Cu `-raw <nume>` afișează doar valoarea, fără ghilimele (bun pentru scripturi). |
| `terraform destroy` | Șterge **tot** ce administrează proiectul, după confirmare (`yes`). |
| `terraform state list` | Listează adresele resurselor din state. Doar citește. |
| `terraform state show <adresă>` | Arată tot ce știe state-ul despre o resursă. Doar citește. |
| `terraform plan -detailed-exitcode` | Răspunde prin codul de ieșire: `0` = nicio schimbare, `2` = există schimbări, `1` = eroare. Util în scripturi și în CI (etapa 8). |

- **Nu modifica din consolă resursele făcute cu Terraform.** Orice „Save” din consolă e **drift**: următorul `plan` arată `~` și `apply` readuce resursa la ce scrie în cod. Consola o folosim doar ca să ne uităm.

### Tag-uri

- Etichete `cheie = valoare` puse pe resurse. Nu schimbă numele sau comportamentul resursei.
- Folosite pentru a găsi resursele, a vedea costurile pe proiect și a ști cine deține ce.
- `tags` = ce scrii tu pe resursă; `tags_all` = acestea plus tag-urile comune din provider (`default_tags`, etapa 3).

- `terraform fmt` nu afișează nimic dacă fișierele erau deja formatate; altfel afișează numele fișierelor modificate.

### Citirea planului

- Simbolul din fața resursei spune ce se va întâmpla: `+` creare, `~` modificare pe loc (resursa rămâne aceeași, se schimbă doar un atribut).
- `-/+` înlocuire: unele atribute nu se pot schimba pe o resursă existentă (de exemplu numele unui bucket), așa că Terraform o șterge și o creează din nou. Atributul vinovat e marcat în plan cu `# forces replacement`.
- **Atenție la `-/+`**: resursa veche dispare cu tot cu datele din ea. Într-o firmă, un `-/+` neașteptat pe o bază de date e motiv de oprire.
- `- destroy`: resursa va fi ștearsă.
- **Ștergi blocul `resource` din cod → Terraform șterge resursa din AWS** la următorul `apply`. Codul descrie tot ce trebuie să existe; ce lipsește din cod dispare.
- O valoare care **depinde** de o resursă încă necreată apare tot `(known after apply)`, de exemplu `bucket = aws_s3_bucket.state.id`.
- Planul listează resursele **alfabetic**, nu în ordinea execuției. Ordinea reală o vezi la `apply`.
- Data source-urile apar ca `Reading...` la începutul planului: sunt citite înainte de orice altceva.
- **`<=` read (data resources)** + *„will be read during apply (config refers to values not yet known)”*: data source-ul depinde de o valoare care nu există încă. Exemplu: `lambda_permissions` are nevoie de ARN-ul log group-ului, care încă nu e creat. Terraform îl citește abia la `apply`.
  - Efect secundar: resursa care îl folosește (`aws_iam_role_policy`) arată tot JSON-ul vechi cu `-` și `-> (known after apply)`. Pare că se șterge tot, dar e doar „noul conținut încă nu se știe”. Noua politică va conține ambele reguli.
- `Changes to Outputs`: ce outputs se vor schimba după `apply`.
- `Refreshing state...`: înainte de plan, Terraform citește starea reală din AWS. Așa observă și schimbările făcute de altcineva din consolă.
- Ultimul rând e rezumatul, de citit mereu: `Plan: 1 to add, 0 to change, 0 to destroy.`
- `(known after apply)`: valori pe care le stabilește AWS abia la creare (ARN, ID, nume de domeniu). Ce ai scris tu în cod (numele bucket-ului, regiunea) apare deja în plan.
- `terraform plan -out=plan.tfplan` salvează planul, iar `terraform apply plan.tfplan` execută exact acel plan. Fără `-out`, `apply` recalculează planul, iar între timp ceva se poate schimba. CI/CD-ul din etapa 8 folosește varianta cu `-out`.

### Fișierele generate

| Fișier | Pe GitHub? | De ce |
|---|---|---|
| `.terraform/` | Nu | Providerii descărcați, pot avea sute de MB. Se recreează cu `init`. |
| `.terraform.lock.hcl` | **Da** | Fixează versiunea exactă a providerilor, ca toată lumea (și CI-ul) să folosească aceeași. |
| `terraform.tfstate` | Nu | Poate conține date sensibile. În etapa 4 îl mutăm în S3. Nu se editează niciodată de mână. |

---

## AWS

### Contul

- **Free plan**: primești credite, iar AWS nu te taxează; dacă se termină creditele, contul se oprește în loc să plătești. Se închide după 6 luni dacă nu faci upgrade la Paid.
- **Root user**: emailul cu care ai creat contul. Poate face orice, inclusiv să închidă contul. Îl folosești doar pentru urgențe și facturare.
- **MFA**: al doilea factor la login (cod din aplicația de autentificare). O parolă furată nu mai e suficientă.
- **Budgets**: un buget „Zero spend” trimite email la primul cost real.

### Regiuni

- Majoritatea resurselor (S3, Lambda, DynamoDB) trăiesc într-o **regiune** anume. Noi folosim `eu-north-1` (Stockholm).
- Dacă schimbi regiunea în consolă, nu-ți mai vezi resursele, deși ele există în continuare.
- **IAM e global**: userii, rolurile și politicile sunt aceleași în toate regiunile.

### IAM (Identity and Access Management)

- **User IAM**: o identitate pentru o persoană sau o aplicație. Lucrăm cu userul `admin`, nu cu root.
- **Politică (policy)**: document JSON care spune ce **acțiuni** sunt permise pe ce **resurse**. `AdministratorAccess` = orice acțiune pe orice resursă (`"Action": "*"`, `"Resource": "*"`).
- **AWS managed** vs **customer managed**: politici scrise de AWS vs politici scrise de tine (pe cele proprii le scriem în Terraform).
- **Grupuri**: pui politicile pe un grup și userii în grup. Util când ai mulți useri cu aceleași drepturi.
- **Roluri**: identități pe care le „preia” un serviciu (de exemplu Lambda). *Service-linked roles* sunt create automat de AWS: nu le șterge.
- Un rol are **două** politici:
  - **Trust policy** (`assume_role_policy`): **cine** poate purta rolul. Pentru noi, doar `lambda.amazonaws.com`.
  - **Permissions policy**: **ce** poate face cine îl poartă.
- Rolul nu are parolă și nici chei permanente. Cine îl preia primește de la **STS** chei **temporare**, care expiră singure. E mai sigur decât cheile unui user.
- **STS** (Security Token Service) e serviciul AWS care emite chei temporare: access key (`ASIA…`, nu `AKIA…` ca la chei permanente), secret și session token. `aws sts get-caller-identity` e tot un apel STS („cine sunt?”).
- La Lambda, AWS cere singur cheile de la STS și le pune în variabilele de mediu ale funcției (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`). SDK-ul le citește automat, deci codul nu atinge nicio cheie.
- `principals.type`: `Service` (un serviciu AWS), `AWS` (un cont, user sau rol), `Federated` (identitate din afară, de exemplu GitHub prin OIDC, în etapa 8).
- **Least privilege** (drepturi minime): dai doar acțiunile necesare, doar pe resursele necesare. Exemplu: `dynamodb:GetItem` + `PutItem` doar pe ARN-ul tabelului, nu `dynamodb:*` pe `*`.
- În Service Authorization Reference, `table*` la *Resource types* înseamnă că acțiunea se aplică obligatoriu pe un ARN de tabel. Coloana *Condition keys* (de exemplu `dynamodb:LeadingKeys`) permite restricții și mai fine, până la nivel de cheie.
- `max_session_duration = 3600` pe rol: cheile temporare de la STS țin cel mult 1 oră (se poate între 1 și 12 ore). Lambda le reînnoiește singură.
- În JSON-ul politicii, ordinea din `Action` nu contează (e o mulțime), iar o listă cu un singur element apare ca text simplu (`"Resource": "arn:..."`).
- Pagina unui rol în consolă: **Last activity** (când l-a folosit cineva ultima dată), **Tags** (din `default_tags`), **Generate policy based on CloudTrail events** (propune o politică minimă din ce a folosit rolul de fapt). O politică *Customer inline* are „Attached entities 0”, pentru că nu e un obiect separat.
- `effect` în `aws_iam_policy_document` e opțional, implicit `Allow`. Îl scriem totuși, ca să se citească mai ușor.
- **Inline policy** (`aws_iam_role_policy`): trăiește și moare odată cu rolul, ca o politică „personală”. **Managed policy** (`aws_iam_policy` + attachment): se poate atașa la mai multe roluri.
- Dacă IAM refuză o acțiune, eroarea e `AccessDenied` / `is not authorized to perform`.
- Datele de facturare sunt ascunse userilor IAM până când root-ul activează „IAM user and role access to Billing information”.

### S3

- Un bucket nou are implicit criptare (`AES256`), versionare oprită și acces doar pentru contul tău.
- În providerul AWS v4+, setările unui bucket sunt resurse separate: `aws_s3_bucket_versioning`, `aws_s3_bucket_server_side_encryption_configuration`, `aws_s3_bucket_public_access_block`. Se leagă de bucket prin `bucket = aws_s3_bucket.x.id`.
- **Versioning**: S3 păstrează fiecare versiune a unui fișier. Pentru state, înseamnă că poți reveni la o versiune bună dacă cea curentă se strică.
- **Public access block**: patru setări care blochează orice formă de acces public. Pentru state, toate pe `true`.
- Un bucket nu poate fi redenumit. Pentru alt nume se creează un bucket nou.
- `force_destroy = false` (implicit): Terraform refuză să șteargă un bucket care conține fișiere. E o plasă de siguranță împotriva pierderii datelor.
- ARN-ul unui bucket nu are regiune și cont (`arn:aws:s3:::nume`), pentru că numele e deja unic în toată lumea.

### DynamoDB

- Bază de date NoSQL, cheie-valoare. Un **tabel** conține **item-uri**, iar fiecare item e găsit după **cheia de partiție** (`hash_key`), aici `code`.
- Cheia de partiție e unică per item. DynamoDB îi aplică o funcție hash (un calcul care transformă textul într-un număr: același text dă mereu același număr) ca să decidă în ce **partiție** (zonă de stocare) pune item-ul, de aici numele `hash_key`. Așa știe direct unde să caute, oricât de mare ar fi tabelul.
- **`GetItem`** (după cheie) = rapid și ieftin. **`Scan`** (după alt câmp, de exemplu `url`) = citește tot tabelul, deci e lent și scump. Cheia o alegi după întrebarea pe care o pune aplicația cel mai des.
- `code` e `S` (string), pentru că `abc123` conține litere. Cu `N` ai avea doar cifre și ai pierde zerourile din față (`007` → `7`).
- În Terraform declari doar atributele care fac parte din chei. Restul câmpurilor (`url`, `created_at`) le adaugă aplicația, fără schemă.
- `billing_mode = "PAY_PER_REQUEST"`: plătești pe fiecare citire/scriere, fără capacitate de administrat. Ideal pentru trafic mic sau imprevizibil.
- **PITR** (point-in-time recovery): poți readuce tabelul la orice secundă din ultimele 35 de zile.
- În plan apar și opțiuni pe care nu le folosim încă: `global_secondary_index` (a doua cheie de căutare), `ttl` (item-urile expiră singure), `stream` (flux cu toate modificările). `read_capacity`/`write_capacity` contează doar la `PROVISIONED`.
- Un tabel nou e criptat automat cu o cheie deținută de AWS. De aceea `describe-table` arată `SSEDescription` gol: e criptarea implicită, nu lipsa ei.
- CLI: `put-item --item` (tot rândul), `get-item --key` / `delete-item --key` (doar cheia). Fără eroare = succes. `get-item` pe o cheie inexistentă dă răspuns gol, nu eroare.
- `put-item` cu o cheie care există deja **suprascrie** item-ul, fără avertisment. Ca să previi asta: condiția `attribute_not_exists(code)`, pe care o folosim în Lambda.
- `ResourceNotFoundException` = tabelul nu există: numele e greșit sau ești în altă regiune.
- Tipuri în DynamoDB JSON: `S` = string, `N` = număr, `BOOL`. Exemplu de item: `{"code": {"S": "abc123"}, "url": {"S": "https://..."}}`.

### Lambda

- O funcție Lambda = cod care rulează doar când e chemat (de un **eveniment**). Plătești per execuție, nu ai server de administrat.
- **Handler-ul** e funcția exportată pe care o cheamă Lambda (`export async function handler(event)`). Primește evenimentul și întoarce răspunsul.
- **Mediul de execuție** e refolosit între cereri. Ce e în afara handler-ului (clientul DynamoDB) se creează o singură dată, la *cold start*, apoi e refolosit, deci cererile următoare sunt mai rapide.
- Evenimentul de la API Gateway HTTP API (payload 2.0): `routeKey` („POST /links”), `pathParameters`, `body` (text), `isBase64Encoded`, `requestContext.domainName`.
- Răspunsul: `{ statusCode, headers, body }`. `302` + header-ul `location` = redirect temporar: browserul nu-l ține minte, deci fiecare click trece prin Lambda.
- `return` cu 4xx = răspuns normal. `throw` = **eroare de funcție**: API Gateway răspunde 500 și crește metrica **Errors**, pe care o urmărește alarma din partea E.
- **Scriere condiționată**: `ConditionExpression: "attribute_not_exists(code)"` scrie doar dacă cheia nu există. Altfel DynamoDB aruncă `ConditionalCheckFailedException`, iar codul încearcă alt cod.
- În Terraform (`lambda.tf`):
  - `data "archive_file"` face zip-ul din `app/dist/index.js`, chiar în timpul lui `plan`. Trebuie rulat `npm run build` înainte.
  - `output_file_mode = "0666"`: aceleași permisiuni de fișier în zip pe Windows și pe Linux (CI-ul din etapa 8), deci aceeași amprentă. Altfel planul ar cere update fără motiv.
  - `code_sha256` = amprenta zip-ului (`output_base64sha256`). Cod nou → amprentă nouă → Terraform urcă noua versiune. Terraform o compară cu amprenta reală din AWS (`CodeSha256`), deci vede și codul urcat manual din consolă (drift). Varianta veche, `source_code_hash`, e ținută doar în state și nu vede asta. `code_sha256` e opțional din providerul AWS 6.27.
  - `handler = "index.handler"` = fișierul `index.js` + funcția exportată `handler`.
  - `architectures = ["arm64"]` = procesoare Graviton, mai ieftine decât x86.
  - Log group-ul `/aws/lambda/<nume>` îl creăm noi, cu `retention_in_days`. Altfel Lambda l-ar crea singură, fără limită de timp și în afara Terraform.
  - API-ul AWS dă ARN-ul grupului **cu** `:*` la final (`aws logs describe-log-groups`). Terraform îl scoate din atributul `.arn`, deci în politică îl pui tu înapoi.
  - Verificare după apply: `CodeSha256` din `aws lambda get-function-configuration` = `code_sha256` din plan, adică AWS are exact zip-ul de pe laptop.
- Variabilele de mediu (`process.env.TABLE_NAME`) sunt setate din Terraform. Codul nu conține nume de resurse scrise direct. Le vezi în consolă (Lambda → Configuration → Environment variables) sau cu `aws lambda get-function-configuration --function-name <nume> --query Environment`. Pe laptop nu există, deci `process.env.TABLE_NAME` e `undefined`.
- **`process.env`**: `process` = obiectul global Node.js care descrie programul pornit. `env` = **variabilele de mediu**, perechi `NUME=valoare` primite de program la pornire, de la cine îl lansează (Windows, Lambda). E același lucru ca `$env:USERNAME` în PowerShell.
- Lambda pune singură și variabile proprii: `AWS_REGION` (de aici știe `new DynamoDBClient({})` regiunea) și `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN`, adică cheile temporare **ASIA…** ale rolului, din STS. SDK-ul le citește singur, deci în cod nu apar chei.
- Rutele HTTP API au **șabloane**: `GET /{code}`. Pentru adresa `/k3x9Qa`, evenimentul conține `routeKey: "GET /{code}"` (șablonul), `rawPath: "/k3x9Qa"` (adresa reală) și `pathParameters: { code: "k3x9Qa" }` (ce a „umplut” golul `{code}`). `routeKey` trebuie scris exact, cu spațiu: `"GET /{code}"`.
- `{code}` prinde **o singură** bucată de drum (`/k3x9Qa`, dar nu `/a/b`). Ca să prinzi mai multe bucăți există `{proxy+}`. Dacă nicio rută nu se potrivește, API Gateway răspunde singur `404 {"message":"Not Found"}`, iar Lambda nici nu e chemată.
- `GET /links` se potrivește cu `GET /{code}` (cu `code = "links"`), pentru că metoda contează: `POST /links` e altă regulă.

### ARN (Amazon Resource Name)

Adresa unică a oricărei resurse din AWS:

```
arn:aws:<serviciu>:<regiune>:<cont>:<resursă>
arn:aws:iam::145050022460:user/admin
```

Câmpul de regiune e gol la IAM, pentru că IAM e global. Exemplu cu toate câmpurile: `arn:aws:dynamodb:eu-north-1:145050022460:table/url-shortener-dev-links`. În politicile IAM, `resources` primește ARN-uri.

### API, SDK, CLI

- Orice acțiune în AWS e un apel **API** prin HTTPS (de exemplu `dynamodb:GetItem`).
- **SDK** (Software Development Kit) = biblioteca unui limbaj de programare care face aceste apeluri. Lambda va folosi `@aws-sdk/client-dynamodb` (TypeScript).
- Consola web, AWS CLI, Terraform și SDK-urile sunt toate doar clienți ai aceluiași API.

### CloudTrail

- Jurnalul contului: cine, ce apel API, când, de unde. **Event history** păstrează gratuit ultimele 90 de zile.
- Exemplu: fiecare `terraform plan` apare ca `GetCallerIdentity` (sursa `sts.amazonaws.com`), cu user agent-ul `Terraform/1.17.1`.
- Filtrare: **Lookup attributes**, un singur atribut odată (Event source, Event name, User name, Read-only…). `Read-only = false` arată doar modificările. Apelurile de citire, ca `GetCallerIdentity`, nu apar cu filtrul ăsta.
- **CloudTrail ≠ logurile aplicației.** CloudTrail răspunde la „cine a făcut ce în contul AWS”. Ce scrie codul tău (`console.log`, erori) ajunge în **CloudWatch Logs**. Event history arată doar *management events* (creare, ștergere, configurare), nu și *data events* precum `GetItem`/`PutItem`. Pe acelea le poți activa separat, cu plată.
- Data events pentru DynamoDB = operațiile pe item-uri (`GetItem`, `PutItem`, `UpdateItem`, `DeleteItem`, `Query`, `Scan`, `Batch*`). Se activează pe un *trail* și costă aproximativ 0,10 USD la 100.000 de evenimente.
- Evenimentele serviciilor globale (IAM, `CreateRole`) apar în Event history din regiunea **us-east-1** (N. Virginia), nu din eu-north-1.
- În eveniment, `accessKeyId` arată tipul de cheie: `AKIA…` = cheie permanentă a unui user, `ASIA…` = cheie temporară de la STS (rol).
- Se înregistrează și apelurile eșuate (`errorCode`). Exemplu: la crearea tabelului, `UpdateContinuousBackups` a eșuat de 5 ori („Please retry later”), iar providerul a reîncercat singur până a mers. De aici cele 34 de secunde.

### Chei de acces și AWS CLI

- O cheie de acces = **Access key ID** + **Secret access key**. Cine o are poate face tot ce face userul respectiv.
- Nu o pui niciodată în cod, în chat sau pe GitHub. Nu crea niciodată chei pentru root.
- `aws configure` le salvează în `~/.aws/credentials`, de unde le citesc automat AWS CLI și Terraform, indiferent din ce folder rulezi.
- `aws sts get-caller-identity` arată cu ce identitate rulezi. Primul lucru de verificat când ceva nu merge.
- Forma oricărei comenzi: `aws <serviciu> <acțiune> --opțiuni`. Acțiunile `get-*`, `list-*` și `describe-*` doar citesc.
- `--query '...'` (JMESPath) filtrează răspunsul și păstrează doar câmpul cerut, de exemplu `--query 'Role.AssumeRolePolicyDocument'`. `--output text|json|table` schimbă formatul.

---

## Git și GitHub

- `.gitignore` se pune **înainte** de primul commit, ca state-ul și secretele să nu poată ajunge pe GitHub.
- `git init -b main` creează repo-ul local cu branch-ul principal numit `main`.
- `gh auth login` conectează GitHub CLI la contul tău.
- `gh repo create <nume> --public --source=. --push` creează repo-ul pe GitHub din folderul curent și urcă commit-urile.
- Codul, comentariile și mesajele de commit le scriem în engleză, pentru că se văd pe GitHub.
- Un commit e deja un punct de salvare: poți reveni oricând la el. Branch-ul nu e o copie de siguranță, ci un loc unde lucrezi separat de `main`.
- Fluxul folosit în echipe: branch nou → commit-uri → push → **pull request** (PR) → review → merge în `main`. În etapa 8, CI-ul va rula `terraform plan` automat pe fiecare PR.
- Comenzi: `git switch -c <branch>` (creează și trece pe branch), `git push -u origin <branch>`, `gh pr create --fill`, `gh pr merge --squash --delete-branch`, apoi `git switch main` și `git pull`.
- `git add <fișiere>` pune modificările în **staging** („astea intră în următorul commit”). `git commit -m "..."` salvează tot ce e în staging ca un punct în istorie, **doar local**. Pe GitHub ajunge abia la `git push`.
- **Branch-urile nu izolează infrastructura.** State-ul și resursele din AWS sunt aceleași, indiferent pe ce branch ești. Un `apply` dat de pe un branch modifică resursele reale.

---

## Node.js, npm și TypeScript (aplicația din `app/`)

- **Node.js** rulează JavaScript în afara browserului. Lambda folosește runtime-ul `nodejs24.x` (suport până în aprilie 2028), aceeași versiune ca pe laptop.
- **npm** instalează pachete (biblioteci) din registry-ul npm.

| npm | echivalent Terraform | rol |
|---|---|---|
| `package.json` | `versions.tf` | ce pachete și ce interval de versiuni cere proiectul |
| `package-lock.json` | `.terraform.lock.hcl` | versiunile exacte instalate. **Se pune în Git.** |
| `node_modules/` | `.terraform/` | pachetele descărcate, refăcute de `npm install`. **NU se pune în Git.** |

- `package-lock.json` e creat de **primul** `npm install` și actualizat de fiecare `npm install` următor. Pentru fiecare pachet ține `version`, `resolved` (de unde s-a descărcat) și `integrity` (hash `sha512`, ca hash-urile din `.terraform.lock.hcl`).
- Lock-ul conține și pachetele **indirecte** (dependențele dependențelor). La noi: 5 directe, 80 în total. Conține și variantele esbuild pentru toate sistemele (Windows, Linux, Mac), dar se instalează doar cea potrivită (`@esbuild/win32-x64`).
- `npm ci` instalează **exact** ce scrie în lock, fără să-l modifice. Se folosește în CI (etapa 8).
- `dependencies` ajung în codul care rulează în Lambda (SDK-ul AWS). `devDependencies` sunt doar unelte de dezvoltare (TypeScript, esbuild, tipuri).
- `^3.1171.0` = orice 3.x de la 3.1171.0 în sus, fără 4.0. E ca `~> 6.0` din Terraform.
- **TypeScript** = JavaScript cu tipuri, iar `tsc --noEmit` verifică tipurile fără să genereze fișiere. **esbuild** împachetează codul și toate pachetele folosite într-un singur fișier (`dist/index.js`), adică ce urcă în Lambda.
- `npm run <script>` rulează o comandă din secțiunea `scripts` a `package.json`. `npx <unealtă>` rulează o unealtă instalată în proiect.
- TypeScript de bază, cum apare în `handler.ts`:
  - `const` = valoare care nu se mai schimbă.
  - `async`/`await` = „așteaptă răspunsul” (de la DynamoDB) fără să blocheze.
  - `try { … } catch (err) { … }` = „încearcă; dacă apare o eroare, sari în catch”.
  - `throw` = aruncă o eroare mai departe.
  - `for (let i = 1; i <= 3; i++)` = repetă de 3 ori. `continue` = sari direct la următoarea repetare.
  - `instanceof` (cu `o` mic) = „e eroarea de tipul X?”.
  - `` `text ${valoare}` `` = interpolare, ca în Terraform.
  - `const { url } = obiect` = **destructurare**: ia câmpul `url` din obiect într-o variabilă cu același nume. E același lucru cu `const url = obiect.url`.
  - `string | undefined` = „text SAU lipsă” (tip uniune).
  - `Promise<T>` = „îți dau un T, dar mai târziu”. Orice funcție `async` întoarce un `Promise`.
  - `err instanceof X` întreabă: „eroarea prinsă e de tipul X?”. `continue` în `catch` sare la următoarea repetare a buclei `for`.
- npm-ul nou nu mai rulează automat scripturile de instalare ale pachetelor (`npm warn install-scripts`). E o protecție împotriva pachetelor compromise. esbuild merge și fără.

## Windows și unelte

- `winget install <pachet>` instalează programe din terminal.
- **PATH** e lista de foldere în care terminalul caută programe. Un terminal o citește doar când pornește, deci după o instalare trebuie redeschis.
- În Git Bash, `D:\Projects` se scrie `/d/Projects`.
- Extensia **HashiCorp Terraform** din VS Code dă culori, autocompletare și erori direct în editor.
- **Auto-import în VS Code:** când scrii un nume care încă nu există (de exemplu `json`), VS Code poate adăuga singur un `import` greșit sus în fișier (`import { json } from "node:stream/consumers"`). Verifică importurile după ce scrii cod. Când apare lista de sugestii, `Esc` o închide fără să accepte nimic. Auto-importurile se pot opri din Settings, căutând „auto imports”.
- `Shift+Alt+F` (Format Document) aranjează indentarea codului TypeScript.
- Dacă lași o ghilimea deschisă, Bash așteaptă continuarea comenzii (`>`). `Ctrl+C` anulează.
- **Git Bash strică argumentele care încep cu `/`**: crede că sunt căi Linux și le transformă în `C:/Program Files/Git/...`. Exemplu: `/aws/lambda/...` dă eroarea `failed to satisfy constraint`. Soluția: `MSYS_NO_PATHCONV=1` în fața comenzii (`MSYS_NO_PATHCONV=1 aws logs tail /aws/lambda/...`). În PowerShell nu apare problema.
- În **PowerShell 5.1**, JSON-ul trimis la `aws` pierde ghilimelele. Le scrii ca `\"` în interiorul `'...'`, de exemplu `'{\"code\":{\"S\":\"test1\"}}'`. În Git Bash merge JSON-ul normal.
