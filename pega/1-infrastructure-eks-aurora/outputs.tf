output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig | aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}


output "aurora-jdbc-write-url" {
  description = "Aurora JDBC Url required to be configured in ../3-pega-application-deployment-helm/pega.yaml"
  value       = "Aurora JDBC Url to be configured in ../3-pega-application-deployment-helm/pega.yaml | jdbc:postgresql://${module.aurora_postgresql_v2.cluster_endpoint}/${local.pega_db_name}"
}
