# Amazon EKS (Tomcat) and Amazon Aurora PostgreSQL blueprint for Pega

Welcome to blueprint for running Pega platform on EKS ( Tomcat) and Amazon Aurora PostgreSQL. The project is structured as follows

    .
    ├── pega
    │    ├── 1-infrastructure-eks-aurora --> (Terraform code which creates 1. EKS cluster with necessary add-ons 2. Provisions Aurora PostgreSQL Serverless v2   )
    │    ├── 2-secret-management-awssecretsmanager --> (Replicates secrets from external secret store such as AWS Secrets manager as native Kubernetes secrets  )
    │    ├── 3-pega-application-deployment-helm --> (Deploys Pega application components using helm)
     
                                 
![plot](./pega/screenshots/Pega-on-EKS-Architecture.png)

## Important files that require configuration :

/pega/3-pega-application-deployment-helm/pega-credentials-secret.yaml --> This is where you will configure the RDS secret name line # 37 and line #41. 
/pega/3-pega-application-deployment-helm/pega.yaml  --> This is where you will configure you JDBC URL and your ECR Image URLs 


## Prerequisites :

1. Install AWS cli https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
2. Install kubectl https://kubernetes.io/docs/tasks/tools/
3. Install helm https://helm.sh/docs/intro/install/
4. Install terraform https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli
5. Create a private ECR repository of Pega-provided Docker images as shown below. For more information see the links below
                a. https://docs-previous.pega.com/client-managed-cloud/87/pega-provided-docker-images
                b. https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html

![plot](./pega/screenshots/Amazon-ECR.png)


## Getting Started - Please follow these instructions in sequence

STEP 1. Create required Infrastructure using terraform (Create EKS Cluster + required Kubernetes add-ons,provision Aurora database,create all the required secrets and store them in AWS secrets manager)

```
cd ./pega/1-infrastructure-eks-aurora  
```
```
Terraform init
```
```
Terraform apply 
```

Infrastructure creation will take about 20 minutes.

####  Output should look like below  

```
Apply complete! Resources: 95 added, 0 changed, 0 destroyed.

Outputs:

aurora-jdbc-write-url = <<EOT
jdbc:postgresql://pega2-postgresqlv2.cluster-cv7ba80pgvtb.us-east-1.rds.amazonaws.com/pegadb 
 
EOT
configure_kubectl = <<EOT
configure kubectl: aws eks --region us-east-1 update-kubeconfig --name pega2 

EOT
list-of-secrets = toset([
  "rds!cluster-2571d018-7087-402f-997a-7a6c79abc06d"
])

```

Configure kubectl by running command shown in output example 

```
aws eks --region us-east-1 update-kubeconfig --name pega2
```

Make a note of list-of-secrets value ( ```rds!cluster-2571d018-7087-402f-997a-7a6c79abc06d``` in the example above ) This is the name of the secret holding Aurora Username and Password. This secret is automatically created by Aurora when database is provisioned. Alterntaly you can get this secret name by logging into AWS secrets manager from AWS console. 

We will use this value to configure secrets in step#2 

Make a note of JDBC URL - this will be required for configuration during step #3 


STEP 2. Configuring Secrets : Deploy External secret provider configurations in EKS cluster. This consists of deploying 1/ AWS secrets manager as external secret store and 2/ IRSA for Secret Store  to access AWS Secrets 3/External Secret configurations which will import AWS secrets as kubernetes native secrets. 

open file ../2-secret-management-awssecretsmanager/pega-credentials-secret.yaml and update row # 37 and row #41 with value from list-of-secrets output from step #1. In the example above the value is rds!cluster-2571d018-7087-402f-997a-7a6c79abc06d

Once updated run the following commands 
    
```
cd ../2-secret-management-awssecretsmanager 

kubectl apply -f .
```

#### Output should look like below
```
externalsecret.external-secrets.io/pega-credentials-secret created
externalsecret.external-secrets.io/pega-ecr-password created
externalsecret.external-secrets.io/pega-ecr-url created
externalsecret.external-secrets.io/pega-ecr-username created
externalsecret.external-secrets.io/pega-ecr-credentials created
serviceaccount/pega-web-sa created
secretstore.external-secrets.io/aws-secrets-manager created
```

