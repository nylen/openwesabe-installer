#!/bin/bash

shopt -s expand_aliases

apt_opts="-y"
while getopts "n" o; do
  case $o in
    n) apt_opts="" ;;
  esac
done

# TODO: These will be OS-dependent...
alias sudo=sudo
alias pkg="sudo apt-get install $apt_opts"

cat <<EOF
OpenWesabe installer - v0.1
===========================

You will be asked a series of questions.  Type your answers and press
Enter, or just press Enter to pick the default options [which are in
brackets].

Some steps can take as long as 20-30 minutes.  If the process ends
before showing a message that says "Wesabe should now be running",
that means the installation was aborted due to an error.

EOF

configdir=~/.openwesabe-installer
mkdir -p "$configdir"

[ -e "$configdir/dir" ] && dir=$(cat "$configdir/dir")
dir=${dir:-/opt/wesabe}
echo -n "Enter install directory [$dir]: "
read entry
entry="${entry%/}"
[ -z "$entry" ] || dir="$entry"
echo -n "$dir" > "$configdir/dir"

sudo mkdir -p "$dir" || exit
sudo chown "`id -un`:`id -gn`" "$dir" || exit
cd "$dir"

[ -e "$configdir/gh_user" ] && gh_user=$(cat "$configdir/gh_user")
echo -n "Enter your github username [${gh_user:-"I don't have one"}]: "
#'# (this fixes geany's syntax highlighting from the line above)
read entry
[ -z "$entry" ] || gh_user="$entry"
echo -n "$gh_user" > "$configdir/gh_user"


### install git and download source

pkg git-core || exit

gh_user="$gh_user wesabe"
gh_proto="git http"
gh_mand="pfc brcm-accounts-api" # mandatory repositories
gh_opt="fixofx" # optional repositories

for repo in $gh_mand $gh_opt; do
  if [ ! -d "$repo" ]; then
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
  else
    echo "Skipping already-cloned repo $repo"
    success="$success $repo"
  fi
done

for repo in $gh_mand; do
  if [[ "$success" != *$repo* ]]; then
    echo "Failed to clone repository for '$repo'.  Exiting."
    exit
  fi
done


### install and configure mysql

pkg mysql-server-5.1 || exit

if [ -e "$dir/pfc/config/database.yml" -a \
     -e "$dir/brcm-accounts-api/development/properties" ]; then
  rewrite_db_config=no
else
  rewrite_db_config=yes
fi

if [ $rewrite_db_config = yes ]; then
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
  
  [ -z "$mysql_pw" -o "$mysql_pw" != "$mysql_pw_confirm" ] \
    && echo "Passwords are blank or do not match." && exit
  
  # Retardedly, MySQL doesn't have CREATE USER IF NOT EXISTS
  echo "
  CREATE USER 'wesabe'@'localhost' IDENTIFIED BY '$mysql_pw';
  " | mysql -uroot -p"$mysql_pw_root"
  
  echo "
  GRANT ALL ON pfc_development.* TO 'wesabe'@'localhost';
  GRANT ALL ON pfc_test.* TO 'wesabe'@'localhost';
  " | mysql -uroot -p"$mysql_pw_root" || exit
fi

### brcm setup

pkg openjdk-6-jdk maven2 || exit

cd brcm-accounts-api

if [ $rewrite_db_config = yes ]; then
  cat <<EOF > development.properties
hibernate.dialect=org.hibernate.dialect.MySQL5InnoDBDialect
hibernate.connection.username=wesabe
hibernate.connection.password=$mysql_pw
hibernate.connection.url=jdbc:mysql://localhost:3306/pfc_development
hibernate.generate_statistics=true
EOF
fi

for file in shore-0.2-SNAPSHOT xmlson-1.5.2; do
  for ext in pom jar; do
    if [ ! -e "$file.$ext" ]; then
      wget "http://dl.dropbox.com/u/40652/$file.$ext" || exit
    fi
  done
  mvn install:install-file -Dfile="$file.jar" -DpomFile="$file.pom" || exit
done

pkg rake || exit
if ! rake test; then
  echo -n '
Some tests for the brcm-accounts-api project appear to have failed.
Please review the error message(s) above.  If you have set your system
to a non-US locale, you may see some errors like "expected $8.50 but
got US$8.50" and it is probably OK to continue.  However, if the errors
look more severe, like a failure to build the project, then you need to
fix them before Wesabe will work on your computer.

Press Enter to continue installing Wesabe.

Press Ctrl+C or type exit to exit.

What would you like to do [continue]? '
  read action
  [ "$action" = exit ] && exit
fi


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

sudo gem install bundler --pre --no-ri --no-rdoc || exit
sudo gem install thor --no-ri --no-rdoc || exit
# FIXME: sudo gem install can create ~/.gem as root
sudo chown -R "`id -un`:`id -gn`" "$dir" ~/.gem || exit 1
bundle install --deployment || exit

if [ $rewrite_db_config = yes ]; then
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
fi

bundle exec rake db:setup || exit

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
shopt -s expand_aliases
alias setsid="\`which setsid\`"
(
  cd pfc
  setsid xterm -T pfc -e bash --rcfile "$dir/pfc.bashrc"
) &
(
  cd brcm-accounts-api
  setsid xterm -T brcm -e bash --rcfile "$dir/brcm.bashrc"
) &
EOF
chmod +x start-wesabe-xterm.sh

cat <<EOF > "$dir/pfc.bashrc"
[ -f ~/.bashrc ] && . ~/.bashrc
script/rails server
echo '
To run pfc again, type

script/rails server

and press Enter.
'
EOF

cat <<EOF > "$dir/brcm.bashrc"
[ -f ~/.bashrc ] && . ~/.bashrc
rake run
echo '
To run brcm again, type

rake run

and press Enter.
'
EOF


if [ -z "$DISPLAY" -o -z "`which xterm`" ]; then

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

rm -rf $configdir
