# Amazon EKS (Tomcat) and Amazon Aurora PostgreSQL blueprint for Pega

Welcome to blueprint for running Pega platform on EKS ( Tomcat) and Amazon Aurora PostgreSQL. This project is a collection of

1. IaC using Terraform which creates 1/ an EKS cluster with all the necessary add ons reqwuired to install Pega Platform 2/ Aurora PostgreSQL Serverless v2 
2. Creates all the necessary secrets in AWS secrets manager and replicates them as native kubernetes secrets using external secrets operator : https://external-secrets.io/latest/
3. Deploys Pega application using helm charts 1/ installs RULES and DATA schemas onto AuroraPostgreSQL 2/ Installs pega-web and Pega-batch and all the necessary services suchg as Hazelcast in client server mode , Cassandra in Client server mode, Pega-search and Pega-stream.     

< Insert Architecture here>

## Prerequisites :

Pega provided docker images should be available in your private Amazon ECR repository  as shown below . For more information on how to upload Pega-provided docker images, please see the links below 

https://docs-previous.pega.com/client-managed-cloud/87/pega-provided-docker-images

https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html

![plot](./pega/images/Amazon-ECR.png)


## Getting Started

The easiest way to get started with EKS Blueprints is to follow our [Getting Started guide](https://aws-ia.github.io/terraform-aws-eks-blueprints/latest/getting-started/).

## Troubleshooting and Known issues 

To view examples for how you can leverage EKS Blueprints, please see the [examples](https://github.com/aws-ia/terraform-aws-eks-blueprints/tree/main/examples) directory.


## Support & Feedback

EKS Blueprints for Terraform is maintained by AWS Solution Architects. It is not part of an AWS service and support is provided best-effort by the EKS Blueprints community. To post feedback, submit feature ideas, or report bugs, please use the [Issues section](https://github.com/aws-ia/terraform-aws-eks-blueprints/issues) of this GitHub repo. If you are interested in contributing to EKS Blueprints, see the [Contribution guide](https://github.com/aws-ia/terraform-aws-eks-blueprints/blob/main/CONTRIBUTING.md).

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

Apache-2.0 Licensed. See [LICENSE](https://github.com/aws-ia/terraform-aws-eks-blueprints/blob/main/LICENSE).
