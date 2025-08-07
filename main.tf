terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "0.140.1"
    }
  }
}

# --- Локальные переменные и облачные данные ---
locals {
  folder_id = var.folder_id
  cloud_id  = var.cloud_id
  instance_names = {
    bastion       = "bastion"
    web1          = "web1"
    web2          = "web2"
    monitoring    = "monitoring"
    elasticsearch = "elasticsearch"
    kibana        = "kibana"
  }
  common_tags = {
    project     = "diploma"
    environment = "production"
    terraform   = "true"
  }
}

provider "yandex" {
  cloud_id  = local.cloud_id
  folder_id = local.folder_id
  service_account_key_file = "C:/Terraform/authorized_key.json"
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

# --- Сеть ---
resource "yandex_vpc_network" "main" {
  name = "diploma-network"
}

resource "yandex_vpc_subnet" "public" {
  name           = "public-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

resource "yandex_vpc_subnet" "private-a" {
  name           = "private-subnet-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["192.168.20.0/24"]
  route_table_id = yandex_vpc_route_table.nat.id
}

resource "yandex_vpc_subnet" "private-b" {
  name           = "private-subnet-b"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["192.168.30.0/24"]
  route_table_id = yandex_vpc_route_table.nat.id
}

resource "yandex_vpc_gateway" "nat" {
  name = "nat-gateway"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "nat" {
  name       = "nat-route-table"
  network_id = yandex_vpc_network.main.id
  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id        = yandex_vpc_gateway.nat.id
  }
}

# --- Приватная DNS-зона для ru-central1.internal ---
resource "yandex_dns_zone" "internal" {
  name             = "private-internal-zone"
  zone             = "ru-central1.internal."   # с точкой в конце
  public = false
  private_networks = [ yandex_vpc_network.main.id ]
}

# --- Security Groups ---
resource "yandex_vpc_security_group" "bastion" {
  name        = "bastion-sg"
  network_id  = yandex_vpc_network.main.id
  description = "SG for bastion host"
  ingress {
    description    = "SSH from anywhere"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description    = "Allow all outgoing"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "web" {
  name        = "web-sg"
  network_id  = yandex_vpc_network.main.id
  description = "SG for web servers"
  ingress {
    description       = "HTTP from ALB"
    protocol          = "TCP"
    port              = 80
    security_group_id = yandex_vpc_security_group.alb.id
  }
  ingress {
    description       = "SSH from Bastion"
    protocol          = "TCP"
    port              = 22
    security_group_id = yandex_vpc_security_group.bastion.id
  }
  ingress {
    description       = "Zabbix Agent from Monitoring"
    protocol          = "TCP"
    port              = 10050
    security_group_id = yandex_vpc_security_group.monitoring.id
  }
  egress {
    description    = "Allow all outbound traffic"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "alb" {
  name        = "alb-sg"
  network_id  = yandex_vpc_network.main.id
  description = "SG for ALB"
  ingress {
    description    = "HTTP from Internet"
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description    = "Health checks from YC"
    protocol       = "TCP"
    from_port      = 30080
    to_port        = 31000
    v4_cidr_blocks = ["198.18.235.0/24", "198.18.248.0/24"]
  }
  egress {
    description    = "Allow all outgoing"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "monitoring" {
  name        = "monitoring-sg"
  network_id  = yandex_vpc_network.main.id
  description = "SG for Zabbix"
  ingress {
    description    = "Zabbix Web UI HTTP"
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description    = "Zabbix Web UI HTTPS"
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description    = "SSH from Bastion"
    protocol       = "TCP"
    port           = 22
    security_group_id = yandex_vpc_security_group.bastion.id
  }
  ingress {
    description    = "Zabbix Server port"
    protocol       = "TCP"
    port           = 10051
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description    = "Zabbix Agent checks"
    protocol       = "TCP"
    port           = 10050
    v4_cidr_blocks = ["192.168.20.0/24", "192.168.30.0/24"]
  }
  egress {
    description    = "HTTP/HTTPS"
    protocol       = "TCP"
    from_port      = 80
    to_port        = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "yandex_vpc_security_group" "elasticsearch" {
  name        = "elasticsearch-sg"
  network_id  = yandex_vpc_network.main.id
  description = "SG for Elasticsearch"

  # Filebeat с веб-серверов
  ingress {
    description       = "Filebeat access from web"
    protocol          = "TCP"
    port              = 9200
    security_group_id = yandex_vpc_security_group.web.id
  }

  # HTTP API с бастиона
  ingress {
    description       = "Elasticsearch HTTP from bastion"
    protocol          = "TCP"
    port              = 9200
    security_group_id = yandex_vpc_security_group.bastion.id
  }

  # SSH с бастиона (если потребуется удалённый доступ)
  ingress {
    description       = "SSH from bastion"
    protocol          = "TCP"
    port              = 22
    security_group_id = yandex_vpc_security_group.bastion.id
  }

  egress {
    description    = "Allow all outgoing"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "kibana" {
  name        = "kibana-sg"
  network_id  = yandex_vpc_network.main.id
  description = "SG for Kibana"

  # HTTP UI на публичном и внутреннем IP
  ingress {
    description    = "Kibana HTTP"
    protocol       = "TCP"
    port           = 5601
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP UI через бастион по приватному адресу
  ingress {
    description       = "Kibana HTTP from bastion"
    protocol          = "TCP"
    port              = 5601
    security_group_id = yandex_vpc_security_group.bastion.id
  }

  # SSH с бастиона (если потребуется удалённый доступ)
  ingress {
    description       = "SSH from bastion"
    protocol          = "TCP"
    port              = 22
    security_group_id = yandex_vpc_security_group.bastion.id
  }

  egress {
    description    = "Allow all outgoing"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- ВМ (bastion, web, monitoring, elasticsearch, kibana) ---
resource "yandex_compute_instance" "bastion" {
  name        = local.instance_names.bastion
  hostname    = local.instance_names.bastion
  platform_id = "standard-v3"
  zone        = "ru-central1-a"
  scheduling_policy {
    preemptible = true
  }
  resources {
    cores         = 2
    core_fraction = 20
    memory        = 2
  }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
    }
  }
  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    security_group_ids = [yandex_vpc_security_group.bastion.id]
    nat                = true

    dns_record {
      fqdn = "${local.instance_names.bastion}.ru-central1.internal."
      ptr  = true
    }
  }
  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }
  labels = local.common_tags
}

resource "yandex_compute_instance" "web1" {
  name        = local.instance_names.web1
  hostname    = local.instance_names.web1
  platform_id = "standard-v3"
  zone        = "ru-central1-a"
  scheduling_policy {
    preemptible = true
  }
  resources {
    cores         = 2
    core_fraction = 20
    memory        = 2
  }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
    }
  }
  network_interface {
    subnet_id          = yandex_vpc_subnet.private-a.id
    security_group_ids = [yandex_vpc_security_group.web.id]

   dns_record {
     fqdn = "${local.instance_names.web1}.ru-central1.internal."
     ptr  = true
   }
  }
  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }
  labels = local.common_tags
}

resource "yandex_compute_instance" "web2" {
  name        = local.instance_names.web2
  hostname    = local.instance_names.web2
  platform_id = "standard-v3"
  zone        = "ru-central1-b"
  scheduling_policy {
    preemptible = true
  }
  resources {
    cores         = 2
    core_fraction = 20
    memory        = 2
  }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
    }
  }
  network_interface {
    subnet_id          = yandex_vpc_subnet.private-b.id
    security_group_ids = [yandex_vpc_security_group.web.id]

   dns_record {
     fqdn = "${local.instance_names.web2}.ru-central1.internal."
     ptr  = true
   }
  }
  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }
  labels = local.common_tags
}

resource "yandex_compute_instance" "monitoring" {
  name        = local.instance_names.monitoring
  hostname    = local.instance_names.monitoring
  platform_id = "standard-v3"
  zone        = "ru-central1-a"
  scheduling_policy {
    preemptible = true
  }
  resources {
    cores         = 2
    core_fraction = 20
    memory        = 4
  }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 20
    }
  }
  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    security_group_ids = [yandex_vpc_security_group.monitoring.id]
    nat                = true

   dns_record {
     fqdn = "${local.instance_names.monitoring}.ru-central1.internal."
     ptr  = true
   }
  }
  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }
  labels = local.common_tags
}

resource "yandex_compute_instance" "elasticsearch" {
  name        = local.instance_names.elasticsearch
  hostname    = local.instance_names.elasticsearch
  platform_id = "standard-v3"
  zone        = "ru-central1-a"
  scheduling_policy {
    preemptible = true
  }
  resources {
    cores         = 2
    core_fraction = 20
    memory        = 2
  }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 20
    }
  }
  network_interface {
    subnet_id          = yandex_vpc_subnet.private-a.id
    security_group_ids = [yandex_vpc_security_group.elasticsearch.id]

   dns_record {
     fqdn = "${local.instance_names.elasticsearch}.ru-central1.internal."
     ptr  = true
   }
  }
  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }
  labels = local.common_tags
}

