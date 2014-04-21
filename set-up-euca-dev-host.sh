#!/bin/bash -f

SCRIPT_NAME=$(basename ${BASH_SOURCE:-$0})
SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE:-$0}); pwd -P)
SCRIPT_PATH=$SCRIPT_DIR/$SCRIPT_NAME
SCRIPT_PATH_REMOTE=/root/$SCRIPT_NAME
KEY_PATH_REMOTE=/root/euca-dev-key
HOST=$(hostname)
unset SSH_AGENT_PID # so that earlier invocations dont' interfere

err ()
{
    echo "ERROR: $1" >&2
    exit 1
}

msg() # a colorful status output, with a prefix
{
    echo
    echo -n $HOST
    echo -ne " \e[1;33m" # turn on color
    echo "$1"
    echo -e "\e[0m" # turn off color
    echo
}

cleanup () # always called when script exits
{
    if [ "$SSH_AGENT_PID" != "" ] ; then
        msg terminating SSH agent with PID $SSH_AGENT_PID
        kill $SSH_AGENT_PID
    fi
}

trap cleanup EXIT

inherit_or_default ()
{
    VARNAME="$1"
    VARDESC="$2"
    INHERITED="$3"
    DEFAULT="$4"

    if [ "$INHERITED" != "" ] ; then
        echo "$INHERITED"
    elif [ "$DEFAULT" != "" ] ; then
        echo "$DEFAULT"
    else
        err "cannot find $VARDESC to use (set env variable $VARNAME)"
    fi
}

check_file ()
{
    FILEPATH="$1"

    if [ ! -e $FILEPATH ] ; then
        err "required file '$FILEPATH' does not exist"
    fi
}

check_ssh_keys ()
{
    PRIVATE_KEY_PATH=$(inherit_or_default "PRIVATE_KEY_PATH" "private SSH key" "$PRIVATE_KEY_PATH" "${HOME}/.ssh/id_rsa_euca_qa")
    msg "will use private SSH key '$PRIVATE_KEY_PATH' (override with env variable PRIVATE_KEY_PATH)"
    check_file $PRIVATE_KEY_PATH
    PUBLIC_KEY_PATH=$(inherit_or_default "PUBLIC_KEY_PATH" "public SSH key" "$PUBLIC_KEY_PATH" "${PRIVATE_KEY_PATH}.pub")
    msg "will use public SSH key '$PUBLIC_KEY_PATH' (override with env variable PUBLIC_KEY_PATH)"
    check_file $PUBLIC_KEY_PATH
    msg "SSH keys look good"
}

check_git_conf ()
{
    msg "checking git configuration..."
    GIT_NAME_DISCOVERED=$(git config --global user.name)
    GIT_NAME=$(inherit_or_default "GIT_NAME" "name for git" "$GIT_NAME" "$GIT_NAME_DISCOVERED")
    GIT_EMAIL_DISCOVERED=$(git config --global user.email)
    GIT_EMAIL=$(inherit_or_default "GIT_EMAIL" "email for git" "$GIT_EMAIL" "$GIT_EMAIL_DISCOVERED")
    msg "will use '$GIT_NAME <$GIT_EMAIL>' for git commits"
}

configure_git () # be sure to call check_ssh_keys and check_git_conf before this
{
    SSH_CONFIG=${HOME}/.ssh/config
    msg "setting git configuration in $SSH_CONFIG"
    echo "Host git git.eucalyptus-systems.com" >$SSH_CONFIG
    echo "  IdentityFile $PRIVATE_KEY_PATH" >>$SSH_CONFIG
    echo "Host github github.com" >>$SSH_CONFIG
    echo "  IdentityFile $PRIVATE_KEY_PATH" >>$SSH_CONFIG
    git config --global user.name "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"
    git config --global core.editor `which vim`
    git config --global color.ui true
    cat $SSH_CONFIG
    echo
}

