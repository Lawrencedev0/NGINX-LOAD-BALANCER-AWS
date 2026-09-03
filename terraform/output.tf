output "backend_private_ips" {
  value = { for k, v in aws_instance.backend : k => v.private_ip }
}

output "lb_public_ip" {
  value = aws_instance.lb.public_ip
}

output "lb_public_dns" {
  value = aws_instance.lb.public_dns
}