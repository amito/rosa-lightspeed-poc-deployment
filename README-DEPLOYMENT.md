# Lightspeed Stack - ROSA POC Deployment

This repository contains deployment manifests and automation scripts for running [Lightspeed Stack](https://github.com/lightspeed-core/lightspeed-stack) on Red Hat OpenShift Service on AWS (ROSA) with vLLM inference and RAG capabilities.

## About This Repository

This is a **deployment-specific repository** separated from the main Lightspeed Stack codebase to keep deployment infrastructure independent from the application code.

**Main Application Repository**: https://github.com/lightspeed-core/lightspeed-stack

## What's Included

This deployment sets up a complete AI stack on ROSA:

- **Lightspeed Stack**: User-facing REST API and web UI
- **Llama Stack**: Agent orchestration and RAG runtime
- **vLLM**: GPU-accelerated LLM inference with KServe/OpenShift AI
- **RAG Database**: FAISS vector store for knowledge search

## Quick Start

```bash
# 1. Log into your ROSA cluster
oc login --token=<your-token> --server=<your-server>

# 2. Set your HuggingFace token
export HF_TOKEN="your_huggingface_token_here"

# 3. Run automated deployment
cd scripts
./deploy-all.sh
```

## Documentation

See [README.md](README.md) for complete deployment instructions, troubleshooting, and configuration details.

## Repository Structure

```
├── 00-prerequisites/     # Prerequisite checks
├── 01-namespace/         # Namespace configuration
├── 02-secrets/           # Secret templates
├── 03-vllm/              # vLLM deployment manifests
├── 04-llama-stack/       # Llama Stack configuration
├── 05-lightspeed-stack/  # Lightspeed Stack deployment
├── scripts/              # Automation and testing scripts
├── README.md             # Main deployment guide
└── QUICKSTART.md         # Quick start guide
```

## Prerequisites

- ROSA cluster (4.12+)
- GPU nodes (g5.2xlarge or similar)
- OpenShift AI operator installed
- NVIDIA GPU operator configured

## Support

- **Deployment Issues**: Open an issue in this repository
- **Application Issues**: Report to [lightspeed-stack repository](https://github.com/lightspeed-core/lightspeed-stack)
- **RHOAI Support**: Red Hat support portal

## License

Apache 2.0 License (same as Lightspeed Stack)