setup_ssh_access ()
{
    USERHOST="$1"

    msg "adding public key ${PUBLIC_KEY_PATH} to authorized_keys on ${USERHOST}"
    cat ${PUBLIC_KEY_PATH} | ssh ${USERHOST} 'cat >>/root/.ssh/authorized_keys'
    echo

    msg "starting SSH agent on $HOST and adding ${PRIVATE_KEY_PATH} to it"
    eval `ssh-agent`
    echo adding key to SSH agent
    ssh-add ${PRIVATE_KEY_PATH}
    echo

    SSH_OPTS="-i ${PRIVATE_KEY_PATH}"
}

do_scp ()
{
    msg "copying via SCP file '$1' to '$2'"
    scp $SSH_OPTS $1 $2
}

scp_keys_and_script ()
{
    msg "ensuring SSH tools are installed remotely"
    ssh $SSH_OPTS ${DEST} yum install -y openssh-clients
    msg "copying over SSH keys and the script"
    do_scp ${PRIVATE_KEY_PATH} ${DEST}:${KEY_PATH_REMOTE}
    do_scp ${PUBLIC_KEY_PATH}  ${DEST}:${KEY_PATH_REMOTE}.pub
    do_scp $SCRIPT_PATH ${DEST}:${SCRIPT_PATH_REMOTE}
    echo
}

devbox_remote()
{
    DEST="$1"

    if [ "$DEST" == "" ] ; then
        err "usage: $0 devbox-remote [vagrant | user@host]"
    fi
    check_ssh_keys
    check_git_conf
    echo

    # a local Vagrant deployment built from source
    if [ "$1" == "vagrant" ] ; then
        echo retrieving SSH options from Vagrant
        SSH_OPTS=$(vagrant ssh-config | awk '{print " -o "$1"="$2}')
        echo $SSH_OPTS
        echo

        DEST="localhost"
        EUCALYPTUS="/"
        EUCALYPTUS_SRC="/vagrant/eucalyptus-src"

    # <user@host> of a host in Euca QA built from source
    else
        if [[ $DEST != *@* ]] ; then
            err "expecting user@host as parameter"
        fi
        EUCALYPTUS="/opt/eucalyptus"
        EUCALYPTUS_SRC="/root/euca_builder/eee"

        setup_ssh_access $DEST
    fi

    scp_keys_and_script
    echo

    msg "preparing ${DEST} for eucalyptus development"
    cmd="$SCRIPT_PATH_REMOTE devbox"
    echo "executing on $DEST '$cmd'"
    ssh $SSH_OPTS ${DEST} \
        PRIVATE_KEY_PATH=\'$KEY_PATH_REMOTE\' \
        GIT_NAME=\'$GIT_NAME\' \
        GIT_EMAIL=\'$GIT_EMAIL\' \
        EUCALYPTUS=\'$EUCALYPTUS\' \
        EUCALYPTUS_SRC=\'$EUCALYPTUS_SRC\' $cmd
}

devbox()
{
    msg "installing software required on the devbox"
    if which aptitude >/dev/null 2>&1 ; then
      aptitude install -y vim emacs23-nox git gdb screen tmux swig python-dev electric-fence
    else
      yum install -y vim emacs-nox git gdb screen tmux ctags
    fi
    echo

    DEST='localhost'
    check_ssh_keys
    check_git_conf
    configure_git
    echo

    echo adding paths to .bash_profile
    cat >>$HOME/.bash_profile <<-'ENDBASH'
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
    IWKEYNAME=$(euca-describe-instances $IWVMID | grep INSTANCE | cut -f 7)
    if [ "$IWKEYNAME" == "" ] ; then
        echo no imaging worker key found
        exit 1
    fi
    IWKEYPATH="$HOME/$IWKEYNAME"
    if [ ! -e $IWKEYPATH ] ; then
	IWKEYPATH="${IWKEYPATH}.pem"
	if [ ! -e $IWKEYPATH ] ; then
	    echo no imaging worker key file found in $IWKEYPATH
            exit 1
        fi
    fi
 
    cmd="$SCRIPT_PATH iworker-remote $IWKEYPATH root@$IWADDR"
    echo "executing on $DEST '$cmd'"
    $cmd

    msg "done setting up the development box"
}

