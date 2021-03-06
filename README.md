# OpenWesabe / Mesabe installer

This script is known to install cleanly against Ubuntu or Ubuntu Server
10.04.  It may work on Debian as well (but probably not without some
changes).

To install:

    wget http://tinyurl.com/openwesabe-installer
    bash openwesabe-installer.sh

Then follow the on-screen instructions.  Some steps will take a while.

## Note

If you are starting from a fresh install of Ubuntu, it will probably be
necessary to do at least a `sudo apt-get update`.  I'd also recommend a
`sudo apt-get upgrade`.

If you are NOT starting from a fresh install of Ubuntu, I strongly
recommend that you run the installer script as
`bash openwesabe-installer.sh -n`.  This will prompt you to confirm
package manager actions.

If you encounter the following error:
    E: Couldn't find package maven2
This probably means you need to enable the Universe software repository
(in Ubuntu, see the System -> Administration -> Software Sources tool).

## Prebuilt VMWare images

You can find prebuilt Ubuntu Server VMware images
[here](http://www.thoughtpolice.co.uk/vmware/).  They will also run in
VirtualBox with no problem.
