#!/bin/bash
set -euo pipefail
[[ "$RUNNER_ENVIRONMENT" == github-hosted ]]
cd "$RUNNER_TEMP"
mkdir -m 700 vault-test
cd vault-test
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -keyout ca.key -out ca.crt -subj '/CN=Kaizu Disposable QA CA' -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign' 2>/dev/null
openssl req -new -newkey rsa:2048 -nodes -keyout tls.key -out tls.csr -subj '/CN=localhost' 2>/dev/null
cat > leaf.conf <<'EOF'
basicConstraints=critical,CA:FALSE
subjectAltName=DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth
keyUsage=digitalSignature,keyEncipherment
EOF
openssl x509 -req -in tls.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 1 -extfile leaf.conf -out tls.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca.crt
nix build "$NIXPKGS#vaultwarden" -o vaultwarden
nix run "$NIXPKGS#crane" -- export --platform linux/arm64 docker.io/vaultwarden/server@sha256:4fe17f415f90087377d37c755e0ea3cf189dcc6794e49cdd2a9adbb4937d9e1f image.tar
tar -xf image.tar web-vault
mkdir data
export DATA_FOLDER="$PWD/data" WEB_VAULT_FOLDER="$PWD/web-vault" DOMAIN=https://localhost:18765 ROCKET_ADDRESS=127.0.0.1 ROCKET_PORT=18765
export ROCKET_TLS="{certs=\"$PWD/tls.crt\",key=\"$PWD/tls.key\"}"
nohup ./vaultwarden/bin/vaultwarden > vault.log 2>&1 </dev/null &
nohup python3 "$GITHUB_WORKSPACE/.github/qa/safari-vault/site.py" > site.log 2>&1 </dev/null &
for attempt in {1..40}; do
    if curl --silent --fail --cacert ca.crt https://localhost:18765/alive >/dev/null; then break; fi
    sleep 1
done
curl --fail --silent --cacert ca.crt https://localhost:18765/alive
curl --fail --silent --cacert ca.crt https://127.0.0.1:18764/login >/dev/null
