# Local values
locals {
  boot_disk_name      = var.boot_disk_name != null ? var.boot_disk_name : "${var.name_prefix}-boot-disk"
  linux_vm_name       = var.linux_vm_name != null ? var.linux_vm_name : "${var.name_prefix}-linux-vm"
  vpc_network_name    = var.vpc_network_name != null ? var.vpc_network_name : "${var.name_prefix}-private"
  ydb_serverless_name = var.ydb_serverless_name != null ? var.ydb_serverless_name : "${var.name_prefix}-ydb-serverless"
  bucket_sa_name      = var.bucket_sa_name != null ? var.bucket_sa_name : "${var.name_prefix}-bucket-sa"
  bucket_name         = var.bucket_name != null ? var.bucket_name : "${var.name_prefix}-terraform-bucket-${random_string.bucket_name.result}"
}

# Создание дисков и виртуальных машин
resource "yandex_compute_disk" "boot_disk" {
  for_each = var.zones

  name     = length(var.zones) > 1 ? "${local.boot_disk_name}-${substr(each.value, -1, 0)}" : local.boot_disk_name
  zone     = each.value
  image_id = var.image_id

  type = var.instance_resources.disk.disk_type
  size = var.instance_resources.disk.disk_size
}

resource "yandex_compute_disk" "secondary_disk_a" {
  count = contains(var.zones, "ru-central1-a") ? var.secondary_disks.count : 0

  name = "${var.secondary_disks.name}-a-${count.index}"
  zone = "ru-central1-a"

  type = var.secondary_disks.type
  size = var.secondary_disks.size
}

resource "yandex_compute_disk" "secondary_disk_b" {
  count = contains(var.zones, "ru-central1-b") ? var.secondary_disks.count : 0

  name = "${var.secondary_disks.name}-b-${count.index}"
  zone = "ru-central1-b"

  type = var.secondary_disks.type
  size = var.secondary_disks.size
}

resource "yandex_compute_disk" "secondary_disk_d" {
  count = contains(var.zones, "ru-central1-d") ? var.secondary_disks.count : 0

  name = "${var.secondary_disks.name}-d-${count.index}"
  zone = "ru-central1-d"

  type = var.secondary_disks.type
  size = var.secondary_disks.size
}

resource "yandex_compute_instance" "this" {
  for_each = var.zones

  name                      = length(var.zones) > 1 ? "${local.linux_vm_name}-${substr(each.value, -1, 0)}" : local.linux_vm_name
  allow_stopping_for_update = true
  platform_id               = var.instance_resources.platform_id
  zone                      = each.value

  resources {
    cores  = var.instance_resources.cores
    memory = var.instance_resources.memory
  }

  boot_disk {
    disk_id = yandex_compute_disk.boot_disk[each.value].id
  }

  dynamic "secondary_disk" {
    for_each = each.value == "ru-central1-a" ? yandex_compute_disk.secondary_disk_a : each.value == "ru-central1-b" ? yandex_compute_disk.secondary_disk_b : each.value == "ru-central1-d" ? yandex_compute_disk.secondary_disk_d : []
    content {
      disk_id = try(secondary_disk.value.id, null)
    }
  }

  network_interface {
    subnet_id = {
      for subnet in module.net.public_subnets :
      subnet.zone => subnet.subnet_id
    }[each.value]
    nat            = true    
  }

  metadata = {
    user-data = templatefile("cloud-init.yaml.tftpl", {
      ydb_connect_string = yandex_ydb_database_serverless.this.ydb_full_endpoint,
      bucket_domain_name = module.s3.bucket_domain_name
    })
  }
}

module "net" {
  source = "github.com/terraform-yc-modules/terraform-yc-vpc.git?ref=19a9893f25b2536cea3c9c15c180c905ea37bf9c" # Commit hash for 1.0.7

  network_name = local.vpc_network_name
  create_sg    = false

  public_subnets = [
    for zone in var.zones :
    {
      v4_cidr_blocks = var.subnets[zone]
      zone           = zone
      name           = zone
    }
  ]
}

# Создание Yandex Managed Service for YDB
resource "yandex_ydb_database_serverless" "this" {
  name = local.ydb_serverless_name
  location_id = "ru-central1"
}

module "s3" {
  source = "github.com/terraform-yc-modules/terraform-yc-s3.git?ref=9fc2f832875aefb6051a2aa47b5ecc9a7ea8fde5" # Commit hash for 1.0.2

  bucket_name = local.bucket_name
  
}

resource "random_string" "bucket_name" {
  length  = 8
  special = false
  upper   = false
}

resource "time_sleep" "this" {
  create_duration = "180s"

  depends_on = [ yandex_compute_instance.this ]
}

resource "terraform_data" "stop_instance" {
  for_each = yandex_compute_instance.this

  provisioner "local-exec" {
    command = "yc compute instance stop ${each.value.id}"
  }

  depends_on = [ time_sleep.this ]
}
