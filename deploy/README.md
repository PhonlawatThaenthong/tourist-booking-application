# Deploy Backend ขึ้น GCP (Compute Engine + Nginx + GitHub Actions CD)

สถาปัตยกรรม: VM 1 เครื่อง (Ubuntu 24.04) ใช้ Nginx บน host ทำ TLS termination แล้ว reverse proxy ไปที่ `127.0.0.1:3000` ส่วน api, postgres และ redis รันใน docker compose (`backend/docker-compose.prod.yml`)

```
Flutter app ──HTTPS──> Nginx :443 (Let's Encrypt) ──> api :3000 (127.0.0.1)
                                                      ├── postgres (volume pgdata)
                                                      └── redis    (volume redisdata)
GitHub push main ─> Backend CI ─> Backend CD ─> Artifact Registry ─> IAP SSH ─> deploy.sh
```

| ไฟล์ | หน้าที่ |
|---|---|
| `.github/workflows/backend-cd.yml` | build image → push ไป Artifact Registry → SSH ผ่าน IAP → รัน `deploy.sh` → smoke test ผ่าน HTTPS |
| `backend/docker-compose.prod.yml` | stack production (api ดึง image จาก registry และไม่เปิดพอร์ตสู่สาธารณะ) |
| `deploy/deploy.sh` | pull image → pg_dump → migrate → สลับ container → health check → rollback image ถ้าไม่ผ่าน |
| `deploy/setup-vm.sh` | ตั้งค่า VM ครั้งแรก (docker, nginx, certbot, swap, auth registry) |
| `deploy/nginx/poonsuk-api.conf` | site config ของ Nginx |

ทุกคำสั่งในหัวข้อ 1–6 และ 9 รันบนเครื่องตัวเองด้วย gcloud CLI (หรือใน Cloud Shell) และต้องใช้บัญชีที่เป็น Owner ของ project

---

## 0. ตัวแปรที่ใช้ทั้งเอกสาร

```bash
PROJECT_ID=your-project-id
REGION=asia-southeast1          # สิงคโปร์ ใกล้ภูเก็ตที่สุด
ZONE=asia-southeast1-b
INSTANCE=poonsuk-api
REPO=poonsuk                    # Artifact Registry repository
GH_REPO=PhonlawatThaenthong/tourist-booking-application
VM_SA=poonsuk-vm@${PROJECT_ID}.iam.gserviceaccount.com
DEPLOY_SA=github-deployer@${PROJECT_ID}.iam.gserviceaccount.com

gcloud config set project $PROJECT_ID
```

## 1. เปิด API

```bash
gcloud services enable compute.googleapis.com artifactregistry.googleapis.com \
  iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com \
  iap.googleapis.com oslogin.googleapis.com
```

## 2. Artifact Registry

```bash
gcloud artifacts repositories create $REPO \
  --repository-format=docker --location=$REGION
```

## 3. Service account ของ VM (ใช้ pull image)

```bash
gcloud iam service-accounts create poonsuk-vm --display-name="Poonsuk VM runtime"

gcloud artifacts repositories add-iam-policy-binding $REPO --location=$REGION \
  --member=serviceAccount:$VM_SA --role=roles/artifactregistry.reader

for ROLE in roles/logging.logWriter roles/monitoring.metricWriter; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:$VM_SA --role=$ROLE --condition=None
done
```

ถ้าจะให้ backup ของฐานข้อมูลถูกส่งขึ้น Cloud Storage ด้วย (แนะนำ)

```bash
BUCKET=${PROJECT_ID}-poonsuk-backups
gcloud storage buckets create gs://$BUCKET --location=$REGION --uniform-bucket-level-access
gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
  --member=serviceAccount:$VM_SA --role=roles/storage.objectCreator
```

จากนั้นใส่ `BACKUP_BUCKET=<ชื่อ bucket>` ใน `.env` ของ VM (หัวข้อ 7)

