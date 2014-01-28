#!/bin/bash -f
set -e # stop on error

KEY_BASE=id_rsa_euca_qa
KEYS_HOST="${HOME}/.ssh/${KEY_BASE} ${HOME}/.ssh/${KEY_BASE}.pub"
GIT_NAME=$(git config --global user.name)
GIT_EMAIL=$(git config --global user.email)

for KEY in $KEYS_HOST ; do
    if [ ! -e $KEY ] ; then
	echo "$KEY is not readable"
	exit 1
    fi
done

# without a command-line argument, we assume 
# a local Vagrant deployment built from source
if [ "$1" == "" ] ; then
    echo retrieving SSH options from Vagrant
    SSH_OPTS=$(vagrant ssh-config | awk '{print " -o "$1"="$2}')
    echo $SSH_OPTS
    echo

    DEST="localhost"
    EUCALYPTUS="/"
    EUCALYPTUS_SRC="/vagrant/eucalyptus-src"

# when there are arguments, we assume the first is 
# <user@host> of a host in Euca QA built from source
else
    DEST="$1"
    if [[ $DEST != *@* ]] ; then
	echo expecting user@host as parameter
	exit 1
    fi
    EUCALYPTUS="/opt/eucalyptus"
    EUCALYPTUS_SRC="/root/euca_builder/eee"
fi

echo copying SSH keys to ${DEST}
scp $SSH_OPTS $KEYS_HOST ${DEST}:/tmp
echo

echo preparing ${DEST} for development
ssh $SSH_OPTS ${DEST} \
    KEY_BASE=\'$KEY_BASE\' \
    GIT_NAME=\'$GIT_NAME\' \
    GIT_EMAIL=\'$GIT_EMAIL\' \
    EUCALYPTUS=\'$EUCALYPTUS\' \
    EUCALYPTUS_SRC=\'$EUCALYPTUS_SRC\' 'bash -s' <<'ENDSSH'
sudo -E bash
mv /tmp/${KEY_BASE} /root/.ssh
mv /tmp/${KEY_BASE}.pub /root/.ssh
chown root.root /root/.ssh/${KEY_BASE}*
echo "Host git git.eucalyptus-systems.com" > /root/.ssh/config
echo "  IdentityFile /root/.ssh/${KEY_BASE}" >> /root/.ssh/config
if which aptitude >/dev/null 2>&1 ; then
  aptitude install -y vim emacs23-nox git gdb screen tmux swig python-dev electric-fence
else
  yum install -y vim emacs-nox git gdb screen tmux ctags
fi

echo adding paths to .bash_profile
cat >>/root/.bash_profile <<'ENDBASH'
if [ -d /usr/lib/axis2/ ] ; then 
  export AXIS2C_HOME="/usr/lib/axis2"
elif [ -d "$EUCALYPTUS/packages/axis2c-1.6.0/" ] ; then
  export AXIS2C_HOME="$EUCALYPTUS/packages/axis2c-1.6.0"
else 
  echo "cannot find Axis2C!"
fi
export LD_LIBRARY_PATH=$AXIS2C_HOME/lib:$AXIS2C_HOME/modules/rampart/
export PATH=$PATH:$EUCALYPTUS/usr/lib/eucalyptus
ENDBASH

echo configuring git repo in $EUCALYPTUS_SRC
cd $EUCALYPTUS_SRC
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global core.editor `which vim`
git config --global color.ui true

# if code seems to have come from Github, reset 'origin' to internal repo
git remote -v | grep origin | grep push | head -1 | grep github && \
    git remote set-url origin repo-euca@git.eucalyptus-systems.com:eucalyptus

git submodule foreach git branch --set-upstream testing origin/testing
git branch --set-upstream testing origin/testing
ENDSSH
