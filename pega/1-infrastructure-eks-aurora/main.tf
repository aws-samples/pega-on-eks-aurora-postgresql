provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {}

locals {
  name   = "pega2" # VD name of your EKS cluster 
  region = "us-east-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
  
  pega_db_name = "pegadb"

  pega_web_namespace = "pega-web"

  tags = {
    Blueprint  = local.name
    GithubRepo = ""
    Author ="Vikrant Dhir"
  }
}

################################################################################
# Cluster
################################################################################

#tfsec:ignore:aws-eks-enable-control-plane-logging
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.12"

  cluster_name                   = local.name
  cluster_version                = "1.25"
  cluster_endpoint_public_access = true
# EKS Addons
  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
    #aws-ebs-csi-driver = {} - remove this add on as it inherits the role of underlying node which does not have implicit permission to provision block storage.
  }
#Data Plane - Compute nodes 
  
  eks_managed_node_groups = {
    initial = {
      instance_types = ["m5.8xlarge"]
      min_size     = 3
      max_size     = 10
      desired_size = 5
    }
  }
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets 

  

  #VD change to private subnet in futuyre and add a NAT gateway as the Elastic search for pega required downlading micronaught libraries

  # Fargate profiles use the cluster primary security group so these are not utilized
  #create_cluster_security_group = false
  #create_node_security_group    = false
  tags = local.tags
}
################################################################################
# Create Namespace for PEGA and other resources such as external secrets 
################################################################################

resource "kubernetes_namespace" "pega" {
  metadata {
    name = local.pega_web_namespace
  }
}

resource "kubernetes_namespace" "external-secret" {
  metadata {
    name = "external-secret"
  }
}


################################################################################
# Kubernetes Addons - Load balancer controller and EFS CSI Driver  Add on 
################################################################################


module "eks_blueprints_kubernetes_addons" {
  source = "../../modules/kubernetes-addons"

  eks_cluster_id       = module.eks.cluster_name
  eks_cluster_endpoint = module.eks.cluster_endpoint
  eks_oidc_provider    = module.eks.oidc_provider
  eks_cluster_version  = module.eks.cluster_version

  enable_aws_load_balancer_controller = true 
  aws_load_balancer_controller_helm_config = {
    set_values = [
      {
        name  = "vpcId"
        value = module.vpc.vpc_id
      },
      {
        name  = "podDisruptionBudget.maxUnavailable"
        value = 1
      },
    ]
  }

  #enable_aws_efs_csi_driver = false #CSI EFS Driver is currently not a managed ADD ON
  # enable_amazon_eks_aws_ebs_csi_driver = false 
  enable_self_managed_aws_ebs_csi_driver = true #This self managed CSI EBS driver will auto create all the required IRSA and Service accounts. With EKS Managed Add ON that requires a custom config . so picking self managed one 
  enable_argocd = true # enable argocd for workload management 
  
  # enable secret store csi driver and aws provider - see https://secrets-store-csi-driver.sigs.k8s.io/concepts for details 
  
  #enable_secrets_store_csi_driver = true # VD add secret store csi driver. This driver runs as daemonset and interfaces with Kubectl to mount / unmount the secrets as pod volumes
  #enable_secrets_store_csi_driver_provider_aws = true #runs as daemonset which will interact with AWS secret manager to copy secrets to local k8s secret stores based on SecretProviderClass Object 

  tags = local.tags

}

/*
###########################################################################################################
# Provision EFS file system  and add mount targtes mapping to private subnets 
###########################################################################################################

resource "aws_efs_file_system" "efs-file-system" {
  creation_token = "efs-file-system"
  tags = local.tags
}


resource "aws_efs_mount_target" "efs-mount-target" {
   count = length(module.vpc.private_subnets)
   file_system_id  = aws_efs_file_system.efs-file-system.id
   subnet_id = module.vpc.private_subnets[count.index]
   security_groups = [module.eks.node_security_group_id] //use the same security group id that APi server uses to communicated with nodes 
   
 }
*/


################################################################################
# Provision Aurora PostgreSQL Serverless v2 
################################################################################

