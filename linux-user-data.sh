#!/bin/sh
# -------------------------------------------------------- #
# Check for Admin User
# -------------------------------------------------------- #

if [ `whoami` != 'root' ]
then
 printf "\n\nLogin as ROOT to execute this Script. Exiting...\n\n\n"
 exit 1
fi


# -------------------------------------------------------- #
# Variable Initialization
# -------------------------------------------------------- #

X=`date +'%Y%m%d_%H%M'`.mig

TEMP=/tmp/POINSCR_$X
mkdir -p $TEMP

TMP_SSHD=$TEMP/.sshd_cnf_$X
F_SSHD=/etc/ssh/sshd_config

TMP_PAM=$TEMP/.pam.login.$X
F_PAM=/etc/pam.d/login

TMP_ACC=$TEMP/.acc.cnf.tmp_$X
F_ACC=/etc/security/access.conf

TMP_AUTH=$TEMP/.auth.$X
F_AUTH=/etc/sysconfig/authconfig

TMP_SEL=$TEMP/.selc.$X
F_SEL=/etc/selinux/config

F_SUDO=/etc/sudoers
TMP_SUDO=$TEMP/.sudo.$X
ERR=0


# -------------------------------------------------------- #
# Install required Packages
# -------------------------------------------------------- #

sudo yum erase -y 'ntp*' sendmail java-1.7.0-openjdk
sudo yum -y install telnet mailx curl strace wget sssd finger openldap tcpdump nmap bind-utils httpd vim oddjob-mkhomedir traceroute postfix nc dos2unix cyrus-sasl-plain cronie chrony bc lsof top zip mlocate pip3 python3 lvm2 nfs-utils java-1.8.0-openjdk git


curl -O https://bootstrap.pypa.io/get-pip.py
python3 get-pip.py --user
export PATH=~/.local/bin:$PATH
pip3 install awscli --upgrade --user


# -------------------------------------------------------- #
# Backup Config Files
# -------------------------------------------------------- #

for i in $F_SSHD  $F_ACC $F_PAM $F_AUTH $F_SEL /etc/passwd /etc/shadow /etc/group /etc/sudoers /etc/profile /etc/bashrc /etc/fstab /etc/chrony.conf
do
 cp -p $i $i.$X
 ls -lh $i $i.$X
done

authconfig --savebackup authconfig_original_$X


# -------------------------------------------------------- #
# IPTables & TMP mount-point Disable
# -------------------------------------------------------- #
printf "\n\n\t\tIPTables Disablement in Progress."
sleep 1 ; printf "." ; sleep 1 ; printf ".\n\n"

systemctl stop iptables  2>>/dev/null
systemctl disable iptables 2>>/dev/null
systemctl stop firewalld 2>>/dev/null
systemctl mask iptables  2>>/dev/null
systemctl disable firewalld 2>>/dev/null
systemctl mask firewalld  2>>/dev/null
service iptables stop 2>>/dev/null
service iptables status
service firewalld status



# -------------------------------------------------------- #
# Change SELinux Configuration
# -------------------------------------------------------- #

sed "s/^SELINUX=enforcing/SELINUX=permissive/" $F_SEL >$TMP_SEL
cat $TMP_SEL >$F_SEL
/usr/sbin/setenforce 0

echo "SELinux Status"
echo =====================
sestatus


# -------------------------------------------------------- #
# Create Service ID & Local Users for Migration Activities
# -------------------------------------------------------- #


UNUM=2000
LGRP=ec2-user

for LUSR in akilan

do
 if [  `cat  /etc/passwd | grep ^$LUSR: | wc -l  | awk '{print $1}' ` = 0 ]
 then
  #useradd -u $UNUM -s /bin/bash -d /data01/home/$LUSR $LUSR
  useradd -u $UNUM -s /bin/bash $LUSR
  usermod -a -G $LGRP $LUSR
  echo "$LUSR:Welcome123" >$TEMP/newspwd.txt
  /usr/sbin/chpasswd <$TEMP/newspwd.txt
  passwd  $LUSR >>/dev/null

  if [ $LUSR = "appuser" ]
  then
   chage -m0 -M99999 $LUSR
   usermod -a -G svc $LUSR
  fi
  echo User Details for $LUSR
  echo ===================================
  finger $LUSR
  echo "Group Details for "`groups $LUSR`
  chage -l $LUSR
#for password non-expiry
  chage -m0 -M99999 $LUSR
  echo

 else
  printf "\nUser $LUSR already Exists. No modifications done...\n"
 fi
 UNUM=`expr $UNUM + 1 `
 sleep 1
done

# -------------------------------------------------------- #
# Configure Sudo Access
# -------------------------------------------------------- #

if [ `cat  $F_SUDO | grep -v ^# | grep -i akilan | wc -l  | awk '{print $1}' ` != 0 ]
then
 echo "ERROR: $F_SUDO has sudo entries. No Modification Done. Exiting..."
 echo
else
 for i in 1
 do
  echo
  echo "akilan ALL=(ALL) NOPASSWD: ALL"
  echo
  echo "Cmnd_Alias SU_APPUSER = /bin/su appuser, /bin/su - appuser"
  echo "%appuser ALL=(ALL) NOPASSWD: SU_APPUSER"
  echo
 done >>$F_SUDO
fi


# -------------------------------------------------------- #
# Update AUTH Configuration
# -------------------------------------------------------- #

sed "s/^USEPAMACCESS=no/USEPAMACCESS=yes/" /etc/sysconfig/authconfig  >$TMP_AUTH
cat $TMP_AUTH >$F_AUTH

# -------------------------------------------------------- #
# Update ACCESS Configuration
# -------------------------------------------------------- #

if [ `cat  $F_ACC | grep -v ^# | wc -l  | awk '{print $1}' ` = 0 ]
then
 printf "# Various Service Accounts
+ : root : ALL
+ : ec2-user : ALL
+ : svc : ALL

# Local Users' Access
+ : appuser : ALL

# Deny Everybody Else
- : ALL : ALL
" >$TMP_ACC

 cat $TMP_ACC >$F_ACC

# -------------------------------------------------------- #
# Update SSHD Configuration
# -------------------------------------------------------- #

 grep -v ^ClientAliveInterval $F_SSHD | grep -v ^ClientAliveCountMax >$TMP_SSHD
 sed "s/^AllowUsers/# AllowUsers/" $TMP_SSHD >$F_SSHD
 sed "s/^PasswordAuthentication no/PasswordAuthentication yes/" $F_SSHD >$TMP_SSHD

 cat $TMP_SSHD >$F_SSHD

 for i in 1
 do
  echo
  echo ClientAliveInterval 3600
  echo ClientAliveCountMax 5
  echo
 done >>$F_SSHD

else
 ERR=`expr $ERR + 1 `
fi

if [ $ERR = 0 ]
then
 service sshd reload
 authconfig --updateall
else
 printf "Access.conf has entries. Please check and do the updates manually...\n"
fi

