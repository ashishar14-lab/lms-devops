# ---------- Lookups ----------
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------- Networking ----------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" }
}

resource "aws_subnet" "app_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project}-app-subnet-a" }
}

resource "aws_subnet" "app_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project}-app-subnet-b" }
}

# DB subnet: has a route to the IGW only so Ansible can install packages.
# PostgreSQL (5432) is still locked down to the app security group.
resource "aws_subnet" "db" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project}-db-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.project}-public-rt" }
}

resource "aws_route_table_association" "app_a" {
  subnet_id      = aws_subnet.app_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "app_b" {
  subnet_id      = aws_subnet.app_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "db" {
  subnet_id      = aws_subnet.db.id
  route_table_id = aws_route_table.public.id
}

# ---------- Security groups ----------
resource "aws_security_group" "app" {
  name        = "${var.project}-app-sg"
  description = "Web/App servers: SSH, HTTP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from Management Server / Jenkins"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP via Nginx"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ICMP inside VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project}-app-sg" }
}

resource "aws_security_group" "db" {
  name        = "${var.project}-db-sg"
  description = "DB server: PostgreSQL only from app servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from Management Server (Ansible)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description     = "PostgreSQL from app servers only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  ingress {
    description     = "Ping from app servers"
    from_port       = -1
    to_port         = -1
    protocol        = "icmp"
    security_groups = [aws_security_group.app.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project}-db-sg" }
}

# ---------- Key pair (enables passwordless SSH from Management Server) ----------
resource "aws_key_pair" "mgmt" {
  key_name   = "${var.project}-mgmt-key"
  public_key = file(pathexpand(var.public_key_path))
}

# ---------- EC2 instances ----------
resource "aws_instance" "app" {
  count                  = 2
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = count.index == 0 ? aws_subnet.app_a.id : aws_subnet.app_b.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = aws_key_pair.mgmt.key_name

  root_block_device {
    volume_size = 15
  }
  tags = { Name = "${var.project}-app-server-${count.index + 1}" }
}

resource "aws_instance" "db" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.db.id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = aws_key_pair.mgmt.key_name

  root_block_device {
    volume_size = 15
  }
  tags = { Name = "${var.project}-db-server" }
}

# ---------- Auto-generate Ansible inventory ----------
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"
  content  = <<-EOT
    [app]
    %{for i, inst in aws_instance.app~}
    app${i + 1} ansible_host=${inst.public_ip} private_ip=${inst.private_ip}
    %{endfor~}

    [db]
    db1 ansible_host=${aws_instance.db.public_ip} private_ip=${aws_instance.db.private_ip}

    [all:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=${pathexpand(var.private_key_path)}
    db_private_ip=${aws_instance.db.private_ip}
  EOT
}