## 4. Static IP และ VM

```bash
gcloud compute addresses create poonsuk-api-ip --region=$REGION
gcloud compute addresses describe poonsuk-api-ip --region=$REGION --format='value(address)'

gcloud compute instances create $INSTANCE --zone=$ZONE \
  --machine-type=e2-small \
  --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
  --boot-disk-size=30GB --boot-disk-type=pd-balanced \
  --address=poonsuk-api-ip --tags=poonsuk-api \
  --service-account=$VM_SA --scopes=cloud-platform \
  --metadata=enable-oslogin=TRUE
```

e2-small มี RAM 2 GB ซึ่งพอสำหรับ api, postgres และ redis เมื่อมี swap 2 GB ที่ `setup-vm.sh` สร้างให้ ไม่แนะนำ e2-micro (1 GB) เพราะ Node กับ Postgres รวมกันจะใช้ swap หนัก แม้ image จะ build บน GitHub ไม่ได้ build บน VM

## 5. Firewall

```bash
# 80/443 สำหรับทุกคน
gcloud compute firewall-rules create poonsuk-allow-web --network=default \
  --direction=INGRESS --action=ALLOW --rules=tcp:80,tcp:443 \
  --source-ranges=0.0.0.0/0 --target-tags=poonsuk-api

# 22 เปิดเฉพาะช่วง IP ของ IAP (ไม่ใช่ทั้งอินเทอร์เน็ต)
gcloud compute firewall-rules create poonsuk-allow-iap-ssh --network=default \
  --direction=INGRESS --action=ALLOW --rules=tcp:22 \
  --source-ranges=35.235.240.0/20 --target-tags=poonsuk-api
```

network `default` มี rule `default-allow-ssh` ที่เปิด 22 ให้ทั้งโลก ถ้าใน project นี้ไม่มี VM อื่นที่พึ่ง rule นี้ ให้ลบทิ้ง

```bash
gcloud compute firewall-rules delete default-allow-ssh
```

## 6. DNS

สร้าง A record ชี้โดเมน (เช่น `api.example.com`) ไปที่ static IP ในหัวข้อ 4

ถ้ายังไม่มีโดเมน ใช้ sslip.io ได้ เช่น IP `34.1.2.3` ใช้โดเมน `34-1-2-3.sslip.io` ได้ทันทีโดยไม่ต้องตั้งค่าอะไร และ Let's Encrypt ออก cert ให้ได้ (แต่ rate limit ใช้ร่วมกับผู้ใช้ sslip.io คนอื่น จึงเหมาะกับเดโมเท่านั้น)

ตรวจก่อนไปขั้นถัดไป: `nslookup api.example.com` ต้องได้ IP ของ VM

## 7. ตั้งค่า VM ครั้งแรก

```bash
# ส่งโฟลเดอร์ deploy/ ขึ้น VM แล้วรัน setup
gcloud compute scp --recurse deploy $INSTANCE:~ --zone=$ZONE --tunnel-through-iap
gcloud compute ssh $INSTANCE --zone=$ZONE --tunnel-through-iap \
  --command="sudo bash deploy/setup-vm.sh api.example.com you@psu.ac.th $REGION"
```

สร้าง `/opt/poonsuk/.env` บน VM (`sudo nano /opt/poonsuk/.env` แล้ว `sudo chmod 600 /opt/poonsuk/.env`)

