#!/bin/bash
set -euo pipefail

# Log all output
exec > >(tee /var/log/gitlab-install.log) 2>&1

echo "=== Starting GitLab Installation ==="

# Update system
apt-get update -y
apt-get upgrade -y

# Install dependencies
apt-get install -y curl openssh-server ca-certificates tzdata perl

# ==============================================================================
# Install TLS certificate issued by Private CA
# ==============================================================================

mkdir -p /etc/gitlab/ssl

cat > /etc/gitlab/ssl/gitlab.crt <<'CERT'
${tls_certificate}
CERT

cat > /etc/gitlab/ssl/gitlab.key <<'KEY'
${tls_private_key}
KEY

cat > /usr/local/share/ca-certificates/gitlab-ca.crt <<'CA'
${ca_certificate}
CA

chmod 600 /etc/gitlab/ssl/gitlab.key
chmod 644 /etc/gitlab/ssl/gitlab.crt

# Trust the private CA on this instance
update-ca-certificates

# ==============================================================================
# Install GitLab CE
# ==============================================================================

curl -sS https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash

EXTERNAL_URL="https://${gitlab_domain}" apt-get install -y gitlab-ce

# Configure GitLab to use our certificate
cat >> /etc/gitlab/gitlab.rb <<'GITLABCFG'
nginx['ssl_certificate'] = "/etc/gitlab/ssl/gitlab.crt"
nginx['ssl_certificate_key'] = "/etc/gitlab/ssl/gitlab.key"
letsencrypt['enable'] = false
GITLABCFG

# Reconfigure with the proper TLS cert
gitlab-ctl reconfigure

echo "=== Waiting for GitLab to start ==="
sleep 60

# Wait for GitLab to be responsive
for i in $(seq 1 30); do
  if curl -sk https://localhost/-/health | grep -q "ok"; then
    echo "GitLab is healthy"
    break
  fi
  echo "Waiting for GitLab... attempt $i/30"
  sleep 10
done

echo "=== Creating Personal Access Token ==="

# Create a personal access token for the root user with api and admin scopes
gitlab-rails runner "
  user = User.find_by_username('root')
  token = user.personal_access_tokens.create!(
    name: '${gitlab_token_name}',
    token_digest: Gitlab::CryptoHelper.sha256('${gitlab_token_value}'),
    impersonation: false,
    scopes: [:api, :read_api, :read_user, :read_repository, :write_repository, :sudo, :admin_mode],
    expires_at: 365.days.from_now
  )
  token.save!
  puts 'Token created successfully'
"

echo "=== GitLab Installation Complete ==="
echo "Access GitLab at: https://${gitlab_domain}"
echo "Personal Access Token Name: ${gitlab_token_name}"
echo "Token scopes: api, admin_mode"