# DB subnet group for Aurora
resource "aws_db_subnet_group" "this" {
  name        = "${local.name}-postgresqlv2"
  description = "For Aurora cluster ${local.name}"
  subnet_ids  = module.vpc.private_subnets 
  tags = local.tags
}

data "aws_rds_engine_version" "postgresql" {
  engine  = "aurora-postgresql"
  version = "14.5"
}

module "aurora_postgresql_v2" {
  source = "terraform-aws-modules/rds-aurora/aws"

  name              = "${local.name}-postgresqlv2"
  engine            = data.aws_rds_engine_version.postgresql.engine
  engine_mode       = "provisioned"
  engine_version    = data.aws_rds_engine_version.postgresql.version
  storage_encrypted = true
  master_username   = "TestUser"
  database_name     = local.pega_db_name//VD : create a default DB with the name pegadb
  //enable_http_endpoint = true //VD : enable data api for query editor 
  //publicly_accessible  = true // VD : make it publicly accessible to run queries from PgAdmin
  vpc_id               = module.vpc.vpc_id
  db_subnet_group_name = module.vpc.database_subnet_group_name
  security_group_rules = {
    vpc_ingress = {
      from_port= 0
      to_port= 65535
      protocol= "tcp"
      cidr_blocks = module.vpc.public_subnets_cidr_blocks // VD for security :  restrict DB traffic from public subnets 
    }
  }
 
  monitoring_interval = 60

  apply_immediately   = true
  skip_final_snapshot = true

  serverlessv2_scaling_configuration = {
    min_capacity = 2
    max_capacity = 10
  }

  instance_class = "db.serverless" // VD Aurora serverless 
  instances = {
    one = {}
    two = {}
  }

  tags = local.tags
}


################################################################################
# Add Aurora PostgreSQL JDBC Writer Endpoint, Postgres drivers etc  to Secrets 
################################################################################

resource "aws_secretsmanager_secret" "postgresql-jdbc-url" {
  name = "postgresql-connection-details-v2"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "postgresql-jdbc-url" {
  secret_id = aws_secretsmanager_secret.postgresql-jdbc-url.id
  secret_string = "{\"dbType\":\"postgres\",\"jdbcurl\":\"jdbc:postgresql://${module.aurora_postgresql_v2.cluster_endpoint}/${local.pega_db_name}\",\"driverClass\":\"org.postgresql.Driver\", \"driveruri\":\"http://jdbc.postgresql.org/download/postgresql-42.2.27.jre7.jar\"}"
  depends_on = [module.aurora_postgresql_v2] // VD - create an explicit dependecy on DB creation
}


################################################################################
# Create Secrets for Hazelcast and Cassandra 
################################################################################

resource "random_password" "password_cassandra" {
length = 12
special = false
override_special = "_%@"
}

resource "aws_secretsmanager_secret" "password_cassandra" {
  name = "pega-cassandra-v2"
  recovery_window_in_days = 0 
}


resource "aws_secretsmanager_secret_version" "password_cassandra" {
  secret_id = aws_secretsmanager_secret.password_cassandra.id
  secret_string = "{\"CASSANDRA_USERNAME\":\"${random_password.password_cassandra.result}\",\"CASSANDRA_PASSWORD\":\"${random_password.password_cassandra.result}\"}"
}


resource "random_password" "password_HZCAST" {
length = 12
special = false
override_special = "_%@"
}

resource "aws_secretsmanager_secret" "password_HZCAST" {
name = "pega-hzcast-v2"
recovery_window_in_days = 0 
}

resource "aws_secretsmanager_secret_version" "password_HZCAST" {
  secret_id = aws_secretsmanager_secret.password_HZCAST.id
  secret_string = "{\"HZ_CS_AUTH_PASSWORD\":\"${random_password.password_HZCAST.result}\",\"HZ_CS_AUTH_USERNAME\":\"${random_password.password_HZCAST.result}\"}"
}


################################################################################
# Create IAM permissions for pods to access the secrets 

 #1 IAM policy for read access to secrets
 #2 Roles and IRSA 
################################################################################

resource "aws_iam_policy" "policy" {
  name        = "pega-secrets-policy"
  path        = "/"
  description = "policy for EKS pods to access pega secrets"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
           "secretsmanager:GetSecretValue",
           "secretsmanager:DescribeSecret"
        ]
        Effect   = "Allow"
        Resource = "*"
      
      },
    ]
  })
}


