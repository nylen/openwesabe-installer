#!/bin/bash

unalias -a # is this needed?
shopt -s expand_aliases

# TODO: These will be OS-dependent...
alias sudo=sudo
alias pkg="sudo apt-get install -y"

cat <<EOF
OpenWesabe installer - v0.1
===========================

You will be asked a series of questions.  Type your answers and press
Enter, or just press Enter to pick the default options [which are in
brackets].

Some steps can take as long as 20-30 minutes.  If the process appears
to complete without showing an informative message saying that it
succeeded, that means the installation was aborted due to an error.

EOF

echo -n "Enter install directory [/opt/wesabe]: "
read dir
dir="${dir%/}"
[ x"$dir" = x ] && dir="/opt/wesabe"

sudo mkdir -p "$dir" || exit
sudo chown "`id -un`:`id -gn`" "$dir" || exit
cd "$dir"

echo -n "Enter your github username [I don't have one]: "
read gh_user


### install git and download source

pkg git-core || exit

gh_user="$gh_user wesabe"
gh_proto="git http"
gh_mand="pfc brcm-accounts-api" # mandatory repositories
gh_opt="fixofx" # optional repositories

for repo in $gh_mand $gh_opt; do
  for proto in $gh_proto; do
    for user in $gh_user; do
      if [[ "$success" != *$repo* ]] \
        && git clone "$proto://github.com/$user/$repo.git"; then
        
        success="$success $repo"
        if [ "$user" != wesabe ]; then (
          cd "$repo"
          url="$proto://github.com/wesabe/$repo"
          git remote add upstream "$url" \
            && echo "Added 'upstream' remote for '$repo': $url"
        ) fi
      fi
    done
  done
done

for repo in $gh_mand; do
  if [[ "$success" != *$repo* ]]; then
    echo "Failed to clone repository for '$repo'.  Exiting."
    exit
  fi
done


### install and configure mysql

pkg mysql-server-5.1 || exit

echo -n "Enter MySQL password for 'root' (you may have just set it): "
stty -echo; read mysql_pw_root; stty echo; echo

echo "
CREATE DATABASE IF NOT EXISTS pfc_development;
CREATE DATABASE IF NOT EXISTS pfc_test;
" | mysql -uroot -p"$mysql_pw_root" || exit

echo -n "Enter NEW MySQL password for new user 'wesabe': "
stty -echo; read mysql_pw; stty echo; echo

echo -n "Confirm NEW MySQL password for 'wesabe': "
stty -echo; read mysql_pw_confirm; stty echo; echo

[ x"$mysql_pw" = x -o x"$mysql_pw" != x"$mysql_pw_confirm" ] \
  && echo "Passwords are blank or do not match." && exit

# Retardedly, MySQL doesn't have CREATE USER IF NOT EXISTS
echo "
CREATE USER 'wesabe'@'localhost' IDENTIFIED BY '$mysql_pw';
" | mysql -uroot -p"$mysql_pw_root"

echo "
GRANT ALL ON pfc_development.* TO 'wesabe'@'localhost';
GRANT ALL ON pfc_test.* TO 'wesabe'@'localhost';
" | mysql -uroot -p"$mysql_pw_root" || exit


### brcm setup

pkg openjdk-6-jdk maven2 || exit

cd brcm-accounts-api

cat <<EOF > development.properties
hibernate.dialect=org.hibernate.dialect.MySQL5InnoDBDialect
hibernate.connection.username=wesabe
hibernate.connection.password=$mysql_pw
hibernate.connection.url=jdbc:mysql://localhost:3306/pfc_development
hibernate.generate_statistics=true
EOF

for file in shore-0.2-SNAPSHOT xmlson-1.5.2; do
  for ext in pom jar; do
    wget "http://dl.dropbox.com/u/40652/$file.$ext" || exit
  done
  mvn install:install-file -Dfile="$file.jar" -DpomFile="$file.pom" || exit
done

pkg rake || exit
rake test || exit


### pfc setup

cd ../pfc

pkg g++ libruby1.8 libopenssl-ruby libmysqlclient-dev \
  libxslt1-dev libxml2-dev libonig-dev ruby1.8-dev rdoc \
  || exit

ruby -rrubygems -e "exit 1 if 
  Gem::Version.new('`gem --version`') < Gem::Version.new('1.3.7')" \
  || ( # upgrade rubygems
  
  cd /tmp
  wget http://production.cf.rubygems.org/rubygems/rubygems-1.3.7.tgz
  tar zxf rubygems-1.3.7.tgz
  cd rubygems-1.3.7
  sudo ruby setup.rb || exit 1
  sudo ln -sfv /usr/bin/gem1.8 /usr/bin/gem || exit 1
) || exit

sudo gem install bundler thor || exit
bundle install || exit

(
  cd config
  for f in *.example.yml; do
    cp "$f" "${f%.example.yml}.yml"
  done
)

sed -i \
  "s/\(username\): .*\$/\1: wesabe/; s/\(password\): .*\$/\1: $mysql_pw/" \
  config/database.yml \
  || exit

rake db:setup || exit

cat <<EOF > "$dir/screenrc"
chdir "$dir/pfc"
screen sh -c "script/rails server; bash -i"
title "pfc"

chdir "$dir/brcm-accounts-api"
screen sh -c "rake run; bash -i"
title "brcm"

#chdir "$dir/pfc"
#screen
#title "code"
EOF

cat <<EOF

================================================

Installation complete.  You will now be dropped to a subshell to import
a Wesabe snapshot, if you have one.  Use the following command:

thor snapshot:import path/to/snapshot.zip

When you are done, type exit or press Ctrl+D to continue.

EOF

bash

cd ..
echo

cat <<EOF > start-wesabe-screen.sh
#!/bin/bash
screen -c "$dir/screenrc" -dm
EOF
chmod +x start-wesabe-screen.sh

cat <<EOF > start-wesabe-xterm.sh
#!/bin/bash
cd "$dir"
alias setsid="`which setsid`"
( cd pfc; setsid xterm sh -c "script/rails server; bash" ) &
( cd brcm-accounts-api; setsid xterm sh -c "rake run; bash" ) &
EOF
chmod +x start-wesabe-xterm.sh


if [ x"$DISPLAY" = x -o x"`which xterm`" = x ]; then

start="$dir/start-wesabe-screen.sh"
"$start"
cat <<'EOF'
A GNU screen session has been started with the Wesabe programs running
in it.  You should resume it with `screen -r` and press Ctrl+A, Space
to cycle through the open windows.  If everything looks OK, press
Ctrl+A, D to detach the session and leave it running in the background.

For more information, read the manual page for screen (`man screen`).
EOF

else

start="$dir/start-wesabe-xterm.sh"
"$start"
cat <<EOF
A terminal window has been opened with each of the Wesabe components
running in it.
EOF

fi

cat <<EOF

Wesabe should now be running.  If you want to launch it later,
use the following command:

$start

If everything worked properly, you can now access your copy of Wesabe
by going to http://localhost:3000 in a web browser.  Note that if you
are running Wesabe on a virtual machine, you will have to set up port
forwarding yourself.

It will take a few minutes for the Wesabe components to initialize -
you need to wait for their output to stop scrolling before you try to
load the application.
EOF
