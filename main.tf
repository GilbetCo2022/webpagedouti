#Define the provider
provider "aws" {
    region = us-east-1
}

#Create a virtual network
resource "aws_vpc" "douti.com-vpc" {
    cidr_block = "12.0.0.0/16"
    tags = {
      "Name" = "app-vpc"
    }
}

#Create your application segment
resource "aws_subnet" "douti.com-subnet" {
    tags = {
      "Name" = "douti.com-subnet"
    }
    vpc_id = aws_vpc.douti.com-vpc.id
    cidr_block = "12.0.1.0/24"
    map_public_ip_on_launch = true
    depends_on= [aws_vpc.douti.com-vpc]
}

#Define routing table
resource "aws_route_table" "douti.com-RT" {
    tags = {
      "Name" = "douti.com-RT"
    }
    vpc_id = aws_vpc.douti.com-vpc.id
}

#Associate subnet with routing table
resource "aws_route_table_association" "douti.com-RTA1" {
    subnet_id = aws_subnet.douti.com-subnet.id
    route_table_id = aws_route_table.douti.com-RT
}

# Create internet gateway for servers to be connected to internet
resource "aws_internet_gateway" "douti.com-igw" {
    tags = {
      "Name" = "douti.com-igw"
    }
    vpc_id = aws_vpc.douti.com-vpc.id
    depends_on = [aws_vpc.douti.com-vpc]
}

#Add default route in routing table to point to internet gateway
resource "aws-route" "default-route" {
    route_table_id = aws_route_table.douti.com-RT.id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.douti.com-igw.id
}

#Create a security group
resource "aws_security_group" "douti.com-sg" {
    tags = {
      "Name" = "douti.com-sg"
    }
    description = "Allow web inbound traffic"
    vpc_id = aws_vpc.douti.com-vpc.id
    ingress {
        protocol = "tcp"
        from_port = 80
        to_port = 80
        cidr_block = ["0.0.0.0/0"]
    }
    
    ingress {
         protocol = "tcp"
        from_port = 22
        to_port = 22
        cidr_block = ["0.0.0.0/0"]
    }

    egress {
        protocol = "-1"
        from_port = 0
        to_port = 0
        cidr_blocks = ["0.0.0.0/0"]
    }
}

#Create a private key which can be used to login to the webserver
resource "tls_private_key" "web-key" {
    algorithm = "RSA"
}

#Save public key attributes from the generated key
resource "aws_key_pair" "web-instance-key" {
    key_name = "web-key"
    public_key = tls_private_key.web-key.public_key_openssh
}

#Save the key to your local system
resource "local_file" "web-key" {
    content = tls_private_key.web-key.private_key_pem
    filename = "web-key.pem"
}

#create your webserver instance
resource "aws_instance" "web" {
    ami = "ami-0d663b04ef21e3c4a"
    instance_type = "t2.micro"
    tags = {
      "name" = "webserver1"
    }
    count = 1
    subnet_id = aws_subnet.douti.com-subnet.id
    key_name = "web-key"
    security_groups = [aws_security_group.douti.com-sg.id]

    provisioner "remote-exec" {
    connection {
        type = "ssh"
        user = "ec2-user"
        private_key = tls_private_key.web-key.private_key_pem
        host = aws_instance.web[0].public_ip
    }
    inline = [
        "sudo yum install httpd php git -y",
        "sudo systemctl restart httpd",
        "sudo systemctl enable httpd",
    ]
}

}

#Create a block volume for data persistence
resource "aws_ebs_volume" "webebs1" {
    availability_zone = aws_instance.web[0].availability_zone
    size              = 1
    tags = {
      "Name" = "ebsvol1"
    }
  
}

#Attach the volume to your instance
resource "aws_volume_attachment" "attach_ebs" {
    depends_on = [aws_ebs_volume.webebs1]
    device_name = "/dev/sdh"
    volume_id = aws_ebs_volume.webebs1.id
    instance_id = aws_instance.web[0].id
    force_detach = true
   
}

