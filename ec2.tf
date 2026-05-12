# EC2 SG: Node.js from ALB only; no SSH (use SSM Session Manager).
# General egress uses NAT + VPC-CIDR HTTPS; SSM stack uses interface VPC endpoints (see endpoints.tf); userdata mirrors still need internet HTTPS (rule below).
resource "aws_security_group" "ec2_security_group" {
  name        = "AWS-CloudWatch-EC2-Security-Group-${var.environment}"
  description = "Security group for the EC2 instance (Node.js + Session Manager; no SSH)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Node.js app from ALB"
    from_port       = var.node_app_port
    to_port         = var.node_app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Outbound HTTPS to internal VPC destinations"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Ephemeral return traffic to internal VPC destinations"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Managed_By = "Terraform"
  }
}

# yum/dnf reaches public package mirrors over both HTTPS and HTTP.
#trivy:ignore:AVD-AWS-0104
resource "aws_vpc_security_group_egress_rule" "ec2_https_internet_packages" {
  security_group_id = aws_security_group.ec2_security_group.id
  description       = "HTTPS to internet package repositories"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

#trivy:ignore:AVD-AWS-0104
resource "aws_vpc_security_group_egress_rule" "ec2_http_internet_packages" {
  security_group_id = aws_security_group.ec2_security_group.id
  description       = "HTTP to internet package repositories (dnf/EPEL mirrors)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# Session Manager requires an instance profile with the AWS-managed SSM policy.
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "AWS-CloudWatch-EC2-Role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_agent" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.ec2_cloudwatch_agent.arn
}

resource "aws_iam_instance_profile" "ec2" {
  name = "AWS-CloudWatch-EC2-Profile-${var.environment}"
  role = aws_iam_role.ec2.name
}

locals {
  # LocalStack: keep EC2 in public subnet for simpler emulation (still no public IP on the instance).
  ec2_subnet_id = var.localstack ? aws_subnet.public.id : aws_subnet.private.id
  # Real AWS AMIs are invisible to LocalStack; bundled Docker-backed AMIs satisfy DescribeImages during apply.
  ec2_ami_effective = var.localstack ? var.ec2_ami_localstack : var.ec2_ami
}

# EC2: private subnet on AWS (no public IP), SSM via VPC endpoints + other APIs via NAT; behind ALB for user traffic.
resource "aws_instance" "ec2_instance" {
  ami                         = local.ec2_ami_effective
  instance_type               = "t3.micro"
  subnet_id                   = local.ec2_subnet_id
  vpc_security_group_ids      = [aws_security_group.ec2_security_group.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2.name

  dynamic "metadata_options" {
    for_each = var.localstack ? [] : [1]
    content {
      http_endpoint = "enabled"
      http_tokens   = "required"
    }
  }

  dynamic "root_block_device" {
    for_each = var.localstack ? [] : [1]
    content {
      encrypted = true
    }
  }

  user_data = <<-EOF
              #!/bin/bash
              set -euo pipefail

              PORT="${var.node_app_port}"

              if command -v dnf >/dev/null 2>&1; then
                dnf -y update
                dnf -y install nodejs npm amazon-cloudwatch-agent
              else
                yum -y update
                yum -y install nodejs npm amazon-cloudwatch-agent
              fi

              mkdir -p /opt/node-demo
              cat >/opt/node-demo/server.js <<'JS'
              const http = require("http");

              const port = Number(process.env.PORT || 3000);
              const server = http.createServer((req, res) => {
                let status = 200;
                let body = `hello from node on $${port}\n`;

                if (req.url === "/health") {
                  body = "ok";
                } else if (req.url === "/error") {
                  status = 500;
                  body = "internal error";
                }

                res.writeHead(status, { "Content-Type": "text/plain" });
                res.end(body);

                console.log(JSON.stringify({
                  level: status >= 500 ? "error" : "info",
                  path: req.url,
                  status,
                  timestamp: new Date().toISOString()
                }));
              });

              server.listen(port, "0.0.0.0", () => {
                console.log(`listening on $${port}`);
              });
              JS

              cat >/etc/systemd/system/node-demo.service <<'UNIT'
              [Unit]
              Description=Node demo app
              After=network-online.target
              Wants=network-online.target

              [Service]
              Type=simple
              Environment=PORT=3000
              WorkingDirectory=/opt/node-demo
              ExecStart=/usr/bin/node /opt/node-demo/server.js
              StandardOutput=append:/var/log/nextjs-app.log
              StandardError=append:/var/log/nextjs-app.log
              Restart=always
              RestartSec=2

              [Install]
              WantedBy=multi-user.target
              UNIT

              # Replace PORT in unit if different from 3000
              sed -i "s/Environment=PORT=3000/Environment=PORT=$${PORT}/" /etc/systemd/system/node-demo.service

              mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
              cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWAGENT'
              {
                "agent": {
                  "metrics_collection_interval": 60,
                  "run_as_user": "root"
                },
                "metrics": {
                  "append_dimensions": {
                    "InstanceId": "$${aws:InstanceId}"
                  },
                  "metrics_collected": {
                    "cpu": {
                      "resources": ["*"],
                      "measurement": [
                        "cpu_usage_idle",
                        "cpu_usage_iowait",
                        "cpu_usage_user",
                        "cpu_usage_system"
                      ],
                      "totalcpu": true
                    },
                    "disk": {
                      "resources": ["*"],
                      "measurement": ["used_percent"],
                      "ignore_file_system_types": [
                        "sysfs",
                        "devtmpfs",
                        "tmpfs"
                      ]
                    },
                    "mem": {
                      "measurement": ["mem_used_percent"]
                    }
                  }
                },
                "logs": {
                  "logs_collected": {
                    "files": {
                      "collect_list": [
                        {
                          "file_path": "/var/log/nextjs-app.log",
                          "log_group_name": "/aws/ec2/nextjs/${var.environment}",
                          "log_stream_name": "{instance_id}",
                          "retention_in_days": ${var.cloudwatch_log_retention_days}
                        }
                      ]
                    }
                  }
                }
              }
              CWAGENT

              systemctl daemon-reload
              systemctl enable --now node-demo.service
              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
                -a fetch-config \
                -m ec2 \
                -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
                -s
              EOF

  user_data_replace_on_change = true

  tags = {
    name       = "AWS-CloudWatch-EC2-Instance-${var.environment}"
    Managed_By = "Terraform"
  }
}
