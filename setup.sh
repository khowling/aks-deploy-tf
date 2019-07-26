## First Initialise terraform
## terraform init -backend-config="storage_account_name=khstore01" -backend-config="container_name=tfstate" -backend-config="access_key=***" -backend-config="key=kh.microsoft.tfstate"


ENVIRONMENT=kh-europe
export ENVIRONMENT

case $1 in 
  "new")
    # terraform workspace new $ENVIRONMENT
    terraform workspace select $ENVIRONMENT
    echo "Creating new AKS Service Principle...."
    AKS_SP=$(az ad sp create-for-rbac --name "http://${ENVIRONMENT}-aks-sp-rbac" --query '[appId, password]' -o tsv)
    sleep 10
    echo $AKS_SP
    SP_APPID=$(echo $AKS_SP | cut -d ' ' -f1)
    SP_PASSWD=$(echo $AKS_SP | cut -d ' ' -f2)
    ;;
  "update")
    terraform workspace select $ENVIRONMENT
    SP_APPID=$(az ad sp list --spn "http://${ENVIRONMENT}-aks-sp-rbac" --query '[0].appId' -o tsv)
    if [ -z "$2" ]; then
      echo "Need to know the password of the SP ${SP_APPID} (to delete: az ad sp delete --id ${SP_APPID} )"
      echo "usage: $0 update <sp password>"
      exit 1
    fi
    
    SP_PASSWD=$2
    ;;
  *) 
    echo "usage: $0 [ new | update [sp password]]"
    exit 1
esac




echo "Got SP AppID=${SP_APPID}"

echo "Get current az cli user Id (to grant access to create keyvault secrets)"
# CURRENT_AZID=$(az account show --query 'id' --output tsv)
CURRENT_AZID=$(az ad signed-in-user show --query 'objectId' --output tsv)

DEPLOYMENT_NAME="${ENVIRONMENT}-cluster"
echo "Creating Infrastructure [${DEPLOYMENT_NAME}]..."

terraform apply -auto-approve \
  -var dd_api_key=$DD_APIKEY \
  -var aks_sp_client_id=$SP_APPID \
  -var aks_sp_client_secret=$SP_PASSWD \
  -var deployment_name=$DEPLOYMENT_NAME \
  -var current_azid=$CURRENT_AZID


echo "Deploying App [guestbook]..."

az aks get-credentials --name $DEPLOYMENT_NAME --resource-group $DEPLOYMENT_NAME
#kubectl apply -f aks-service/helm-rbac.yaml
kubectl apply -f aks-service/guestbook.yaml
kubectl apply -f aks-service/guestbook-ilb-service.yaml

