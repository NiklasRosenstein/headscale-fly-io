# Headscale Helm Chart

A Helm chart for deploying [Headscale](https://github.com/juanfont/headscale) (self-hosted Tailscale control server) on Kubernetes.

This chart was created as an alternative deployment method for the [headscale-fly-io](https://github.com/niklasrosenstein/headscale-fly-io) project, providing equivalent functionality with Kubernetes-native features.

**Note:** This chart works on any Kubernetes cluster, including [Fly Kubernetes](https://fly.io/kubernetes/), allowing you to leverage Fly.io's infrastructure while using Kubernetes orchestration.

## Features

- ✅ **Headplane Web UI** - Optional modern web interface for managing Headscale
- ✅ **Ingress Support** - Traditional Kubernetes Ingress with support for various controllers (nginx, traefik, etc.)
- ✅ **Gateway API Support** - Modern Gateway API (HTTPRoute, GRPCRoute, TLSRoute)
- ✅ **TLS/Certificate Management** - Integration with cert-manager for automatic certificate provisioning
- ✅ **Persistent Storage** - SQLite database persistence via PVC
- ✅ **Litestream Replication** - S3-compatible backup/restore for SQLite (same as Fly.io version)
- ✅ **OIDC Authentication** - OpenID Connect support for user authentication (Headscale & Headplane)
- ✅ **Prometheus Metrics** - ServiceMonitor for Prometheus Operator
- ✅ **Network Policies** - Optional network segmentation

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PV provisioner support (for persistence)
- Ingress controller or Gateway API implementation (for external access)
- cert-manager (optional, for automatic TLS certificates)

## Installation

### Add the Helm repository (if published)

```bash
# If using a Helm repository
helm repo add headscale https://your-helm-repo.example.com
helm repo update
```

### Install from local chart

```bash
# Clone the repository
git clone https://github.com/niklasrosenstein/headscale-fly-io.git
cd headscale-fly-io

# Install with default values
helm install headscale ./charts/headscale -n headscale --create-namespace

# Install with custom values
helm install headscale ./charts/headscale -n headscale --create-namespace -f my-values.yaml
```

## Configuration

### Minimal Configuration

```yaml
headscale:
  domainName: "vpn.example.com"

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: vpn.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: headscale-tls
      hosts:
        - vpn.example.com
```

### Using Gateway API (instead of Ingress)

```yaml
headscale:
  domainName: "vpn.example.com"

ingress:
  enabled: false

gatewayApi:
  enabled: true
  httpRoute:
    parentRefs:
      - name: main-gateway
        namespace: gateway-system
        sectionName: https
    hostnames:
      - vpn.example.com
  grpcRoute:
    enabled: true
    parentRefs:
      - name: main-gateway
        namespace: gateway-system
        sectionName: grpc

certificate:
  enabled: true
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
```

### With Litestream (S3 Backup/Restore)

```yaml
litestream:
  enabled: true
  s3:
    bucket: "my-headscale-backup"
    endpoint: "https://s3.amazonaws.com"
    region: "us-east-1"
    path: "headscale.db"
  aws:
    # Use existing secret for production
    existingSecret: "my-aws-credentials"
    accessKeyIdKey: "aws-access-key-id"
    secretAccessKeyKey: "aws-secret-access-key"
```

### With OIDC Authentication

```yaml
headscale:
  oidc:
    enabled: true
    issuer: "https://auth.example.com/realms/main"
    clientId: "headscale"
    # Use existing secret for production
    existingSecret: "headscale-oidc"
    allowedDomains: "example.com"
```

### With Headplane Web UI

[Headplane](https://github.com/tale/headplane) is a modern web UI for managing Headscale, providing a user-friendly interface for node management, user administration, and network monitoring.

```yaml
headplane:
  enabled: true
  # Base URL is auto-detected from headscale.domainName
  # Headplane will be available at https://vpn.example.com/admin
  cookieSecure: true
  procEnabled: true
```

### With Headplane + OIDC

For SSO authentication to the Headplane web interface:

```yaml
headplane:
  enabled: true
  oidc:
    enabled: true
    issuer: "https://auth.example.com/realms/main"
    clientId: "headplane"
    # Use existing secret for production
    existingSecret: "headplane-oidc-credentials"
    # API key for Headplane to communicate with Headscale
    headscaleApiKey: "your-headscale-api-key"
    scope: "openid email profile"
    usePkce: true
```

### Complete Production Example

```yaml
replicaCount: 1

image:
  repository: ghcr.io/niklasrosenstein/headscale-fly-io
  tag: "" # Uses Chart appVersion by default

headscale:
  domainName: "vpn.company.com"
  dns:
    baseDomain: "company.tailnet"
    magicDns: true
  logLevel: "info"
  oidc:
    enabled: true
    issuer: "https://sso.company.com/realms/main"
    clientId: "headscale"
    existingSecret: "headscale-oidc-credentials"

# Use existing secrets for sensitive data
existingSecret: "headscale-secrets"

headplane:
  enabled: true
  oidc:
    enabled: true
    issuer: "https://sso.company.com/realms/main"
    clientId: "headplane"
    existingSecret: "headplane-oidc-credentials"

litestream:
  enabled: true
  s3:
    bucket: "company-headscale-backup"
    endpoint: "https://s3.eu-west-1.amazonaws.com"
    region: "eu-west-1"
  aws:
    existingSecret: "headscale-s3-credentials"

persistence:
  enabled: true
  storageClassName: "fast-ssd"
  size: 5Gi

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
  hosts:
    - host: vpn.company.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: headscale-tls
      hosts:
        - vpn.company.com
  grpc:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/backend-protocol: "GRPC"

serviceMonitor:
  enabled: true
  interval: 30s

networkPolicy:
  enabled: true

resources:
  limits:
    cpu: 500m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

## Parameters

### Global Parameters

| Parameter          | Description                                       | Default                                     |
| ------------------ | ------------------------------------------------- | ------------------------------------------- |
| `replicaCount`     | Number of replicas (only 1 supported with SQLite) | `1`                                         |
| `image.repository` | Image repository                                  | `ghcr.io/niklasrosenstein/headscale-fly-io` |
| `image.tag`        | Image tag                                         | `""` (uses Chart appVersion)                |
| `image.pullPolicy` | Image pull policy                                 | `IfNotPresent`                              |

### Headscale Configuration

| Parameter                  | Description                      | Default     |
| -------------------------- | -------------------------------- | ----------- |
| `headscale.domainName`     | Domain name for Headscale server | `""`        |
| `headscale.dns.baseDomain` | Base domain for MagicDNS         | `"tailnet"` |
| `headscale.dns.magicDns`   | Enable MagicDNS                  | `true`      |
| `headscale.logLevel`       | Log level                        | `"info"`    |
| `headscale.oidc.enabled`   | Enable OIDC authentication       | `false`     |
| `headscale.oidc.issuer`    | OIDC issuer URL                  | `""`        |
| `headscale.oidc.clientId`  | OIDC client ID                   | `""`        |

### Headplane Configuration

| Parameter                        | Description                                       | Default |
| -------------------------------- | ------------------------------------------------- | ------- |
| `headplane.enabled`              | Enable Headplane web UI                           | `false` |
| `headplane.baseUrl`              | Base URL for Headplane (auto-detected if not set) | `""`    |
| `headplane.cookieSecret`         | Cookie secret (auto-generated if not set)         | `""`    |
| `headplane.cookieSecure`         | Use secure cookies (set to true with HTTPS)       | `true`  |
| `headplane.procEnabled`          | Enable process inspection features                | `true`  |
| `headplane.oidc.enabled`         | Enable OIDC for Headplane                         | `false` |
| `headplane.oidc.issuer`          | OIDC issuer URL                                   | `""`    |
| `headplane.oidc.clientId`        | OIDC client ID                                    | `""`    |
| `headplane.oidc.headscaleApiKey` | Headscale API key for Headplane                   | `""`    |

### Ingress Configuration

| Parameter              | Description                  | Default |
| ---------------------- | ---------------------------- | ------- |
| `ingress.enabled`      | Enable Ingress               | `false` |
| `ingress.className`    | Ingress class name           | `""`    |
| `ingress.annotations`  | Ingress annotations          | `{}`    |
| `ingress.hosts`        | Ingress hosts configuration  | `[]`    |
| `ingress.tls`          | Ingress TLS configuration    | `[]`    |
| `ingress.grpc.enabled` | Enable separate gRPC Ingress | `false` |

### Gateway API Configuration

| Parameter                         | Description        | Default |
| --------------------------------- | ------------------ | ------- |
| `gatewayApi.enabled`              | Enable Gateway API | `false` |
| `gatewayApi.httpRoute.parentRefs` | Gateway references | `[]`    |
| `gatewayApi.httpRoute.hostnames`  | Route hostnames    | `[]`    |
| `gatewayApi.grpcRoute.enabled`    | Enable GRPCRoute   | `false` |

### Litestream Configuration

| Parameter                | Description                   | Default  |
| ------------------------ | ----------------------------- | -------- |
| `litestream.enabled`     | Enable Litestream replication | `false`  |
| `litestream.s3.bucket`   | S3 bucket name                | `""`     |
| `litestream.s3.endpoint` | S3 endpoint URL               | `""`     |
| `litestream.s3.region`   | S3 region                     | `"auto"` |

### Persistence Configuration

| Parameter                      | Description        | Default |
| ------------------------------ | ------------------ | ------- |
| `persistence.enabled`          | Enable persistence | `true`  |
| `persistence.storageClassName` | Storage class      | `""`    |
| `persistence.size`             | PVC size           | `1Gi`   |
| `persistence.existingClaim`    | Use existing PVC   | `""`    |

## Migrating from Fly.io

If you're migrating from the Fly.io deployment:

1. **Export your database**: Use `fly ssh console` to download your SQLite database
2. **Create a PVC** and copy the database to it
3. **Update secrets**: Transfer your `NOISE_PRIVATE_KEY` and `AGE_SECRET_KEY` to Kubernetes secrets
4. **Deploy the chart** with matching configuration

```bash
# Export database from Fly.io
fly ssh console -C "cat /var/lib/headscale/db.sqlite" > db.sqlite

# Create secret with existing keys
kubectl create secret generic headscale-secrets \
  --from-literal=noise-private-key="privkey:..." \
  --from-literal=age-secret-key="AGE-SECRET-KEY-..."
```

## Fly.io Features Mapped to Kubernetes

| Fly.io Feature                | Kubernetes Equivalent                           |
| ----------------------------- | ----------------------------------------------- |
| `fly.toml` HTTP service       | Ingress or Gateway API HTTPRoute                |
| `fly.toml` TCP service (gRPC) | Ingress with gRPC backend or GRPCRoute          |
| Fly.io TLS termination        | Ingress TLS or Gateway TLS                      |
| Tigris object storage         | Any S3-compatible storage (MinIO, AWS S3, etc.) |
| `fly secrets`                 | Kubernetes Secrets                              |
| Fly.io metrics                | ServiceMonitor + Prometheus                     |
| Health checks                 | Kubernetes liveness/readiness probes            |
| Machine sizing                | Resource requests/limits                        |

## Troubleshooting

### Pods not starting

Check the logs:
```bash
kubectl logs -n headscale -l app.kubernetes.io/name=headscale
```

### Database issues

If the database is corrupted or you need to restore:
```bash
# Delete the PVC and let Litestream restore from S3
kubectl delete pvc -n headscale headscale-data
kubectl rollout restart deployment -n headscale headscale
```

### TLS/Certificate issues

Ensure cert-manager is installed and your ClusterIssuer is configured:
```bash
kubectl get clusterissuer
kubectl describe certificate -n headscale headscale
```

## License

MIT License - see the repository for details.
