variable "availability_zones" {
  description = "Availability Zones for backend servers"
  type        = map(string)

  default = {
    a = "us-east-1a"
    b = "us-east-1b"
  }
}