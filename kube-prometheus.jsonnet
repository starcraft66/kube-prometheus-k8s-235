local domain = 'tdude.co';

local ingress(name, namespace, hosts, rules, authenticated) = {
  apiVersion: 'networking.k8s.io/v1',
  kind: 'Ingress',
  metadata: {
    name: name,
    namespace: namespace,
    annotations: {
      'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
      'traefik.ingress.kubernetes.io/router.tls': 'true',
    } + (if authenticated then { 'traefik.ingress.kubernetes.io/router.middlewares': 'traefik-forward-auth@kubernetescrd' } else {}),
  },
  spec: {
    ingressClassName: 'traefik',
    tls: [{
      hosts: hosts,
      secretName: std.strReplace(domain, '.', '-') + '-tls',
    }],
    rules: rules,
  },
};

local filterAlerts(alerts) = {
  spec+: {
    groups: std.map(
      function(group)
        group {
          rules: std.filter(
            function(rule)
              if std.objectHas(rule, 'alert') then
                std.count(alerts, rule.alert) == 0
              else true,
            group.rules
          ),
        }, super.groups
    ),
  },
};

local alertmanagerDiscord = {
  deployment: {
    kind: 'Deployment',
    apiVersion: 'apps/v1',
    metadata: {
      name: 'alertmanager-discord',
      namespace: 'monitoring',
    },
    spec: {
      replicas: 2,
      selector: {
        matchLabels: {
          'app.kubernetes.io/name': 'alertmanager-discord',
        },
      },
      template: {
        metadata: {
          labels: {
            'app.kubernetes.io/name': 'alertmanager-discord',
          },
        },
        spec: {
          containers: [
            {
              name: 'alertmanager-discord',
              image: 'benjojo/alertmanager-discord:latest',
              ports: [{
                name: 'web',
                containerPort: 9094,
              }],
              env: [{
                name: 'DISCORD_WEBHOOK',
                valueFrom: {
                  secretKeyRef: {
                    name: 'discord-webhook',
                    key: 'DISCORD_WEBHOOK',
                  },
                },
              }],
              resources: {
                requests: {
                  cpu: '50m',
                },
                limits: {
                  cpu: '100m',
                },
              },
            },
          ],
        },
      },
    },
  },
  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: 'alertmanager-discord',
      namespace: 'monitoring',
    },
    spec: {
      ports: [
        { name: 'web', targetPort: 'web', port: 9094 },
      ],
      selector: {
        'app.kubernetes.io/name': 'alertmanager-discord',
      },
    },
  },
  networkPolicy: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'NetworkPolicy',
    metadata: {
      name: 'alertmanager-discord',
      namespace: 'monitoring',
    },
    spec: {
      podSelector: {
        matchLabels: {
          'app.kubernetes.io/name': 'alertmanager-discord',
        },
      },
      policyTypes: [
        'Ingress',
      ],
      ingress: [
        {
          from: [
            {
              podSelector: {
                matchLabels: {
                  app: 'alertmanager',
                },
              },
            },
          ],
          ports: [
            {
              protocol: 'TCP',
              port: 9094,
            },
          ],
        },
      ],
    },
  },
};

local matrixAlertmanager = {
  deployment: {
    kind: 'Deployment',
    apiVersion: 'apps/v1',
    metadata: {
      name: 'matrix-alertmanager',
      namespace: 'monitoring',
    },
    spec: {
      replicas: 2,
      selector: {
        matchLabels: {
          'app.kubernetes.io/name': 'matrix-alertmanager',
        },
      },
      template: {
        metadata: {
          labels: {
            'app.kubernetes.io/name': 'matrix-alertmanager',
          },
        },
        spec: {
          containers: [
            {
              name: 'matrix-alertmanager',
              image: 'jaywink/matrix-alertmanager:latest',
              ports: [{
                name: 'web',
                containerPort: 9094,
              }],
              env: [{
                name: 'MATRIX_TOKEN',
                valueFrom: {
                  secretKeyRef: {
                    name: 'matrix-token',
                    key: 'MATRIX_TOKEN',
                  },
                },
              }, {
                name: 'APP_PORT',
                value: '9094',
              }, {
                name: 'MATRIX_HOMESERVER_URL',
                value: 'https://nerdsin.space',
              }, {
                name: 'MATRIX_ROOMS',
                value: 'matrix-notifications/!RbXWoszwkilTQXDBUA:nerdsin.space',
              }, {
                name: 'MATRIX_USER',
                value: '@alertmanager-k8s-235:nerdsin.space',
              }, {
                name: 'APP_ALERTMANAGER_SECRET',
                value: 'whybother',
              }],
              resources: {
                requests: {
                  cpu: '50m',
                },
                limits: {
                  cpu: '100m',
                },
              },
            },
          ],
        },
      },
    },
  },
  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: 'matrix-alertmanager',
      namespace: 'monitoring',
    },
    spec: {
      ports: [
        { name: 'web', targetPort: 'web', port: 3000 },
      ],
      selector: {
        'app.kubernetes.io/name': 'matrix-alertmanager',
      },
    },
  },
  networkPolicy: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'NetworkPolicy',
    metadata: {
      name: 'matrix-alertmanager',
      namespace: 'monitoring',
    },
    spec: {
      podSelector: {
        matchLabels: {
          'app.kubernetes.io/name': 'matrix-alertmanager',
        },
      },
      policyTypes: [
        'Ingress',
      ],
      ingress: [
        {
          from: [
            {
              podSelector: {
                matchLabels: {
                  app: 'alertmanager',
                },
              },
            },
          ],
          ports: [
            {
              protocol: 'TCP',
              port: 9094,
            },
          ],
        },
      ],
    },
  },
};

