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

### Comenzi

| Comandă | Ce face |
|---|---|
| `terraform init` | Descarcă providerii în `.terraform/` și creează lock file-ul. Se rulează prima dată și după orice schimbare de provideri. |
| `terraform fmt` | Formatează codul (indentare, aliniere). |
| `terraform validate` | Verifică sintaxa, fără să contacteze AWS. |
| `terraform plan` | Arată ce **ar** schimba. Nu modifică nimic. |
| `terraform apply` | Calculează planul, cere confirmare (`yes`) și execută schimbările. |
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

---

## Windows și unelte

- `winget install <pachet>` instalează programe din terminal.
- **PATH** e lista de foldere în care terminalul caută programe. Un terminal o citește doar când pornește, deci după o instalare trebuie redeschis.
- În Git Bash, `D:\Projects` se scrie `/d/Projects`.
- Extensia **HashiCorp Terraform** din VS Code dă culori, autocompletare și erori direct în editor.
