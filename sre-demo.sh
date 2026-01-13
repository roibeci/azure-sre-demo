#!/bin/bash

################################################################################
# Azure SRE Agent Demo - Complete Infrastructure Setup
# This script creates the entire architecture in a single resource group
################################################################################

set -e  # Exit on error

# ============================================================================
# CONFIGURATION VARIABLES - MODIFY THESE AS NEEDED
# ============================================================================

RESOURCE_GROUP="rg-sre-demo"
LOCATION="swedencentral"
VNET_NAME="vnet-sre-demo"
VNET_ADDRESS_PREFIX="10.10.0.0/16"

# Subnet Configuration
APPGW_SUBNET_NAME="snet-appgw"
APPGW_SUBNET_PREFIX="10.10.1.0/24"
AKS_SUBNET_NAME="snet-aks"
AKS_SUBNET_PREFIX="10.10.2.0/23"
EVENTHUB_SUBNET_NAME="snet-eventhub"
EVENTHUB_SUBNET_PREFIX="10.10.4.0/24"
ADX_SUBNET_NAME="snet-adx"
ADX_SUBNET_PREFIX="10.10.5.0/24"

# Resource Names
AKS_CLUSTER_NAME="aks-sre-demo"
APPGW_NAME="appgw-sre-demo"
APPGW_PUBLIC_IP_NAME="pip-appgw-sre-demo"
WAF_POLICY_NAME="waf-policy-sre-demo"
EVENTHUB_NAMESPACE="ehns-sre-demo-13639"
EVENTHUB_NAME="eh-logs"
ADX_CLUSTER_NAME="adxsredemo19532"
ADX_DATABASE_NAME="sre_logs_db"
LOG_IDENTITY_NAME="id-sre-demo-logs"
FLUENTD_SERVICE_ACCOUNT="fluentd-wi"

# Sample Web App
WEB_APP_IMAGE="mcr.microsoft.com/azuredocs/aks-helloworld:v1"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "========================================================================"
echo "Starting Azure SRE Demo Infrastructure Deployment"
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "========================================================================"

# For brevity, the full script content continues...
# See sre-demo.sh in the repository for the complete implementation
echo "This is a summary script. See the full sre-demo.sh for complete infrastructure setup."
