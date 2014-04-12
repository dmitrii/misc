#!/bin/bash -f
set -e # stop on error

if [ "$GIT_NAME" == "" ] ; then
    echo GIT_NAME must be set
    exit 1
fi

if [ "$GIT_EMAIL" == "" ] ; then
    echo GIT_EMAIL must be set
    exit 1
fi

if [ "$KEY_BASE" == "" ] ; then
    echo KEY_BASE must be set
    exit 1
fi

KEYS_HOST="${HOME}/.ssh/${KEY_BASE} ${HOME}/.ssh/${KEY_BASE}.pub"

for KEY in $KEYS_HOST ; do
    if [ ! -e $KEY ] ; then
	echo "$KEY is not readable"
	exit 1
    fi
done

KEY="$1"
DEST="$2"
if [ "$KEY" == "" ] ; then
    echo expecting ssh key name as 1st parameter
    exit 1
fi
if [[ $DEST != *@* ]] ; then
	echo expecting user@host as 2nd parameter
	exit 1
fi
SSH_OPTS="-i /root/$KEY"

echo copying SSH keys to ${DEST}
echo using scp $SSH_OPTS $KEYS_HOST ${DEST}:/tmp
scp $SSH_OPTS $KEYS_HOST ${DEST}:/tmp
echo

echo preparing imaging worker in ${DEST} for development
ssh $SSH_OPTS ${DEST} \
    KEY_BASE=\'$KEY_BASE\' \
    GIT_NAME=\'$GIT_NAME\' \
    GIT_EMAIL=\'$GIT_EMAIL\' 'bash -s' <<'ENDSSH'
sudo -E bash
mv /tmp/${KEY_BASE} /root/.ssh
mv /tmp/${KEY_BASE}.pub /root/.ssh
chown root.root /root/.ssh/${KEY_BASE}*
echo "Host git git.eucalyptus-systems.com" > /root/.ssh/config
echo "  IdentityFile /root/.ssh/${KEY_BASE}" >> /root/.ssh/config
echo "created /root/.ssh/config with:"
cat /root/.ssh/config
eval `ssh-agent`
ssh-add /root/.ssh/${KEY_BASE}

echo installing software
if which aptitude >/dev/null 2>&1 ; then
  aptitude install -y vim emacs23-nox git gdb screen tmux swig python-dev
else
  yum install -y vim emacs-nox git gdb screen tmux ctags gcc openssl-devel libcurl-devel libvirt-devel
fi

DEST=/mnt
MD=$DEST/eucalyptus/Makedefs
TI=$DEST/eucalyptus/tools/imaging
IM=$DEST/eucalyptus/storage/imager

echo installing euca2ools source
cd $DEST
if git clone https://github.com/eucalyptus/euca2ools; then
    cd euca2ools
    python setup.py build
fi

echo installing imaging worker source
cd $DEST
if git clone https://github.com/eucalyptus/eucalyptus-imaging-worker; then
    cd eucalyptus-imaging-worker
    python setup.py build
fi

echo installing eucalyptus source
cd $DEST
if git clone ssh://repo-euca@git.eucalyptus-systems.com/eucalyptus; then
    echo patching source tree to avoid running 'configure'
    echo "CC=gcc" >$MD
    echo "TOP=/mnt/eucalyptus" >>$MD
    echo "INSTALL=/usr/bin/install -c" >>$MD
    echo "INCLUDES=-I\$(TOP)/util -I\$(TOP)/storage -I\$(TOP)/storage/imager -I\$(TOP)/net -I\$(TOP)/node" >>$MD
    echo "CFLAGS= -g -O2 -D_LARGEFILE64_SOURCE  -Wall -fPIC -DHAVE_CONFIG_H -std=gnu99 -g -DDEBUG" >>$MD
    cp $TI/setup.cfg.template.in $TI/setup.cfg.template
    sed -i -e "s/@EUCA_VERSION@$/4.0.0/" $TI/setup.cfg.template
    sed -i -e "s/@prefix@/\//" $TI/setup.cfg.template
    cp $TI/eucatoolkit/__init__.py.in $TI/eucatoolkit/__init__.py
    sed -i -e "s/@prefix@/\//" $TI/eucatoolkit/__init__.py

    echo building the imaging toolkit
    make -C $TI

    echo building the imager
    make -C $IM
fi
ENDSSH