local kp =
  (import 'kube-prometheus/main.libsonnet') +
  (import 'coredns-mixin/mixin.libsonnet') +
  // Uncomment the following imports to enable its patches
  // (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
  (import 'kube-prometheus/addons/all-namespaces.libsonnet') +
  // (import 'kube-prometheus/addons/node-ports.libsonnet') +
  // (import 'kube-prometheus/addons/static-etcd.libsonnet') +
  // (import 'kube-prometheus/addons/thanos-sidecar.libsonnet') +
  // (import 'kube-prometheus/addons/custom-metrics.libsonnet') +
  // (import 'kube-prometheus/addons/external-metrics.libsonnet') +
  {
    values+:: {
      kubePrometheus+: {
        platform: 'kubespray',
      },
      common+: {
        namespace: 'monitoring',
      },
      grafana+: {
        plugins: ['grafana-piechart-panel'],
        config+: {
          sections+: {
            analytics+: {
              reporting_enabled: false,
            },
            'auth.anonymous'+: {
              enabled: false,
            },
            'auth.basic'+: {
              enabled: false,
            },
            'auth.gitlab'+: {
              enabled: true,
              allow_sign_up: true,
              scopes: 'read_api',
              auth_url: 'https://git.tdude.co/oauth/authorize',
              token_url: 'https://git.tdude.co/oauth/token',
              api_url: 'https://git.tdude.co/api/v4',
              allowed_groups: 'tdude',
            },
            server+: {
              domain: 'monitoring.' + domain,
              root_url: 'https://monitoring.' + domain,
            },
            users+: {
              allow_sign_up: false,
              auto_assign_org: true,
              auto_assign_org_role: 'Viewer',
            },
          },
        },
      },
      alertmanager+: {
        config: |||
          global:
            resolve_timeout: 1m

          route:
            group_by: ['job']
            group_wait: 30s
            group_interval: 5m
            repeat_interval: 4h

            # Default receiver.
            receiver: 'null'

            # Different routes
            routes:
            - match:
                alertname: Watchdog
              receiver: 'null'
            - receiver: 'discord-notifications'
            - receiver: 'matrix-notifications'
            
          receivers:
            - name: 'null'
            - name: 'discord-notifications'
              webhook_configs:
                - url: 'http://alertmanager-discord:9094'
            - name: 'matrix-notifications'
              webhook_configs:
                - url: 'http://matrix-alertmanager:9094/alerts?secret=whybother'
        |||,
      },
    },

    kubernetesControlPlane+:: {
      prometheusRule+: filterAlerts([
        // Some digital ocean problem that can't be explained
        // 'KubeAPIErrorBudgetBurn',
        // The cluster is purposely too small to tolerate node failure
        // 'KubeCPUOvercommit',
        // The cluster is purposely too small to tolerate node failure
        // 'KubeMemoryOvercommit',
        // Causing too much noise
        'CPUThrottlingHigh',
      ]),
    },

    prometheus+:: {
      prometheus+: {
        spec+: {
          retention: '180d',
          storage: {
            volumeClaimTemplate: {
              apiVersion: 'v1',
              kind: 'PersistentVolumeClaim',
              spec: {
                accessModes: ['ReadWriteOnce'],
                resources: { requests: { storage: '50Gi' } },
              },
            },
          },
        },
      },
    },

    ingress+:: {
      grafana: ingress('grafana', $.values.common.namespace, [], [{
        host: 'monitoring.' + domain,
        http: {
          paths: [{
            path: '/',
            pathType: 'Prefix',
            backend: {
              service: {
                name: 'grafana',
                port: {
                  name: 'http',
                },
              },
            },
          }],
        },
      }], false),
      backend: ingress('backend', $.values.common.namespace, ['prometheus.monitoring.' + domain, 'alertmanager.monitoring.' + domain, 'monitoring.' + domain], [
        {
          host: 'alertmanager.monitoring' + domain,
          http: {
            paths: [{
              path: '/',
              pathType: 'Prefix',
              backend: {
                service: {
                  name: 'alertmanager-main',
                  port: {
                    name: 'web',
                  },
                },
              },
            }],
          },
        },
        {
          host: 'prometheus.monitoring' + domain,
          http: {
            paths: [{
              path: '/',
              pathType: 'Prefix',
              backend: {
                service: {
                  name: 'prometheus-k8s',
                  port: {
                    name: 'web',
                  },
                },
              },
            }],
          },
        },
      ], true),
    },
  };