Confirm secrets are imported into kubernetes cluster 

```
kubectl get externalsecrets -n pega-web
```

#### Output should look like below

```
NAME                                                         STORE                 REFRESH INTERVAL   STATUS         READY
externalsecret.external-secrets.io/pega-credentials-secret   aws-secrets-manager   1h                 SecretSynced   True
externalsecret.external-secrets.io/pega-ecr-credentials      aws-secrets-manager   1h                 SecretSynced   True
externalsecret.external-secrets.io/pega-ecr-password         aws-secrets-manager   1h                 SecretSynced   True
externalsecret.external-secrets.io/pega-ecr-url              aws-secrets-manager   1h                 SecretSynced   True
externalsecret.external-secrets.io/pega-ecr-username         aws-secrets-manager   1h                 SecretSynced   True

NAME                                                  AGE     STATUS   CAPABILITIES   READY
secretstore.external-secrets.io/aws-secrets-manager   2m40s   Valid    ReadWrite      True
```

STEP3: Deploy Pega Application components 

##### NOTE: BEFORE YOU BEGIN , Please make sure the Database Password NOT have special characters. Without ensuring this, the installation will fail. See Troubleshooting section fort details 


open file ```../ 3-pega-application-deployment-helm/pega.yaml```. This is the values.yaml for pega-helm-charts. 

Most of the configurations have already been made for you in this file. We just need to update JDBC url and ECR image urls 

Take the JDBC URL from step #1 and update it in row# 41 

Update Respective ECR image Repo URLS ( complete URLS) in row #s 100, 404, 410,432 and 434

Update the Pega Admin Password that you prefer in row #413

Deploy Pega by running the following commands 

##### Note:  For first time installation use --set global.actions.execute=install-deploy flag ( see commands below) This will run pega database installer and  install the rules and database schemas onto Aurora PostgreSQL. 

#### Note:Database installation will take about 30 minutes.

For subsequent installations use flag --set global.actions.execute=deploy. This will skip detabase installer and deploy application components only. 

For more information refer : https://github.com/pegasystems/pega-helm-charts

```
cd ../3-pega-application-deployment-helm

helm repo add pega https://pegasystems.github.io/pega-helm-charts

# First time installation run the following. This will run pega databze installer and deploy pega applications on EKS 

helm install pega pega/pega --namespace pega-web  --values pega.yaml --set global.actions.execute=install-deploy  --no-hooks

# Subsequent installations, run this command. This will skip database installation.

helm install pega pega/pega --namespace pega-web  --values pega.yaml --set global.actions.execute=deploy  --no-hooks
```

#### Output should be like below 

```
NAME: pega
LAST DEPLOYED: Fri Aug 11 11:31:33 2023
NAMESPACE: pega-web
STATUS: deployed
REVISION: 1
TEST SUITE: None
```
You can check the list of Kubernetes Objects deployed along with their status by running the following command 

```kubectl get all -n pega-web```



