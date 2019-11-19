#!/usr/bin/env bash

# Binds a GitHub repository to a Kubernetes cluster for GitOps

EKSCTL_EXPERIMENTAL=true \
AWS_PROFILE=dustbort \
eksctl enable profile \
  --git-url git@github.com:dustbort/kubernetes-gitops.git \
  --git-email dustbort@gmail.com \
  --git-private-ssh-key-path ~/.ssh/kubernetes_github_ed25519 \
  --cluster dev-cluster \
  --region us-east-1 \
  app-dev