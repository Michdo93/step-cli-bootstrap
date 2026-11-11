sudo apt-get update
sudo apt-get install -y --no-install-recommends curl gpg ca-certificates

sudo install -d -m 0755 /etc/apt/keyrings

sudo curl -fsSL \
    https://packages.smallstep.com/keys/apt/repo-signing-key.gpg \
    -o /etc/apt/keyrings/smallstep.asc

sudo tee /etc/apt/sources.list.d/smallstep.sources > /dev/null <<'EOF'
Types: deb
URIs: https://packages.smallstep.com/stable/debian
Suites: debs
Components: main
Signed-By: /etc/apt/keyrings/smallstep.asc
EOF

sudo apt-get update
sudo apt-get install -y step-cli