The easiest way to get started with EKS Blueprints is to follow our [Getting Started guide](https://aws-ia.github.io/terraform-aws-eks-blueprints/latest/getting-started/).



helm repo add pega https://pegasystems.github.io/pega-helm-charts

helm install pega pega/pega --namespace pega-web  --values pega.yaml --set global.actions.execute=install-deploy  --no-hooks

helm install pega pega/pega --namespace pega-web  --values pega.yaml --set global.actions.execute=deploy  --no-hooks



No Hooks will ignore exitence of any external secrets that we have created 


## Troubleshooting and Known issues 

Tomcat doesnt allow spl characters ( & , < etc ) for JDBC password. Rotate the Aurora secrets by going into AWS Secrets Manager --> Select secret created by Aurora --> Rotation Configuration -->  Rotate secrets immediately  

![plot](./pega/screenshots/Rotate-Secrets.png)


use -no-hooks with helm install command to ignore  * secrets "pega-credentials-secret" already exists error

" " //VD  # fixed bug in pega.yaml where ingress.domain should be have some value for ingress template to be invoked. add it as " "


## Support & Feedback

EKS Blueprints for Terraform is maintained by AWS Solution Architects. It is not part of an AWS service and support is provided best-effort by the EKS Blueprints community. To post feedback, submit feature ideas, or report bugs, please use the [Issues section](https://github.com/aws-ia/terraform-aws-eks-blueprints/issues) of this GitHub repo. If you are interested in contributing to EKS Blueprints, see the [Contribution guide](https://github.com/aws-ia/terraform-aws-eks-blueprints/blob/main/CONTRIBUTING.md).

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

Apache-2.0 Licensed. See [LICENSE](https://github.com/aws-ia/terraform-aws-eks-blueprints/blob/main/LICENSE).



---------

# Serverless EKS Cluster using Fargate Profiles

This example shows how to provision a serverless cluster (serverless data plane) using Fargate Profiles.

This example solution provides:

- AWS EKS Cluster (control plane)
- AWS EKS Fargate Profiles for the `kube-system` namespace which is used by the `coredns`, `vpc-cni`, and `kube-proxy` addons, as well as profile that will match on `app-*` namespaces using a wildcard pattern.
- AWS EKS managed addons `coredns`, `vpc-cni` and `kube-proxy`
- AWS Load Balancer Controller add-on deployed through a Helm chart. The default AWS Load Balancer Controller add-on configuration is overridden so that it can be deployed on Fargate compute.
- A [sample-app](./sample-app) is provided to demonstrates how to configure the Ingress so that application can be accessed over the internet.

## Prerequisites:

Ensure that you have the following tools installed locally:

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

## Deploy

To provision this example:

```sh
terraform init
terraform apply
```

Enter `yes` at command prompt to apply

## Validate

The following command will update the `kubeconfig` on your local machine and allow you to interact with your EKS Cluster using `kubectl` to validate the CoreDNS deployment for Fargate.

1. Run `update-kubeconfig` command:

```sh
aws eks --region <REGION> update-kubeconfig --name <CLUSTER_NAME>
```

2. Test by listing all the pods running currently. The CoreDNS pod should reach a status of `Running` after approximately 60 seconds:

```sh
kubectl get pods -A

# Output should look like below
game-2048     deployment-2048-7ff458c9f-mb5xs                 1/1     Running   0          5h23m
game-2048     deployment-2048-7ff458c9f-qc99d                 1/1     Running   0          4h23m
game-2048     deployment-2048-7ff458c9f-rm26f                 1/1     Running   0          4h23m
game-2048     deployment-2048-7ff458c9f-vzjhm                 1/1     Running   0          4h23m
game-2048     deployment-2048-7ff458c9f-xnrgh                 1/1     Running   0          4h23m
kube-system   aws-load-balancer-controller-7b69cfcc44-49z5n   1/1     Running   0          5h42m
kube-system   aws-load-balancer-controller-7b69cfcc44-9vhq7   1/1     Running   0          5h43m
kube-system   coredns-7c9d764485-z247p                        1/1     Running   0          6h1m
```

3. Test that the sample application is now available

```sh
kubectl get ingress/ingress-2048 -n game-2048

# Output should look like this
NAME           CLASS   HOSTS   ADDRESS                                                                  PORTS   AGE
ingress-2048   alb     *       k8s-game2048-ingress2-0d47205282-922438252.us-east-1.elb.amazonaws.com   80      4h28m
```

4. Open the browser to access the application via the ALB address http://k8s-game2048-ingress2-0d47205282-922438252.us-east-1.elb.amazonaws.com/

⚠️ You might need to wait a few minutes, and then refresh your browser.

⚠️ If your Ingress isn't created after several minutes, then run this command to view the AWS Load Balancer Controller logs:

```sh
kubectl logs -n kube-system deployment.apps/aws-load-balancer-controller
```

## Destroy

To teardown and remove the resources created in this example:

```sh
terraform destroy -target="module.eks_blueprints_kubernetes_addons" -auto-approve
terraform destroy -target="module.eks" -auto-approve
terraform destroy -auto-approve
```
