local ingress(name, namespace, hosts, rules, authenticated, domain) = {
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
                  'app.kubernetes.io/name': 'alertmanager',
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

local addMixin = (import 'kube-prometheus/lib/mixin.libsonnet');
local corednsMixin = addMixin({
  name: 'coredns',
  mixin: (import 'coredns-mixin/mixin.libsonnet') + {
    _config+: {},  // mixin configuration object
  },
});
/*local mysqldMixin = addMixin({
  name: 'mysqld',
  mixin: (import 'mysqld-mixin/mixin.libsonnet') + {
    _config+: {},  // mixin configuration object
  },
});
local postgresMixin = addMixin({
  name: 'postgres',
  mixin: (import 'postgres_mixin/mixin.libsonnet') + {
    _config+: {},  // mixin configuration object
  },
});*/
local elasticsearchMixin = addMixin({
  name: 'elasticsearch',
  mixin: (import 'elasticsearch-mixin/mixin.libsonnet') + {
    _config+: {},  // mixin configuration object
  },
});
local etcdMixin = addMixin({
  name: 'etcd',
  mixin: (import 'mixin/mixin.libsonnet') + {
    _config+: {},  // mixin configuration object
  },
});

local fromTraefik() = {
  from: [
    {
      podSelector: {
        matchLabels: {
          "app.kubernetes.io/name": "traefik"
        }
      },
      namespaceSelector: {
        matchLabels: {
          "kubernetes.io/metadata.name": "traefik"
        }
      }
    }
  ]
};

local kp = function(domain)
  (import 'kube-prometheus/main.libsonnet') +
  // Uncomment the following imports to enable its patches
  // (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
  (import 'kube-prometheus/addons/all-namespaces.libsonnet') +
  // (import 'kube-prometheus/addons/node-ports.libsonnet') +
  // (import 'kube-prometheus/addons/static-etcd.libsonnet') +
  // (import 'kube-prometheus/addons/thanos-sidecar.libsonnet') +
  // (import 'kube-prometheus/addons/custom-metrics.libsonnet') +
  // (import 'kube-prometheus/addons/external-metrics.libsonnet') +
  (import 'kube-prometheus/addons/pyrra.libsonnet') +
  {
    kubeStateMetrics+: {
      deployment+: {
        spec+: {
          template+: {
            spec+: {
              # allowlist some node labels used in alert rules
              # Format:
              # https://github.com/prometheus-community/helm-charts/blob/019442a590178d1f1fa948c7042cd0f56ef7cf57/charts/kube-state-metrics/values.yaml#L345-L352
              containers: [
                super.containers[0] + {
                  args: super.args + [
                    '--metric-labels-allowlist=nodes=[kubevirt.io/schedulable]',
                  ],
                },
              ] + super.containers[1:],
            },
          },
        },
      },
    },
  } +
  {
    prometheus+: {
      networkPolicy+: {
        spec+: {
          ingress: super.ingress + [
            fromTraefik() + {
              from+: [
                {
                  podSelector: {
                    matchLabels: {
                      "app.kubernetes.io/name": "pyrra"
                    }
                  }
                }
              ],
              ports: [
                {
                  port: 9090,
                  protocol: "TCP"
                }
              ]
            }
          ]
        }
      }
    },
    alertmanager+: {
      networkPolicy+: {
        spec+: {
          ingress: super.ingress + [
            fromTraefik() + {
              ports: [
                {
                  port: 9093,
                  protocol: "TCP"
                }
              ]
            }
          ]
        }
      }
    },
    grafana+: {
      networkPolicy+: {
        spec+: {
          ingress: super.ingress + [
            fromTraefik() + {
              ports: [
                {
                  port: 3000,
                  protocol: "TCP"
                }
              ]
            }
          ]
        }
      }
    }
  } +
  {
    values+:: {
      common+: {
        namespace: 'monitoring',
        platform: 'kubespray',
      },
      grafana+: {
        plugins: ['grafana-piechart-panel'],
        dashboards+: corednsMixin.grafanaDashboards /*mysqldMixin.dashboards, postgresMixin.dashboards,*/ + elasticsearchMixin.grafanaDashboards + etcdMixin.grafanaDashboards,
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
              role_attribution_path: @'is_admin && ''Admin'' || ''Viewer'''
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
            
          receivers:
            - name: 'null'
            - name: 'discord-notifications'
              webhook_configs:
                - url: 'http://alertmanager-discord:9094'
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
          externalUrl: 'https://prometheus.monitoring.' + domain,
          retention: '180d',
          storage: {
            volumeClaimTemplate: {
              apiVersion: 'v1',
              kind: 'PersistentVolumeClaim',
              spec: {
                accessModes: ['ReadWriteOnce'],
                resources: { requests: { storage: '100Gi' } },
              },
            },
          },
        },
      },
    prometheusAlerts+:: corednsMixin.prometheusAlerts +
      elasticsearchMixin.prometheusAlerts +
      etcdMixin.prometheusAlerts,
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
      }], false, domain),
      backend: ingress('backend', $.values.common.namespace, ['pyrra.monitoring.' + domain, 'prometheus.monitoring.' + domain, 'alertmanager.monitoring.' + domain, 'monitoring.' + domain], [
        {
          host: 'pyrra.monitoring.' + domain,
          http: {
            paths: [{
              path: '/',
              pathType: 'Prefix',
              backend: {
                service: {
                  name: 'pyrra-api',
                  port: {
                    name: 'http',
                  },
                },
              },
            }],
          },
        },
        {
          host: 'alertmanager.monitoring.' + domain,
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
          host: 'prometheus.monitoring.' + domain,
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
      ], true, domain),
    },
  };

