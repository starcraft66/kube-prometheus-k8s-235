# kube-prometheus-kubespray

[![Build manifests and push](https://github.com/berbiche/kube-prometheus-kubespray/actions/workflows/ci.yaml/badge.svg)](https://github.com/berbiche/kube-prometheus-kubespray/actions/workflows/ci.yaml)

Custom configuration for the prometheus configuration of my bare-metal
Kubernetes cluster.

## Building

Simply run `nix-shell --run './build.sh kubespray.jsonnet'`
