output "connection_string" {
  description = "MongoDB SRV connection string."
  value       = module.cluster.connection_strings.standard_srv
}

output "project_id" {
  description = "Atlas project ID."
  value       = module.project.id
}

output "cluster_id" {
  description = "Atlas cluster ID."
  value       = module.cluster.cluster_id
}
