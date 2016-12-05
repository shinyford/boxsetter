#!/bin/sh
echo "Scanning for updates..."
date
cd /root/sinatra/boxsetter
export PATH=/usr/local/rvm/gems/ruby-2.1.1/bin:/usr/local/rvm/gems/ruby-2.1.1@global/bin:/usr/local/rvm/rubies/ruby-2.1.1/bin:/usr/local/rvm/bin:/usr/local/lib:/usr/kerberos/sbin:/usr/kerberos/bin:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin
export GEM_PATH=/usr/local/rvm/gems/ruby-2.1.1:/usr/local/rvm/gems/ruby-2.1.1@global
exec ruby -I. ./harvest.rb
echo " "
echo " "