```dotenv
# image ที่ CD push ขึ้นไป (tag ถูกกำหนดโดย deploy.sh)
API_IMAGE=asia-southeast1-docker.pkg.dev/your-project-id/poonsuk/api

PORT=3000
DB_USER=poonsuk
DB_NAME=poonsuk
DB_PASSWORD=<openssl rand -hex 24>
REDIS_PASSWORD=<openssl rand -hex 24>

JWT_ACCESS_SECRET=<openssl rand -hex 32>
JWT_ACCESS_TTL=15m
JWT_REFRESH_SECRET=<openssl rand -hex 32>
JWT_REFRESH_TTL_DAYS=30

CACHE_ENABLED=true
CACHE_TTL_SECONDS=60
CACHE_OP_TIMEOUT_MS=250
LOCK_ENABLED=true
LOCK_TTL_MS=5000
LOCK_WAIT_MS=2000

PAYMENT_ACCOUNT_NAME=Poonsuk Resort
PAYMENT_PROMPTPAY_ID=<PromptPay ID จริง>
PAYMENT_NOTE=สแกน QR แล้วโอนตามยอดการจอง จากนั้นอัปโหลดสลิปเพื่อรอเจ้าหน้าที่ยืนยัน
PAYMENT_MAX_SLIP_BYTES=5242880
BOOKING_HOLD_MINUTES=3
BOOKING_SWEEP_SECONDS=30

# GCP บล็อกพอร์ต 25 ขาออก ใช้ 587 เท่านั้น
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=
SMTP_FROM=Poonsuk Resort <no-reply@example.com>
RESET_TOKEN_TTL_MINUTES=15

SENTRY_DSN=
BACKUP_BUCKET=
```

**ห้ามใส่ข้อความ `<openssl rand ...>` ลงไปตรง ๆ** ให้รัน `openssl rand -hex 24` (หรือ 32) แล้วนำผลลัพธ์มาใส่ หรือสร้างให้ทีเดียวหลังบันทึกไฟล์

```bash
sudo -i; cd /opt/poonsuk
for K in DB_PASSWORD REDIS_PASSWORD; do sed -i "s|^$K=.*|$K=$(openssl rand -hex 24)|" .env; done
for K in JWT_ACCESS_SECRET JWT_REFRESH_SECRET; do sed -i "s|^$K=.*|$K=$(openssl rand -hex 32)|" .env; done
grep -nE 'openssl|your-project|<PromptPay' .env || echo "ok: no placeholders"
```

ไม่ต้องใส่ `NODE_ENV`, `DB_HOST`, `DB_PORT`, `REDIS_URL`, `UPLOAD_DIR`, `TRUST_PROXY` เพราะ `docker-compose.prod.yml` กำหนดให้แล้ว

`DB_PASSWORD` ถูกใช้ตอนสร้าง volume `pgdata` ครั้งแรกเท่านั้น ถ้าเปลี่ยนภายหลังต้องเปลี่ยนใน Postgres ด้วย (ไม่ต้องรู้รหัสเก่า)

```bash
NEW=$(grep '^DB_PASSWORD=' .env | cut -d= -f2-)
IMAGE_TAG=x docker compose -p poonsuk -f docker-compose.prod.yml exec -T postgres \
  psql -U poonsuk -d poonsuk -c "ALTER USER poonsuk PASSWORD '$NEW';"
```

## 8. Deploy service account + Workload Identity Federation

GitHub Actions ขอ token จาก GCP ผ่าน OIDC จึงไม่ต้องเก็บ JSON key ไว้ใน GitHub