#Mount the volume to your instance
resource "null_resource" "nullmount" {
    depends_on = [aws_ebs_volume_attachment.attach_ebs]
    connection {
        type = "ssh"
        user = "ec2-user"
        private_key = tls_private_key.web-key.private_key_pem
        host = aws_instance.web[0].public_ip
    }
     provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4 /dev/xvdh",
      "sudo mount /dev/xvdh /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/vineets300/Webpage1.git  /var/www/html"
    ]
  }
}


#Define s3 ID
locals {
  s3_origin_id = "s3-origin"
}

#Create a bucket to upload your static data like images
resource "aws_s3_bucket" "doutidemonewbucket123" {
    bucket = "doutidemonewbucket123"
    acl    = "public-read-write"
    region = "us-east-1"

    versioning {
      enabled = true
    }

    tags = {
      "Name" = "doutidemonewbucket123"
      Environment = "UAT"
    }

    provisioner "local-exec" {
       command = "git clone https://github.com/vineets300/Webpage1.git web-server-image"
    }
}

#Allow public access to the bucket
resource "aws_s3_bucket_public_access_block" "public-storage" {
    depends_on = [aws_s3_bucket.doutidemonewbucket123]
    bucket = "doutidemonewbucket123"
    acl    = "public-read-write"
    block_public_acls = false
    block_public_policy = false
}

#Upload your data to s3 bucket
resource "aws_s3_bucket_object" "object1" {
    depends_on = [aws_s3_bucket.doutidemonewbucket123]
    bucket = "doutidemonewbucket123"
    acl    = "public-read-write"
    key = "doutidemo1.png"
    source = "web-server-image/Demo1.PNG"
}

#Create a cloudfront distribution for CDN
resource "aws_cloudfront_distribution" "tera-cloufront" {
     depends_on = [aws_s3_bucket_object.object1]
     origin {
       domain_name = aws_s3_bucket.doutidemonewbucket123.bucket
       origin_id = local.s3_origin_id
     }
     enabled = true
    default_cache_behavior {
      allowed_methods =  ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods = ["GET", "HEAD"]
      target_origin_id = local.s3_origin_id

      forwarded_values {
        queries_string = false

        cookies {
            forward = "none"
        }
      }
      viewer_protocol_policy = "allow-all"
      min_ttl = 0
      default_ttl = 3600
      max_ttl = 86400
    }

    restrictions {
        geo_restriction {
            restriction_type = "none"
        }
    }
    viewer_certificate {
        cloudfront_default_certificate = true
    } 
}

#Update the CDN image URL to your webserver code
resource "null_resource" "Rite_Image" {
     depends_on = [aws_ebs_volume_attachment.attach_ebs]
    connection {
        type = "ssh"
        user = "ec2-user"
        private_key = tls_private_key.web-key.private_key_pem
        host = aws_instance.web[0].public_ip
    }
  provisioner "remote-exec" {
        inline = [
            "sudo su << EOF",
                    "echo \"<img src='http://${aws_cloudfront_distribution.tera-cloufront1.domain_name}/${aws_s3_bucket_object.Object1.key}' width='300' height='380'>\" >>/var/www/html/index.html",
                    "echo \"</body>\" >>/var/www/html/index.html",
                    "echo \"</html>\" >>/var/www/html/index.html",
                    "EOF",    
        ]
  }

}

#Succes message and storing the result in a file
resource "null_resource" "result" {
    depends_on = [null_resource.nullmount]
    provisioner "local-exec" {
    command = "echo The website has been deployed successfully and >> result.txt  && echo the IP of the website is  ${aws_instance.Web[0].public_ip} >>result.txt"
  }
}

#Test the application
resource "null_resource" "running the website" {
    depends_on = [null_resource.Write_Image]
    provisioner "local-exec" {
    command = "start chrome ${aws_instance.web[0].public_ip}"
    }
}