resource "yandex_compute_instance" "kibana" {
  name        = local.instance_names.kibana
  hostname    = local.instance_names.kibana
  platform_id = "standard-v3"
  zone        = "ru-central1-a"
  scheduling_policy {
    preemptible = true
  }
  resources {
    cores         = 2
    core_fraction = 20
    memory        = 2
  }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
    }
  }
  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    security_group_ids = [yandex_vpc_security_group.kibana.id]
    nat                = true

   dns_record {
     fqdn = "${local.instance_names.kibana}.ru-central1.internal."
     ptr  = true
   }
  }
  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"}
  labels = local.common_tags
}

# --- Application Load Balancer (ALB) ---
resource "yandex_alb_target_group" "web" {
  name = "web-target-group"
  target {
    subnet_id  = yandex_vpc_subnet.private-a.id
    ip_address = yandex_compute_instance.web1.network_interface.0.ip_address
  }
  target {
    subnet_id  = yandex_vpc_subnet.private-b.id
    ip_address = yandex_compute_instance.web2.network_interface.0.ip_address
  }
}

resource "yandex_alb_backend_group" "web" {
  name = "web-backend-group"
  http_backend {
    name             = "web-backend"
    weight           = 1
    port             = 80
    target_group_ids = [yandex_alb_target_group.web.id]
    healthcheck {
      timeout  = "3s"
      interval = "5s"
      http_healthcheck {
        path = "/"
      }
    }
  }
}