```bash
gcloud iam service-accounts create github-deployer --display-name="GitHub Actions deployer"

# push image
gcloud artifacts repositories add-iam-policy-binding $REPO --location=$REGION \
  --member=serviceAccount:$DEPLOY_SA --role=roles/artifactregistry.writer

# SSH ผ่าน OS Login (มี sudo) เฉพาะ VM นี้
gcloud compute instances add-iam-policy-binding $INSTANCE --zone=$ZONE \
  --member=serviceAccount:$DEPLOY_SA --role=roles/compute.osAdminLogin

# เปิด IAP tunnel และอ่านข้อมูล instance
for ROLE in roles/iap.tunnelResourceAccessor roles/compute.viewer; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:$DEPLOY_SA --role=$ROLE --condition=None
done

# VM รันด้วย VM_SA ผู้ที่ SSH เข้าไปจึงต้องมีสิทธิ์ actAs SA นั้น
gcloud iam service-accounts add-iam-policy-binding $VM_SA \
  --member=serviceAccount:$DEPLOY_SA --role=roles/iam.serviceAccountUser

# Workload Identity pool + provider (รับ token จาก repo นี้เท่านั้น)
gcloud iam workload-identity-pools create github --location=global \
  --display-name="GitHub Actions"

gcloud iam workload-identity-pools providers create-oidc github-repo \
  --location=global --workload-identity-pool=github \
  --issuer-uri=https://token.actions.githubusercontent.com \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
  --attribute-condition="assertion.repository=='${GH_REPO}'"

PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')

gcloud iam service-accounts add-iam-policy-binding $DEPLOY_SA \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github/attribute.repository/${GH_REPO}"

# ค่าที่ต้องใส่ใน GitHub เป็น GCP_WIF_PROVIDER
echo "projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github/providers/github-repo"
```

## 9. ตั้งค่า GitHub

Settings → Secrets and variables → Actions → แท็บ **Variables** (ไม่มีค่าไหนเป็นความลับ)

