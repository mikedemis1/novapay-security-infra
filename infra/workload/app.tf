# D3 placeholder "transaction service" — no real app exists yet (matches the
# D2 pattern: KMS key/Secrets Manager secret were also "ready-for-use"
# without a real backing service). Purpose here is purely to have something
# real to secure: IRSA, Kyverno policies, Pod Security Standards, and
# NetworkPolicy all need an actual workload to attach to and demonstrate
# against during the test day.

resource "kubernetes_namespace" "app" {
  metadata {
    name = "novapay-app"
    labels = {
      # Native Kubernetes Pod Security Standards admission control — no
      # separate installation needed, built into the API server since 1.23.
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

# Annotated with the IRSA role from eks.tf — this is the actual mechanism:
# any pod using this service account gets temporary AWS credentials scoped
# to exactly the one secret, via the pod's OIDC-federated identity, no
# static AWS keys anywhere in the container.
resource "kubernetes_service_account" "app" {
  metadata {
    name      = "novapay-transaction-service"
    namespace = kubernetes_namespace.app.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.app_irsa.arn
    }
  }
}

resource "kubernetes_deployment" "app" {
  metadata {
    name      = "novapay-transaction-service"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = { app = "novapay-transaction-service" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "novapay-transaction-service" }
    }

    template {
      metadata {
        labels = { app = "novapay-transaction-service" }
      }

      spec {
        service_account_name = kubernetes_service_account.app.metadata[0].name

        # Satisfies the "restricted" Pod Security Standard at the pod level
        # (namespace label alone only enforces it; the pod spec has to
        # actually comply or the API server rejects it).
        security_context {
          run_as_non_root = true
          run_as_user     = 101
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name = "app"

          # Pinned by digest, not by the 1.27-alpine tag alone. A tag is a
          # moving pointer: the same manifest text can deploy different bytes
          # on different days, which makes an image nobody chose the thing
          # actually running. The tag stays for readability; the digest is
          # what is resolved. Update both together.
          image             = "nginxinc/nginx-unprivileged:1.27-alpine@sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0"
          image_pull_policy = "Always"

          port {
            container_port = 8080
          }

          # Without these the deployment reports Ready the moment the process
          # starts, so a container that comes up and immediately fails to
          # serve still counts as a healthy rollout. Readiness gates traffic;
          # liveness restarts a process that is running but wedged.
          readiness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            initial_delay_seconds = 3
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 20
          }

          # nginx needs to write here at runtime (cache temp files, pid
          # file) even though it never touches its own binaries/config -
          # emptyDir keeps read_only_root_filesystem true while still
          # giving it the 3 writable paths it actually needs. Confirmed
          # live: without these the container exits 1 immediately.
          volume_mount {
            name       = "cache"
            mount_path = "/var/cache/nginx"
          }
          volume_mount {
            name       = "run"
            mount_path = "/var/run"
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }

          # run_as_non_root must be repeated here even though it's already
          # set at the pod level: the kubernetes provider renders an unset
          # container-level runAsNonRoot as an explicit `false`, which the
          # "restricted" Pod Security Standard rejects as contradicting the
          # pod-level `true` (confirmed live - this is what PSS caught).
          security_context {
            run_as_non_root            = true
            run_as_user                = 101
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        volume {
          name = "cache"
          empty_dir {}
        }
        volume {
          name = "run"
          empty_dir {}
        }
        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service" "app" {
  metadata {
    name      = "novapay-transaction-service"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    selector = { app = "novapay-transaction-service" }
    port {
      port        = 80
      target_port = 8080
    }
    type = "ClusterIP"
  }
}

# Default-deny both directions, then punch exactly one hole (DNS). Same
# "explicit allow only" philosophy as the security groups in D2
# (lb -> app -> db chain) — nothing in this namespace can talk to anything
# else unless a rule says so.
resource "kubernetes_network_policy" "default_deny" {
  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy" "allow_dns_egress" {
  metadata {
    name      = "allow-dns-egress"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    # Scoped to CoreDNS rather than "port 53 anywhere". Without the selector
    # this rule permits DNS to any destination, which is a working
    # exfiltration channel: data goes out inside query names to a server the
    # attacker controls, and the default-deny policy above never sees it
    # because it is, technically, DNS. The August test only proved HTTPS was
    # blocked, so this path was never exercised.
    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }

      ports {
        port     = 53
        protocol = "UDP"
      }
      ports {
        port     = 53
        protocol = "TCP"
      }
    }
  }
}