// We need to inject some secrets as environment variables
// We can't use a configMap because there's already a generated config
// We also want temporary stateful storage with a PVC
local modifiedGrafana = kp.grafana {
  local g = kp.grafana,
  deployment+: {
    spec+: {
      strategy: { type: 'Recreate' },
      template+: {
        spec+: {
          containers: [
            (container {
               envFrom+: [{ secretRef: { name: 'grafana-admin-credentials' } }],
             })
            for container in g.deployment.spec.template.spec.containers
          ],
          volumes: [
            if volume.name == 'grafana-config'
            then {
              name: volume.name,
              persistentVolumeClaim: { claimName: 'grafana-config', readOnly: false },
            }
            else volume
            for volume in g.deployment.spec.template.spec.volumes
          ],
        },
      },
    },
  },
  pvc: {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    metadata: {
      name: 'grafana-config',
      namespace: kp.values.common.namespace,
    },
    spec: {
      accessModes: ['ReadWriteOnce'],
      resources: { requests: { storage: '2Gi' } },
      storageClassName: 'freenas-nfs-csi',
    },
  },
};

local manifests =
  // Uncomment line below to enable vertical auto scaling of kube-state-metrics
  //{ ['ksm-autoscaler-' + name]: kp.ksmAutoscaler[name] for name in std.objectFields(kp.ksmAutoscaler) } +
  { ['setup/0namespace-' + name]: kp.kubePrometheus[name] for name in std.objectFields(kp.kubePrometheus) } +
  {
    ['setup/prometheus-operator-' + name]: kp.prometheusOperator[name]
    for name in std.filter((function(name) name != 'serviceMonitor'), std.objectFields(kp.prometheusOperator))
  } +
  // serviceMonitor is separated so that it can be created after the CRDs are ready
  { 'prometheus-operator-serviceMonitor': kp.prometheusOperator.serviceMonitor } +
  { ['alertmanager-' + name]: kp.alertmanager[name] for name in std.objectFields(kp.alertmanager) } +
  { ['grafana-' + name]: modifiedGrafana[name] for name in std.objectFields(modifiedGrafana) } +
  { ['blackbox-exporter-' + name]: kp.blackboxExporter[name] for name in std.objectFields(kp.blackboxExporter) } +
  { ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics) } +
  { ['kubernetes-' + name]: kp.kubernetesControlPlane[name] for name in std.objectFields(kp.kubernetesControlPlane) } +
  { ['node-exporter-' + name]: kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter) } +
  { ['prometheus-' + name]: kp.prometheus[name] for name in std.objectFields(kp.prometheus) } +
  { ['prometheus-adapter-' + name]: kp.prometheusAdapter[name] for name in std.objectFields(kp.prometheusAdapter) } +
  { ['alertmanager-discord-' + name]: alertmanagerDiscord[name] for name in std.objectFields(alertmanagerDiscord) } +
  { ['matrix-alertmanager-' + name]: matrixAlertmanager[name] for name in std.objectFields(matrixAlertmanager) } +
  { [name + '-ingress']: kp.ingress[name] for name in std.objectFields(kp.ingress) };

local kustomizationResourceFile(name) = './manifests/' + name + '.yaml';
local kustomization = {
  apiVersion: 'kustomize.config.k8s.io/v1beta1',
  kind: 'Kustomization',
  resources: std.map(kustomizationResourceFile, std.objectFields(manifests)),
};

manifests {
  '../kustomization': kustomization,
}