| Variable | ตัวอย่าง |
|---|---|
| `GCP_PROJECT_ID` | `your-project-id` |
| `GCP_REGION` | `asia-southeast1` |
| `GCP_ZONE` | `asia-southeast1-b` |
| `GAR_REPOSITORY` | `poonsuk` |
| `GCE_INSTANCE` | `poonsuk-api` |
| `GCP_WIF_PROVIDER` | ผลจากคำสั่ง echo สุดท้ายในหัวข้อ 8 |
| `GCP_DEPLOY_SA` | `github-deployer@your-project-id.iam.gserviceaccount.com` |
| `API_DOMAIN` | `api.example.com` (ไม่ต้องมี https://) |

Settings → Environments → New environment ชื่อ `production`

- Deployment branches: เลือก Selected branches แล้วใส่ `main`
- Required reviewers: ใส่ชื่อผู้อนุมัติถ้าต้องการให้กดอนุมัติก่อนขึ้นจริง (continuous delivery) ถ้าไม่ใส่จะ deploy อัตโนมัติทันทีหลัง CI ผ่าน (continuous deployment)

## 10. Deploy ครั้งแรก

1. merge `backend-cd.yml` และไฟล์ใน `deploy/` เข้า `main` (`workflow_run` จะทำงานได้ก็ต่อเมื่อไฟล์ workflow อยู่บน default branch แล้ว)
2. Backend CI ผ่าน → Backend CD เริ่มเอง หรือกด Run workflow ในแท็บ Actions
3. ตรวจ `curl https://api.example.com/health/ready`

### Seed ข้อมูลครั้งแรก

image production ไม่มี ts-node จึงรัน `seed:*` บน VM ไม่ได้ ให้รันจากเครื่องตัวเองผ่าน SSH tunnel

```bash
# หน้าต่างที่ 1: เปิด tunnel  เครื่องตัวเอง :5434  ->  VM 127.0.0.1:5433  ->  postgres
gcloud compute ssh poonsuk-api --zone=asia-southeast1-b --tunnel-through-iap -- -N -L 5434:127.0.0.1:5433
```

```powershell
# หน้าต่างที่ 2 (PowerShell ที่ backend\) ใช้รหัสจาก .env ของ VM
$env:DB_PORT="5434"; $env:DB_PASSWORD="<DB_PASSWORD ของ production>"
npm run seed:rooms; npm run seed:restaurants

# บัญชี admin คนแรก (ไม่มีบัญชี demo แล้ว รหัสต้องยาวอย่างน้อย 12 ตัว)
$env:SEED_ADMIN_EMAIL="you@example.com"; $env:SEED_ADMIN_PASSWORD="<รหัสที่แข็งแรง>"
npm run seed:admin
```

## 11. Flutter

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com
```

ใช้ HTTPS แล้วจึงไม่ต้องเปิด cleartext traffic บน Android

---

## งานประจำ

### ดูสถานะและ log

```bash
gcloud compute ssh poonsuk-api --zone=asia-southeast1-b --tunnel-through-iap
sudo -i                               # /opt/poonsuk เป็นของ root (chmod 750)
cd /opt/poonsuk
cat .deployed-tag                     # commit ที่ขึ้นอยู่ตอนนี้
# compose บังคับให้มี IMAGE_TAG ทุกคำสั่ง (deploy.sh เป็นคน export ให้ตอน deploy)
export IMAGE_TAG=$(cat .deployed-tag)
docker compose -p poonsuk -f docker-compose.prod.yml ps
docker compose -p poonsuk -f docker-compose.prod.yml logs -f --tail=100 api
```

### Rollback

ย้อน image (เร็วที่สุด เพราะ image อยู่ใน registry อยู่แล้ว)

```bash
sudo /opt/poonsuk/deploy.sh <commit-sha-เก่า>
```

หรือกด Run workflow ของ Backend CD แล้วใส่ SHA เก่า (จะ build ใหม่ ช้ากว่า)

ย้อนฐานข้อมูล (ทำเมื่อ migration ทำข้อมูลเสียเท่านั้น และข้อมูลหลังเวลา dump จะหายไป)

```bash
sudo -i
cd /opt/poonsuk
export IMAGE_TAG=$(cat .deployed-tag)
C="docker compose -p poonsuk -f docker-compose.prod.yml"
$C stop api
$C exec -T postgres sh -c 'pg_restore --clean --if-exists -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < backups/pre-xxxx.dump
sudo /opt/poonsuk/deploy.sh <commit-sha-ที่ตรงกับ schema ใน dump>
```

### เปลี่ยน Nginx config

CD ไม่ได้ deploy ไฟล์ Nginx ถ้าแก้ `deploy/nginx/poonsuk-api.conf` ให้ทำหัวข้อ 7 ซ้ำ (สคริปต์รันซ้ำได้ ไม่ขอ cert ใหม่ถ้ามีอยู่แล้ว)

### ต่ออายุ cert

`certbot.timer` ทำให้อัตโนมัติวันละ 2 ครั้ง และ hook จะ reload Nginx ให้ ตรวจได้ด้วย `sudo certbot renew --dry-run`

---

## กติกาและข้อจำกัด

- **Migration ต้อง backward compatible** เพราะ migration รันก่อนสลับ container (api ตัวเก่ายังรับ request อยู่) และ rollback ย้อนได้แค่ image ไม่ย้อน schema ให้แยกการเปลี่ยนที่ทำลายของเดิมเป็นสองรอบ เช่น เพิ่มคอลัมน์ใหม่ → deploy โค้ดที่ใช้คอลัมน์ใหม่ → ลบคอลัมน์เก่าใน release ถัดไป
- **Downtime ไม่กี่วินาที** ตอนสลับ api container เพราะมี replica เดียว ถ้าต้องการ zero-downtime ต้องรัน api สองตัวแล้วเพิ่มใน `upstream` ของ Nginx (แต่ต้องย้าย throttler ไปใช้ Redis store และย้ายไฟล์อัปโหลดไป shared storage ก่อน)
- **ไฟล์สลิปและรูปภาพ** อยู่ใน volume `uploads` และ `deploy.sh` ไม่ได้ backup ให้ ควรตั้ง snapshot schedule ของ boot disk ใน Compute Engine เพิ่ม
- `client_max_body_size 6m` ใน Nginx ต้องปรับตามถ้าเพิ่ม `PAYMENT_MAX_SLIP_BYTES` หรือ `IMAGE_MAX_BYTES`
- กด Run workflow ด้วยมือจะข้ามขั้น CI ใช้กับ commit ที่ผ่าน CI แล้วเท่านั้น