iworker_remote ()
{
    KEY="$1"
    DEST="$2"
    if [ "$KEY" == "" ] ; then
        err "usage: $0 iworker-remote <worker SSH key path> <user@worker-vm-address>"
    fi
    if [[ $DEST != *@* ]] ; then
        err "usage: $0 iworker-remote <worker SSH key path> <user@worker-vm-address>"
    fi
    SSH_OPTS="-i $KEY"

    check_ssh_keys
    check_git_conf
    scp_keys_and_script
    echo

    echo "preparing ${DEST} for imaging worker development"
    cmd="$SCRIPT_PATH_REMOTE iworker"
    echo "executing on $DEST '$cmd'"
    ssh $SSH_OPTS ${DEST} \
        PRIVATE_KEY_PATH=\'$PRIVATE_KEY_PATH\' \
        GIT_NAME=\'$GIT_NAME\' \
        GIT_EMAIL=\'$GIT_EMAIL\' $cmd
}

iworker ()
{
    msg "installing software required on the imaging worker"
    if which aptitude >/dev/null 2>&1 ; then
      aptitude install -y vim emacs23-nox git gdb screen tmux swig python-dev
    else
      yum install -y vim emacs-nox git gdb screen tmux ctags gcc openssl-devel libcurl-devel libvirt-devel
    fi

    DEST='localhost'
    check_ssh_keys
    check_git_conf
    configure_git
    echo

    DEST=/mnt

    msg "installing euca2ools source"
    cd $DEST
    if git clone https://github.com/eucalyptus/euca2ools; then
        cd euca2ools
        python setup.py build
    fi

    msg "installing imaging worker source"
    cd $DEST
    if git clone https://github.com/eucalyptus/eucalyptus-imaging-worker; then
        cd eucalyptus-imaging-worker
        python setup.py build
    fi

    msg "starting SSH agent on $HOST and adding ${PRIVATE_KEY_PATH} to it"
    eval `ssh-agent`
    echo adding key to SSH agent
    ssh-add ${PRIVATE_KEY_PATH}
    echo

    msg "installing eucalyptus source"
    MD=$DEST/eucalyptus/Makedefs
    TI=$DEST/eucalyptus/tools/imaging
    IM=$DEST/eucalyptus/storage/imager
    cd $DEST
    if git clone ssh://repo-euca@git.eucalyptus-systems.com/eucalyptus; then
        msg "patching source tree to avoid running 'configure'"
        echo "PYTHON=python" >$MD
        echo "CC=gcc" >>$MD
        echo "TOP=/mnt/eucalyptus" >>$MD
        echo "INSTALL=/usr/bin/install -c" >>$MD
        echo "INCLUDES=-I\$(TOP)/util -I\$(TOP)/storage -I\$(TOP)/storage/imager -I\$(TOP)/net -I\$(TOP)/node" >>$MD
        echo "CFLAGS= -g -O2 -D_LARGEFILE64_SOURCE  -Wall -fPIC -DHAVE_CONFIG_H -std=gnu99 -g -DDEBUG" >>$MD
        cp $TI/setup.cfg.template.in $TI/setup.cfg.template
        sed -i -e "s/@EUCA_VERSION@$/4.0.0/" $TI/setup.cfg.template
        sed -i -e "s/@prefix@/\//" $TI/setup.cfg.template
        cp $TI/eucatoolkit/__init__.py.in $TI/eucatoolkit/__init__.py
        sed -i -e "s/@prefix@/\//" $TI/eucatoolkit/__init__.py

        msg "building the imaging toolkit"
        make -C $TI

        msg "building the imager"
        make -C $IM
    fi
    
    msg "done setting up the imaging worker!"
}

case "$1" in
    devbox)         devbox ;;
    devbox-remote)  devbox_remote $2 ;;
    iworker)        iworker ;;
    iworker-remote) iworker_remote $2 $3;;
    *)
    echo "usage: $0 {devbox|devbox-remote|iworker|iworker-remote}" >&2
    exit 1
esac
