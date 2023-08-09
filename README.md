# Amazon EKS (Tomcat) and Amazon Aurora PostgreSQL blueprint for Pega

Welcome to blueprint for running Pega platform on EKS ( Tomcat) and Amazon Aurora PostgreSQL. The project is structured as follows

    .
    ├── pega
    │    ├── 1-infrastructure-eks-aurora --> (Terraform code which creates 1. EKS cluster with necessary add-ons 2. Provisions Aurora PostgreSQL Serverless v2   )
    │    ├── 2-secret-management-awssecretsmanager --> (Replicates secrets from external secret store such as AWS Secrets manager as native Kubernetes secrets  )
    │    ├── 3-pega-application-deployment-helm --> (Deploys Pega application components using helm)
     
                                 
< Insert Architecture here>

## Important files that require configuration :

/pega/3-pega-application-deployment-helm/pega-credentials-secret.yaml --> This is where you will configure the RDS secret name line # 37 and line #41. 
/pega/3-pega-application-deployment-helm/pega.yaml  --> This is where you will configure you JDBC URL and your ECR Image URLs 


## Prerequisites :

1. Install kubectl https://kubernetes.io/docs/tasks/tools/
2. Install helm https://helm.sh/docs/intro/install/
3. Install terraform https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli
4. Create a private ECR repository of Pega-provided Docker images as shown below. For more information see the links below
                a. https://docs-previous.pega.com/client-managed-cloud/87/pega-provided-docker-images
                b. https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html

                ![plot](.docs/pega/Amazon-ECR.png)


## Getting Started

The easiest way to get started with EKS Blueprints is to follow our [Getting Started guide](https://aws-ia.github.io/terraform-aws-eks-blueprints/latest/getting-started/).



helm repo add pega https://pegasystems.github.io/pega-helm-charts

helm install pega pega/pega --namespace pega-web  --values pega.yaml --set global.actions.execute=install-deploy  --no-hooks

helm install pega pega/pega --namespace pega-web  --values pega.yaml --set global.actions.execute=deploy  --no-hooks



No Hooks will ignore exitence of any external secrets that we have created 


## Troubleshooting and Known issues 

Tomcat doesnt allow spl characters ( & , < etc ) for JDBC password. Rotate the Aurora secrets by going into AWS Secrets Manager --> Select secret created by Aurora --> Rotation Configuration -->  Rotate secrets immediately  

                ![plot](.docs/pega/Rotate-Secrets.png)


use -no-hooks with helm install command to ignore  * secrets "pega-credentials-secret" already exists error

" " //VD  # fixed bug in pega.yaml where ingress.domain should be have some value for ingress template to be invoked. add it as " "


## Support & Feedback

EKS Blueprints for Terraform is maintained by AWS Solution Architects. It is not part of an AWS service and support is provided best-effort by the EKS Blueprints community. To post feedback, submit feature ideas, or report bugs, please use the [Issues section](https://github.com/aws-ia/terraform-aws-eks-blueprints/issues) of this GitHub repo. If you are interested in contributing to EKS Blueprints, see the [Contribution guide](https://github.com/aws-ia/terraform-aws-eks-blueprints/blob/main/CONTRIBUTING.md).

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

Apache-2.0 Licensed. See [LICENSE](https://github.com/aws-ia/terraform-aws-eks-blueprints/blob/main/LICENSE).
