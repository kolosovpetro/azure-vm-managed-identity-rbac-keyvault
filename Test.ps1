az login --identity --allow-no-subscription

az keyvault secret list --vault-name "kv-d01"

az keyvault secret show --vault-name "kv-d01" --name "vm-admin-password"