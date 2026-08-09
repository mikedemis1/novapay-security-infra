# D3 Kyverno admission control. Deliberately NOT duplicating what the native
# Pod Security Standards (app.tf namespace labels) already enforce
# (privileged/root/capabilities) — these two policies cover things PSS
# doesn't: resource limits and a supply-chain registry allowlist.
resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno/"
  chart            = "kyverno"
  version          = "3.2.6"
  namespace        = "kyverno"
  create_namespace = true

  # Single replica everywhere — this is a test-day lab cluster, not HA prod.
  set {
    name  = "replicaCount"
    value = "1"
  }
  set {
    name  = "admissionController.replicas"
    value = "1"
  }
  set {
    name  = "backgroundController.replicas"
    value = "1"
  }
  set {
    name  = "reportsController.replicas"
    value = "1"
  }
  set {
    name  = "cleanupController.replicas"
    value = "1"
  }

  depends_on = [module.eks]
}

# NOTE (verification, not just trust): validate these two policies live
# during the D3 test day — deploy a Pod that violates each on purpose and
# confirm Kyverno actually blocks it (Enforce) before treating this as done.
# This is the same "break it on purpose" practice already used for the WAF
# and SCPs.

resource "kubernetes_manifest" "kyverno_require_requests_limits" {
  manifest = yamldecode(<<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: require-requests-limits
    spec:
      validationFailureAction: Enforce
      background: true
      rules:
        - name: validate-resources
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          validate:
            message: "CPU and memory requests and limits are required on every container."
            pattern:
              spec:
                containers:
                  - resources:
                      requests:
                        memory: "?*"
                        cpu: "?*"
                      limits:
                        memory: "?*"
                        cpu: "?*"
  YAML
  )

  depends_on = [helm_release.kyverno]
}

resource "kubernetes_manifest" "kyverno_restrict_registries" {
  manifest = yamldecode(<<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: restrict-image-registries
    spec:
      validationFailureAction: Enforce
      background: true
      rules:
        - name: validate-registries
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          validate:
            message: "Images must come from an approved registry (nginxinc on Docker Hub or public.ecr.aws)."
            pattern:
              spec:
                containers:
                  - image: "nginxinc/* | public.ecr.aws/*"
  YAML
  )

  depends_on = [helm_release.kyverno]
}
