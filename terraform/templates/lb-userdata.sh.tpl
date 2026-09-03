#!/bin/bash
apt update -y
apt install -y nginx

cat > /etc/nginx/sites-available/default << 'NGINXCONF'
upstream backend_servers {
%{ for ip in backend_ips ~}
    server ${ip};
%{ endfor ~}
}

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location / {
        proxy_pass http://backend_servers;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINXCONF

nginx -t
systemctl enable nginx
systemctl restart nginx