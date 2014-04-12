#!/bin/bash -f
set -e # stop on error

SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE:-$0}); pwd -P)
SET_UP_IW=set-up-imaging-worker-dev.sh
SET_UP_IW_PATH=/root/$SET_UP_IW
KEY_BASE=id_rsa_euca_qa
KEY_PRIV=${HOME}/.ssh/${KEY_BASE}
KEY_PUB=${HOME}/.ssh/${KEY_BASE}.pub
KEYS_BOTH="${KEY_PRIV} ${KEY_PUB}"
GIT_NAME=$(git config --global user.name)
GIT_EMAIL=$(git config --global user.email)

for KEY in $KEYS_BOTH ; do
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
    
    echo adding public key ${KEY_PUB} to authorized_keys on ${DEST}
    cat ${KEY_PUB} | ssh ${DEST} 'cat >>/root/.ssh/authorized_keys'
    echo
    
    echo starting SSH agent on localhost and adding ${KEY_PRIV} to it
    eval `ssh-agent`
    echo adding key to SSH agent
    ssh-add ${KEY_PRIV}
    echo
    
    SSH_OPTS="-i ${KEY_PRIV}"
fi

echo copying SSH keys to ${DEST}
scp $SSH_OPTS $KEYS_BOTH ${DEST}:/tmp
echo copying $SET_UP_IW to ${DEST}:${SET_UP_IW_PATH}
scp $SSH_OPTS $SCRIPT_DIR/$SET_UP_IW ${DEST}:${SET_UP_IW_PATH}
echo

echo preparing ${DEST} for development
ssh $SSH_OPTS ${DEST} \
    SET_UP_IW_PATH=\'$SET_UP_IW_PATH\' \
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
echo

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
echo 

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
echo

echo configuring imaging worker, if present
source /root/eucarc
IWVMID=$(euca-describe-instances --filter tag-value=euca-internal-imaging-workers | grep INSTANCE | cut -f 2)
if [ "$IWVMID" == "" ] ; then
    echo no imaging worker found
    exit 1
fi
IWADDR=$(euca-describe-instances $IWVMID | grep INSTANCE | cut -f 4)
if [ "$IWADDR" == "" ] ; then
    echo no imaging worker address found
    exit 1
fi
IWKEY=$(euca-describe-instances i-3f039798 | grep INSTANCE | cut -f 7)
if [ "$IWKEY" == "" ] ; then
    echo no imaging worker key found
    exit 1
fi

echo invoking $SET_UP_IW_PATH with $IWKEY root@$IWADDR
bash $SET_UP_IW_PATH $IWKEY root@$IWADDR
ENDSSH
