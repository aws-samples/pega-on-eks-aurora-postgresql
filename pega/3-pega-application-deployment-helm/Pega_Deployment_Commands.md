



helm repo add pega https://pegasystems.github.io/pega-helm-charts

helm install pega pega/pega --namespace pega-web  --values pega.yaml --set global.actions.execute=install-deploy  --no-hooks

helm install pega pega/pega --namespace pega-web  --values pega.yaml --set global.actions.execute=deploy  --no-hooks



No Hooks will ignore exitence of any external secrets that we have created 