resource "yandex_alb_http_router" "web" {
  name = "web-router"
}

resource "yandex_alb_virtual_host" "web" {
  name           = "web-host"
  http_router_id = yandex_alb_http_router.web.id
  route {
    name = "web-route"
    http_route {
      http_route_action {
        backend_group_id = yandex_alb_backend_group.web.id
      }
    }
  }
}

resource "yandex_alb_load_balancer" "web" {
  name               = "web-alb"
  network_id         = yandex_vpc_network.main.id
  security_group_ids = [yandex_vpc_security_group.alb.id]
  allocation_policy {
    location {
      zone_id   = "ru-central1-a"
      subnet_id = yandex_vpc_subnet.public.id
    }
  }
  listener {
    name = "web-listener"
    endpoint {
      address {
        external_ipv4_address {}
      }
      ports = [80]
    }
    http {
      handler {
        http_router_id = yandex_alb_http_router.web.id
      }
    }
  }
}

# --- Backup: Snapshot Schedule ---
resource "yandex_compute_snapshot_schedule" "daily" {
  name = "daily-snapshot"
  schedule_policy {
    expression = "0 3 * * *" # каждый день в 3:00
  }
  retention_period = "168h" # 7 дней
  snapshot_count   = 7
  disk_ids = [
    yandex_compute_instance.bastion.boot_disk[0].disk_id,
    yandex_compute_instance.web1.boot_disk[0].disk_id,
    yandex_compute_instance.web2.boot_disk[0].disk_id,
    yandex_compute_instance.monitoring.boot_disk[0].disk_id,
    yandex_compute_instance.elasticsearch.boot_disk[0].disk_id,
    yandex_compute_instance.kibana.boot_disk[0].disk_id,
  ]
  labels = local.common_tags
}

# --- Outputs (FQDN для ansible) ---
output "web_instances_fqdn" {
  value = [
    "${yandex_compute_instance.web1.name}.ru-central1.internal",
    "${yandex_compute_instance.web2.name}.ru-central1.internal"
  ]
  description = "FQDN names of web instances for Ansible inventory"
}
output "bastion_fqdn" {
  value       = "${yandex_compute_instance.bastion.name}.ru-central1.internal"
  description = "FQDN of bastion host"
}
output "monitoring_fqdn" {
  value       = "${yandex_compute_instance.monitoring.name}.ru-central1.internal"
  description = "FQDN of monitoring server"
}
output "elasticsearch_fqdn" {
  value       = "${yandex_compute_instance.elasticsearch.name}.ru-central1.internal"
  description = "FQDN of elasticsearch server"
}
output "kibana_fqdn" {
  value       = "${yandex_compute_instance.kibana.name}.ru-central1.internal"
  description = "FQDN of kibana server"
}
output "alb_external_ip" {
  value       = yandex_alb_load_balancer.web.listener[0].endpoint[0].address[0].external_ipv4_address[0].address
  description = "External IP address of ALB"
}
output "ssh_connection_command" {
  value       = "ssh -J ubuntu@${yandex_compute_instance.bastion.name}.ru-central1.internal ubuntu@${yandex_compute_instance.web1.name}.ru-central1.internal"
  description = "SSH command to connect to web1 via bastion"
}
