#!/bin/bash
#
# A sample custom service for CloudCenter.
# This creates a Nginx webserver on Centos 6 or 7.
#
# This script creates yum REPO for nginx
# Installs nginx from the vendors repo at nginx.org
# Configures nginx to serve static content from /var/www/html
# Downloads content from a user supplied github repo and places it in /var/www/html
# Starts nginx
# adjusts firewalld on CentOS 7/RHEL 7 to allow traffic on TCP ports 80 and 443 
#
# Authors - Adam Ordal, Ian Logan, Matthew Good 

exec > >(tee -a /usr/local/osmosix/logs/nginx_$$.log) 2>&1

OSSVC_HOME=/usr/local/osmosix/service
. /usr/local/osmosix/etc/.osmosix.sh
. /usr/local/osmosix/etc/userenv
# . $OSSVC_HOME/utils/cfgutil.sh
# . $OSSVC_HOME/utils/install_util.sh
# . $OSSVC_HOME/utils/os_info_util.sh
# . $OSSVC_HOME/utils/agent_util.sh
#

configureRepo ()
{
dist=`cat /etc/system-release | awk '{print $1}'`
case $dist in
  CentOS)
    OS=centos
    ;;
  RedHat)
    OS=rhel
    ;;
  *)
  exit 127
  ;;
esac

#
# This uses a "here documenent"
# cat <<EOF > /path/to/file
# Everything until the letter E O F without the spaces will by copied into the file /path/to/file.
# You can use any string of characters you want in place of E O F, just make sure its not a character
# or string that will appear in your actual file.
# EOF this content will also not appear in the file
# This line will not appear in the file

if [[ ! -f /etc/yum.repos.d/nginx.repo ]]
then
  cat <<EOF >> /etc/yum.repos.d/nginx.repo
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/$OS/\$releasever/\$basearch/
gpgcheck=0
enabled=1
priority=19
EOF
fi
}

installNginx ()
{
  yum install -y nginx nginx-module-\* 2>&1 > /root/nginx_install.log
}

#The Cliqr repo by default has priority 1, highest priority.
#The cliqr repo includes a much older version of nginx, so we temporarily lower the 
#priority of the cliqr repo, install nginx from the vendor repo, and the restore the cliqr
#repo priority
lowerCliqrRepoPriority ()
{
  #cliqr Repo
  sed -i s/priority=1/priority=20/ /etc/yum.repos.d/cliqr.repo
}

raiseCliqrRepoPriority ()
{
  sed -i s/priority=20/priority=1/ /etc/yum.repos.d/cliqr.repo

}

startNginx ()
{
  if [[ $majversion -le 6 ]]
  then
    service nginx start
  elif [[ $majversion -ge 7 ]]
  then
    systemctl start nginx
  fi
}

stopNginx ()
{
  if [[ $majversion -le 6 ]]
  then
    service nginx stop
  elif [[ $majversion -ge 7 ]]
  then
    systemctl stop nginx
  fi
}

configureNginx ()
{
  sed -i s/^/\#/ /etc/nginx/conf.d/default.conf
  cat << FOE > /etc/nginx/conf.d/main.conf
  server {
      listen       80;
      server_name  _;

      #charset koi8-r;
      #access_log  /var/log/nginx/log/host.access.log  main;

      location / {
          root   /var/www/html;
          index  index.html index.htm;
      }

      #error_page  404              /404.html;

      # redirect server error pages to the static page /50x.html
      #
      error_page   500 502 503 504  /50x.html;
      location = /50x.html {
          root   /usr/share/nginx/html;
      }

      # proxy the PHP scripts to Apache listening on 127.0.0.1:80
      #
      #location ~ \.php$ {
      #    proxy_pass   http://127.0.0.1;
      #}

      # pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
      #
      #location ~ \.php$ {
      #    root           html;
      #    fastcgi_pass   127.0.0.1:9000;
      #    fastcgi_index  index.php;
      #    fastcgi_param  SCRIPT_FILENAME  /scripts$fastcgi_script_name;
      #    include        fastcgi_params;
      #}

      # deny access to .htaccess files, if Apache's document root
      # concurs with nginx's one
      #
      #location ~ /\.ht {
      #    deny  all;
      #}
  }
FOE
}

#The environment variable cccGitHubRepoURL is defined in the service profile in Cloud Center
deployContent ()
{
  mkdir -p /var/www/html
  cd /var/www/html
  git clone --depth 1 $cccGitHubRepoURL .
  # chmod 000 .git
}

installGit ()
{
  rpm -qa | grep -q git
  if [[ ! -z $? ]]
  then
    yum install -y git
  fi
}

installLSB ()
{
  rpm -qa | grep -q redhat-lsb
  if [[ ! -z $? ]]
  then
    yum install -y redhat-lsb
  fi
}

openFirewallD ()
{
  firewall-cmd --permanent --add-service=http
  firewall-cmd --permanent --add-service=https
  firewall-cmd --add-service=http
  firewall-cmd --add-service=https
}

#Ensure git and lsb packages are installed.
installGit
installLSB

majversion=$(/usr/bin/lsb_release -rs | cut -f1 -d.)
minversion=$(/usr/bin/lsb_release -rs | cut -f2 -d.)

case $1 in
  install)
    if [[ $majversion -ge 7 ]]
    then
      openFirewallD
    fi
    installGit
    configureRepo
    lowerCliqrRepoPriority
    installNginx
    raiseCliqrRepoPriority
    ;;
  stop)
    stopNginx
    ;;
  start)
    startNginx
    ;;
  restart)
    stopNginx
    sleep 3
    startNginx
    ;;
  deploy)
    configureNginx
    deployContent
    ;;
  upgrade)
    stopNginx
    lowerCliqrRepoPriority
    yum update -y nginx
    yum update -y nginx-module\*
    raiseCliqrRepoPriority
    startNginx
    ;;
  *)
    exit 127
esac