// We need to inject some secrets as environment variables
// We can't use a configMap because there's already a generated config
// We also want temporary stateful storage with a PVC
local modifiedGrafana = function(kpd) kpd.grafana {
  local g = kpd.grafana,
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
        },
      },
    },
  },
};

local manifests = function(kpd)
  // Uncomment line below to enable vertical auto scaling of kube-state-metrics
  //{ ['ksm-autoscaler-' + name]: kpd.ksmAutoscaler[name] for name in std.objectFields(kpd.ksmAutoscaler) } +
  { ['setup/0namespace-' + name]: kpd.kubePrometheus[name] for name in std.objectFields(kpd.kubePrometheus) } +
  {
    ['setup/prometheus-operator-' + name]: kpd.prometheusOperator[name]
    for name in std.filter((function(name) name != 'serviceMonitor'), std.objectFields(kpd.prometheusOperator))
  } +
  { 'setup/pyrra-slo-CustomResourceDefinition': kpd.pyrra.crd } +
  // serviceMonitor is separated so that it can be created after the CRDs are ready
  { 'prometheus-operator-serviceMonitor': kpd.prometheusOperator.serviceMonitor } +
  { ['alertmanager-' + name]: kpd.alertmanager[name] for name in std.objectFields(kpd.alertmanager) } +
  { ['grafana-' + name]: modifiedGrafana(kpd)[name] for name in std.objectFields(modifiedGrafana(kpd)) } +
  { ['pyrra-' + name]: kpd.pyrra[name] for name in std.objectFields(kpd.pyrra) if name != 'crd' } +
  { ['blackbox-exporter-' + name]: kpd.blackboxExporter[name] for name in std.objectFields(kpd.blackboxExporter) } +
  { ['kube-state-metrics-' + name]: kpd.kubeStateMetrics[name] for name in std.objectFields(kpd.kubeStateMetrics) } +
  { ['kubernetes-' + name]: kpd.kubernetesControlPlane[name] for name in std.objectFields(kpd.kubernetesControlPlane) } +
  { ['node-exporter-' + name]: kpd.nodeExporter[name] for name in std.objectFields(kpd.nodeExporter) } +
  { ['prometheus-' + name]: kpd.prometheus[name] for name in std.objectFields(kpd.prometheus) } +
  { ['prometheus-adapter-' + name]: kpd.prometheusAdapter[name] for name in std.objectFields(kpd.prometheusAdapter) } +
  { ['alertmanager-discord-' + name]: alertmanagerDiscord[name] for name in std.objectFields(alertmanagerDiscord) } +
  { [name + '-ingress']: kpd.ingress[name] for name in std.objectFields(kpd.ingress) } +
  //{ 'external-mixins/mysqld-mixin-prometheus-rules': mysqldMixin.prometheusRules }
  //{ 'external-mixins/postgres-mixin-prometheus-rules': postgresMixin.prometheusRules }
  { 'elasticsearch-mixin-prometheus-rules': elasticsearchMixin.prometheusRules } +
  { 'etcd-mixin-prometheus-rules': etcdMixin.prometheusRules };

local kustomizationResourceFile(name) = name + '.yaml';
local kustomization = function(kpd) {
  apiVersion: 'kustomize.config.k8s.io/v1beta1',
  kind: 'Kustomization',
  resources: std.map(kustomizationResourceFile, std.objectFields(manifests(kpd))),
};

function(domain)
manifests(kp(domain)) + {
  'kustomization': kustomization(kp(domain)),
}