module "secrets_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.28.0"
  role_name = "pega-secrets-role"
  attach_external_secrets_policy = true
  oidc_providers = {
    one = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["pega-web:pega-web-sa", "default:pega-web-sa"]
      }
    }
}


################################################################################
# VD EXTERNAL SECRET STORE CONTROLLER  
#Deploy external secret store such as AWS Secrets manager so that secretas from external store can be synced into native k8s secrets. Similar config can be done for Hashicorp Vault 
# https://aws.amazon.com/blogs/containers/leverage-aws-secrets-stores-from-eks-fargate-with-external-secrets-operator/
################################################################################


resource "helm_release" "external-secrets-operator" {
  name       = "external-secrets"
  namespace  = "external-secret"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "webhook.port"
    value = "9443"
  }
}


################################################################################
# Add Aurora PostgreSQL Database JDBC Url ( Write Endpoint)
################################################################################
/*
resource "aws_secretsmanager_secret" "postgresql-jdbc-credentials" {
  name = ""
}

resource "aws_secretsmanager_secret_version" "postgresql-jdbc-credentials" {
  secret_id = aws_secretsmanager_secret.postgresql-jdbc-credentials.id
  secret_string = "{\"JDBC_WRITE_URL\":\"${module.aurora_postgresql_v2.jdbc_url}\"}"
  
  depends_on = [module.aurora_postgresql_v2] // VD - create an explicit dependecy on DB creation

}
*/



################################################################################
# Add Private ECR endpoint access token to  Secrets 
################################################################################

data "aws_ecr_authorization_token" "token" {

}

data "aws_ecr_repository" "repo" {
  name = "pega-images/platform/pega"
}


resource "aws_secretsmanager_secret" "ecr-token" {
  name = "pega-ecr-credentials-v2"
  recovery_window_in_days = 0 
}

resource "aws_secretsmanager_secret_version" "ecr-token" {
  secret_id = aws_secretsmanager_secret.ecr-token.id
  secret_string = "{\"url\":\"${data.aws_ecr_repository.repo.repository_url}\",\"username\":\"AWS\", \"password\":\"${data.aws_ecr_authorization_token.token.authorization_token}\",\"expiresat\":\"${data.aws_ecr_authorization_token.token.expires_at}\"}"
}






################################################################################
# Supporting VPC Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  map_public_ip_on_launch = true  // Allow public subnets to auto allocate public Ips to launched instances.

  tags = local.tags
}


#vikdhir : WORKLOAD DEPLOYMENT 
/*
################################################################################
# Deploy K88/EKS Manifests for Storage  (PV , PVC  and Storage class) 
################################################################################

resource "kubernetes_manifest" "my-shared-vol-sc-pv" {
  manifest = {
    "apiVersion" = "v1"
    "kind" = "PersistentVolume"
    "metadata" = {
      "name" = "my-shared-vol-pv"
    }
    "spec" = {
      "accessModes" = [
        "ReadWriteMany",
      ]
      "capacity" = {
        "storage" = "1Gi"
      }
      "csi" = {
        "driver" = "efs.csi.aws.com"
        "volumeHandle" = aws_efs_file_system.efs-file-system.id
      }
      "mountOptions" = [
        "rw",
        "lookupcache=pos",
        "noatime",
        "intr",
        "_netdev",
      ]
      "persistentVolumeReclaimPolicy" = "Retain"
      "storageClassName" = "efs-pv"
      "volumeMode" = "Filesystem"
    }
  }
}

resource "kubectl_manifest" "storage-class-ebs" {
    yaml_body = file("${path.module}/atlassian-data-center/jira/storage-class-ebs.yaml")
}

*/

/*
resource "kubectl_manifest" "my-shared-vol-pvc" {
    yaml_body = file("${path.module}/atlassian-data-center/jira/my-shared-vol-pvc.yaml")
}

*/



