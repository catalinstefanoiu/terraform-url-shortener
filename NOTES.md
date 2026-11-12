# Notițe: Terraform, AWS, GitHub

Ce am învățat pe parcursul proiectului, pe scurt. Se actualizează la fiecare etapă.

---

## Terraform

### Piesele de bază

Terraform lucrează cu trei piese:

- **Provider**: plugin-ul care știe să vorbească cu un anumit serviciu. Pentru AWS e `hashicorp/aws` și transformă codul tău în apeluri către API-ul AWS.
- **Resource**: un obiect real pe care Terraform îl creează și îl administrează, de exemplu un bucket S3.
- **State**: fișierul `terraform.tfstate`, în care Terraform ține minte ce a creat. La fiecare rulare compară trei lucruri: codul (ce vrei), state-ul (ce știe că a creat) și realitatea din AWS. Din diferența lor rezultă planul.

### Sintaxa

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
- **Interpolare**: `"${var.a}-${local.b}"` construiește un string din alte valori.
- **`default_tags`** în provider: tag-uri puse automat pe **toate** resursele, ca să nu le repeți la fiecare.
- Variabilă **fără `default`** = obligatorie: Terraform cere valoarea la `plan`.
- Prefixe: `var.x`, `local.x`, `data.tip.nume.atribut`. O resursă se referă fără prefix: `aws_s3_bucket.first.arn`.
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
- O valoare care **depinde** de o resursă încă necreată apare tot `(known after apply)`, de exemplu `bucket = aws_s3_bucket.state.id`.
- Planul listează resursele **alfabetic**, nu în ordinea execuției. Ordinea reală o vezi la `apply`.
- Data source-urile apar ca `Reading...` la începutul planului: sunt citite înainte de orice altceva.
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
- Datele de facturare sunt ascunse userilor IAM până când root-ul activează „IAM user and role access to Billing information”.

### S3

- Un bucket nou are implicit criptare (`AES256`), versionare oprită și acces doar pentru contul tău.
- În providerul AWS v4+, setările unui bucket sunt resurse separate: `aws_s3_bucket_versioning`, `aws_s3_bucket_server_side_encryption_configuration`, `aws_s3_bucket_public_access_block`. Se leagă de bucket prin `bucket = aws_s3_bucket.x.id`.
- **Versioning**: S3 păstrează fiecare versiune a unui fișier. Pentru state, înseamnă că poți reveni la o versiune bună dacă cea curentă se strică.
- **Public access block**: patru setări care blochează orice formă de acces public. Pentru state, toate pe `true`.
- Un bucket nu poate fi redenumit. Pentru alt nume se creează un bucket nou.
- `force_destroy = false` (implicit): Terraform refuză să șteargă un bucket care conține fișiere. E o plasă de siguranță împotriva pierderii datelor.
- ARN-ul unui bucket nu are regiune și cont (`arn:aws:s3:::nume`), pentru că numele e deja unic în toată lumea.

### ARN (Amazon Resource Name)

Adresa unică a oricărei resurse din AWS:

```
arn:aws:<serviciu>:<regiune>:<cont>:<resursă>
arn:aws:iam::145050022460:user/admin
```

Câmpul de regiune e gol la IAM, pentru că IAM e global.

### Chei de acces și AWS CLI

- O cheie de acces = **Access key ID** + **Secret access key**. Cine o are poate face tot ce face userul respectiv.
- Nu o pui niciodată în cod, în chat sau pe GitHub. Nu crea niciodată chei pentru root.
- `aws configure` le salvează în `~/.aws/credentials`, de unde le citesc automat AWS CLI și Terraform, indiferent din ce folder rulezi.
- `aws sts get-caller-identity` arată cu ce identitate rulezi. Primul lucru de verificat când ceva nu merge.

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
- **Branch-urile nu izolează infrastructura.** State-ul și resursele din AWS sunt aceleași, indiferent pe ce branch ești. Un `apply` dat de pe un branch modifică resursele reale.

---

## Windows și unelte

- `winget install <pachet>` instalează programe din terminal.
- **PATH** e lista de foldere în care terminalul caută programe. Un terminal o citește doar când pornește, deci după o instalare trebuie redeschis.
- În Git Bash, `D:\Projects` se scrie `/d/Projects`.
- Extensia **HashiCorp Terraform** din VS Code dă culori, autocompletare și erori direct în editor.
