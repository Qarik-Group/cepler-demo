variable "env_name" {
  type        = string
  description = "Name of environment."
}

variable "env_version" {
  type        = string
  description = "version of environment."
}

data "null_data_source" "values" {
  inputs = {
    env_name = var.env_name
    env_version = var.env_version
  }
}


resource "null_resource" "cluster" {
}

output "env_name" {
  value = data.null_data_source.values.outputs["env_name"]
}

output "env_version" {
  value = data.null_data_source.values.outputs["env_version"]
}
