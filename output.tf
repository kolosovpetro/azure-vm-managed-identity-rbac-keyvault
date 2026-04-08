output "ssh_command" {
  value = "ssh razumovsky_r@${module.ubuntu_vm_custom_image_key_auth.public_ip}"
}